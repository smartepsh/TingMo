import Darwin
import Foundation

/// Talks to the system Now Playing session through the private `MediaRemote`
/// framework: reads whether the active Now Playing app is playing, which app
/// it is, and sends it *explicit* pause/play commands.
///
/// Explicit commands are the whole point. The public alternative — posting
/// the hardware play/pause media key — has two failure modes this class
/// exists to eliminate:
///
/// - the key is a **toggle**, so firing it against a paused player *starts*
///   the paused track;
/// - when no Now Playing app exists, macOS (`rcd`) answers the key by
///   **launching Apple Music**.
///
/// `MRMediaRemoteSendCommand(kMRPause)` does neither: it is delivered to the
/// current Now Playing session or dropped when there is none.
///
/// Apple restricted parts of MediaRemote (notably now-playing *info*) behind
/// private entitlements in macOS 15.4, but the three calls used here are
/// verified working from an unentitled process on macOS 26.5. TingMo is not
/// sandboxed (see `TingMo.entitlements`), so the framework can be loaded via
/// `dlopen`. If any symbol is missing or a future macOS locks these calls
/// down, every query returns `nil` ("unknown") and every command becomes a
/// no-op — callers must treat that as "leave the media alone".
nonisolated enum NowPlayingRemote {
    /// How long a synchronous query waits for `mediaremoted` before giving
    /// up and reporting "unknown". The IPC normally answers within a few
    /// milliseconds; this cap only bounds the stall on recording start when
    /// the daemon is unresponsive.
    private static let queryTimeout: TimeInterval = 0.15

    private static let queue = DispatchQueue(label: "com.tingmo.mediaremote", qos: .userInitiated)

    // MARK: - Queries

    struct Snapshot: Equatable, Sendable {
        let isPlaying: Bool?
        let pid: pid_t?
    }

    /// Query playback and app identity in parallel. This method blocks its
    /// caller for at most one query timeout and must therefore run away from
    /// the main thread.
    static func snapshot() -> Snapshot {
        let group = DispatchGroup()
        let box = SnapshotBox()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.isPlaying = isPlaying()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.pid = nowPlayingApplicationPID()
            group.leave()
        }

        group.wait()
        return Snapshot(isPlaying: box.isPlaying, pid: box.pid)
    }

    /// `true` if the active Now Playing app is currently playing, `false`
    /// if it is paused/stopped or no Now Playing app exists, `nil` if the
    /// framework is unavailable or the query timed out.
    static func isPlaying() -> Bool? {
        guard let getIsPlaying else { return nil }
        return syncQuery { done in getIsPlaying(queue) { done($0) } }
    }

    /// PID of the active Now Playing app, or `nil` when there is none (the
    /// framework reports pid 0) or the query could not be answered.
    static func nowPlayingApplicationPID() -> pid_t? {
        guard let getPID else { return nil }
        guard let pid = syncQuery({ done in getPID(queue) { done($0) } }), pid > 0 else {
            return nil
        }
        return pid
    }

    // MARK: - Commands

    /// `MRCommand` values from MediaRemote. Deliberately excludes
    /// `kMRTogglePlayPause` (2) — the toggle is the bug this class replaces.
    private enum Command: Int32 {
        case play = 0
        case pause = 1
    }

    /// Ask the current Now Playing app to pause. Returns whether the system
    /// accepted the command; a no-op when no Now Playing app exists.
    @discardableResult
    static func pause() -> Bool { send(.pause) }

    /// Ask the current Now Playing app to play. Safe against an
    /// already-playing app (no-op) and against no app at all (dropped).
    @discardableResult
    static func play() -> Bool { send(.play) }

    private static func send(_ command: Command) -> Bool {
        guard let sendCommand else { return false }
        return sendCommand(command.rawValue, nil)
    }

    // MARK: - Blocking bridge

    /// Runs an async MediaRemote query and waits (bounded) for its callback,
    /// so callers on the recording path get a fresh answer instead of a
    /// possibly-stale cache.
    private static func syncQuery<T>(_ start: (@escaping (T) -> Void) -> Void) -> T? {
        let box = ResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        start { value in
            box.value = value
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + queryTimeout) == .success else { return nil }
        return box.value
    }

    private final class ResultBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: T?
        var value: T? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); defer { lock.unlock() }; stored = newValue }
        }
    }

    private final class SnapshotBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storedIsPlaying: Bool?
        private var storedPID: pid_t?

        var isPlaying: Bool? {
            get { lock.lock(); defer { lock.unlock() }; return storedIsPlaying }
            set { lock.lock(); defer { lock.unlock() }; storedIsPlaying = newValue }
        }

        var pid: pid_t? {
            get { lock.lock(); defer { lock.unlock() }; return storedPID }
            set { lock.lock(); defer { lock.unlock() }; storedPID = newValue }
        }
    }

    // MARK: - Symbol loaders

    private typealias GetBoolFn = @convention(c) (dispatch_queue_t, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias GetPIDFn = @convention(c) (dispatch_queue_t, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool

    /// Kept open for the lifetime of the process.
    private static let frameworkHandle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_NOW | RTLD_LOCAL
    )

    private static let getIsPlaying: GetBoolFn? = loadFunction(
        name: "MRMediaRemoteGetNowPlayingApplicationIsPlaying"
    )
    private static let getPID: GetPIDFn? = loadFunction(
        name: "MRMediaRemoteGetNowPlayingApplicationPID"
    )
    private static let sendCommand: SendCommandFn? = loadFunction(
        name: "MRMediaRemoteSendCommand"
    )

    private static func loadFunction<F>(as type: F.Type = F.self, name: String) -> F? {
        guard let handle = frameworkHandle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: F.self)
    }
}
