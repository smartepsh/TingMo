import Foundation

/// Session-scoped media interruption for dictation.
///
/// All blocking MediaRemote queries run on a dedicated serial queue, never on
/// the main thread. Commands are explicit pause/play operations; this class
/// deliberately never emits a hardware-key toggle.
nonisolated final class MediaPlaybackGuard: @unchecked Sendable {
    struct PlaybackSnapshot: Equatable, Sendable {
        var isPlaying: Bool?
        var pid: pid_t?
    }

    enum BeginResult: Equatable, Sendable {
        /// Media was already quiet, or a requested pause was observed.
        case ready
        /// State could not be verified. Recording may continue fail-open, but
        /// no speculative media command or resume debt is created.
        case unverified
    }

    private struct Session {
        let id: UUID
        var pausedPID: pid_t?
        var owesResume = false
        var beginResult: BeginResult = .unverified
    }

    private let queryPlayback: @Sendable () -> PlaybackSnapshot
    private let pausePlayback: @Sendable () -> Bool
    private let resumePlayback: @Sendable () -> Bool
    private let retryDelay: TimeInterval
    private let queryAttempts: Int
    private let operationQueue = DispatchQueue(
        label: "com.tingmo.media-playback-guard",
        qos: .userInitiated
    )

    /// Accessed only by `operationQueue`.
    private var activeSession: Session?

    init(
        queryPlayback: @escaping @Sendable () -> PlaybackSnapshot = {
            let snapshot = NowPlayingRemote.snapshot()
            return PlaybackSnapshot(isPlaying: snapshot.isPlaying, pid: snapshot.pid)
        },
        pausePlayback: @escaping @Sendable () -> Bool = { NowPlayingRemote.pause() },
        resumePlayback: @escaping @Sendable () -> Bool = { NowPlayingRemote.play() },
        retryDelay: TimeInterval = 0.025,
        queryAttempts: Int = 2
    ) {
        self.queryPlayback = queryPlayback
        self.pausePlayback = pausePlayback
        self.resumePlayback = resumePlayback
        self.retryDelay = retryDelay
        self.queryAttempts = max(1, queryAttempts)
    }

    /// Inspect the current Now Playing session and pause it only when it is
    /// definitely playing and has a stable PID. Unknown state fails open:
    /// recording may continue, but no media command is guessed.
    func beginSession(id: UUID) async -> BeginResult {
        await withCheckedContinuation { continuation in
            operationQueue.async { [self] in
                continuation.resume(returning: beginSessionBlocking(id: id))
            }
        }
    }

    /// Pay this session's resume debt, if any, then forget the session.
    func endSession(id: UUID) async {
        await finishSession(id: id)
    }

    /// Cancellation has the same media teardown semantics as a normal end.
    func cancelSession(id: UUID) async {
        await finishSession(id: id)
    }

    private func finishSession(id: UUID) async {
        await withCheckedContinuation { continuation in
            operationQueue.async { [self] in
                if activeSession?.id == id {
                    finishActiveSessionBlocking()
                }
                continuation.resume()
            }
        }
    }

    private func beginSessionBlocking(id: UUID) -> BeginResult {
        if activeSession?.id == id {
            return activeSession?.beginResult ?? .unverified
        }

        // Defensive cleanup: callers should serialize sessions, but a stale
        // debt must never be silently discarded if they do not.
        if activeSession != nil {
            finishActiveSessionBlocking()
        }

        activeSession = Session(id: id)

        guard let snapshot = initialSnapshotWithRetry() else {
            return .unverified
        }
        guard snapshot.isPlaying == true else {
            activeSession?.beginResult = .ready
            return .ready
        }
        guard let pid = snapshot.pid else {
            return .unverified
        }

        guard pausePlayback() else {
            return .unverified
        }

        // The explicit pause was accepted, so this exact session now owns one
        // resume debt even if confirmation times out.
        activeSession?.pausedPID = pid
        activeSession?.owesResume = true

        // Give mediaremoted a brief opportunity to apply the command, then
        // confirm once. Together with the initial retry this keeps worst-case
        // recording preparation near 500 ms.
        if retryDelay > 0 {
            Thread.sleep(forTimeInterval: retryDelay)
        }
        let confirmation = queryPlayback()
        let pauseConfirmed = confirmation.isPlaying == false && confirmation.pid == pid
        let result: BeginResult = pauseConfirmed ? .ready : .unverified
        activeSession?.beginResult = result
        return result
    }

    private func finishActiveSessionBlocking() {
        guard let session = activeSession else { return }
        defer { activeSession = nil }
        guard session.owesResume, let pausedPID = session.pausedPID else { return }

        guard let snapshot = resumeSnapshotWithRetry() else { return }
        guard snapshot.pid == pausedPID else { return }

        // The user may have resumed manually while recording. Explicit play
        // is needed only when the same app remains paused.
        guard snapshot.isPlaying == false else { return }
        _ = resumePlayback()
    }

    /// For recording start, `false` is conclusive even when there is no PID.
    /// `true` requires a PID so any pause can later be restored safely.
    private func initialSnapshotWithRetry() -> PlaybackSnapshot? {
        queryWithRetry { snapshot in
            snapshot.isPlaying == false ||
                (snapshot.isPlaying == true && snapshot.pid != nil)
        }
    }

    /// Resume requires both state and identity; otherwise no play command is
    /// sent to a potentially unrelated Now Playing app.
    private func resumeSnapshotWithRetry() -> PlaybackSnapshot? {
        queryWithRetry { snapshot in
            snapshot.isPlaying != nil && snapshot.pid != nil
        }
    }

    private func queryWithRetry(
        isConclusive: (PlaybackSnapshot) -> Bool
    ) -> PlaybackSnapshot? {
        for attempt in 0..<queryAttempts {
            let snapshot = queryPlayback()
            if isConclusive(snapshot) { return snapshot }
            if attempt + 1 < queryAttempts, retryDelay > 0 {
                Thread.sleep(forTimeInterval: retryDelay)
            }
        }
        return nil
    }
}
