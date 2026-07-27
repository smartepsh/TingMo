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

    /// Inspect the current Now Playing session and pause it when playback is
    /// confirmed. Application identity is best-effort: MediaRemote can expose
    /// a valid Now Playing session while withholding or timing out its PID.
    /// Unknown playback state still fails open without sending a command.
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

        let pauseAccepted = pausePlayback()
        #if DEBUG
        NSLog("[TingMo] MediaRemote pause accepted=\(pauseAccepted)")
        #endif
        guard pauseAccepted else {
            NSLog("[TingMo] MediaRemote pause command was rejected")
            return .unverified
        }

        // The explicit pause was accepted, so this exact session now owns one
        // resume debt even if confirmation times out. PID is optional because
        // MediaRemote may report playback without exposing app identity.
        activeSession?.pausedPID = snapshot.pid
        activeSession?.owesResume = true

        // Give mediaremoted a brief opportunity to apply the command, then
        // confirm once. Together with the initial retry this keeps worst-case
        // recording preparation near 500 ms.
        if retryDelay > 0 {
            Thread.sleep(forTimeInterval: retryDelay)
        }
        let confirmation = queryPlayback()
        #if DEBUG
        NSLog(
            "[TingMo] MediaRemote pause confirmation: isPlaying=\(String(describing: confirmation.isPlaying)), pid=\(String(describing: confirmation.pid))"
        )
        #endif
        let pauseConfirmed = confirmation.isPlaying == false &&
            identitiesDoNotConflict(snapshot.pid, confirmation.pid)
        let result: BeginResult = pauseConfirmed ? .ready : .unverified
        activeSession?.beginResult = result
        return result
    }

    private func finishActiveSessionBlocking() {
        guard let session = activeSession else { return }
        defer { activeSession = nil }
        guard session.owesResume else { return }

        guard let snapshot = resumeSnapshotWithRetry() else { return }
        guard identitiesDoNotConflict(session.pausedPID, snapshot.pid) else { return }

        // The user may have resumed manually while recording. Explicit play
        // is needed only when the current session remains paused. When both
        // PIDs are available, a mismatch still protects a different player.
        guard snapshot.isPlaying == false else { return }
        let playAccepted = resumePlayback()
        #if DEBUG
        NSLog("[TingMo] MediaRemote play accepted=\(playAccepted)")
        #endif
        if !playAccepted {
            NSLog("[TingMo] MediaRemote play command was rejected")
        }
    }

    /// Playback state is authoritative for deciding whether to pause. PID is
    /// useful for identity checks when available, but is not a prerequisite.
    private func initialSnapshotWithRetry() -> PlaybackSnapshot? {
        queryWithRetry(label: "begin") { $0.isPlaying != nil }
    }

    /// Resume also requires a known playback state. Identity remains
    /// best-effort because MediaRemote may stop reporting PID after pausing.
    private func resumeSnapshotWithRetry() -> PlaybackSnapshot? {
        queryWithRetry(label: "resume") { $0.isPlaying != nil }
    }

    /// Missing identity is inconclusive rather than a conflict. Only two
    /// known, different PIDs prove that the active player changed.
    private func identitiesDoNotConflict(_ lhs: pid_t?, _ rhs: pid_t?) -> Bool {
        guard let lhs, let rhs else { return true }
        return lhs == rhs
    }

    private func queryWithRetry(
        label: String,
        isConclusive: (PlaybackSnapshot) -> Bool
    ) -> PlaybackSnapshot? {
        for attempt in 0..<queryAttempts {
            let snapshot = queryPlayback()
            #if DEBUG
            NSLog(
                "[TingMo] MediaRemote \(label) query \(attempt + 1)/\(queryAttempts): isPlaying=\(String(describing: snapshot.isPlaying)), pid=\(String(describing: snapshot.pid))"
            )
            #endif
            if isConclusive(snapshot) { return snapshot }
            if attempt + 1 < queryAttempts, retryDelay > 0 {
                Thread.sleep(forTimeInterval: retryDelay)
            }
        }
        return nil
    }
}
