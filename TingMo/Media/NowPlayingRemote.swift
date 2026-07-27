import Darwin
import Foundation
import MediaRemoteAdapter

/// Talks to the system Now Playing session: reads whether the active session
/// is playing, which app owns it, and sends explicit pause/play commands.
///
/// **Why reads go through `MediaRemoteAdapter` and not `MediaRemote` directly.**
/// Since macOS 15.4 `mediaremoted` checks the identity of the calling process
/// for *read* requests. A normal signed app is refused with
/// `kMRMediaRemoteFrameworkErrorDomain Code=3 (Operation not permitted)`, but
/// the refusal is silent at the API level: the callback still fires promptly
/// with `isPlaying=false, pid=0`, which is indistinguishable from "nothing is
/// playing". Verified on macOS 26.5.2 — the same code reports real state when
/// hosted by an Apple platform binary and reports nothing when compiled into
/// this app.
///
/// The adapter restores read access by running the framework calls inside
/// `/usr/bin/perl`, which *is* an Apple platform binary, and piping JSON back.
/// There is no entitlement to request and no TCC prompt that grants this.
///
/// Commands are unaffected: `MRMediaRemoteSendCommand` works from an ordinary
/// signed process, so pause/play are still sent directly. The public
/// alternative — posting the hardware play/pause media key — stays rejected:
/// it is a *toggle* (it starts a paused player) and `rcd` answers it by
/// **launching Apple Music** when no Now Playing session exists.
///
/// If the adapter is unavailable or times out, every query returns `nil`
/// ("unknown") and callers must treat that as "leave the media alone".
nonisolated enum NowPlayingRemote {
    /// How long a query waits for the perl subprocess before reporting
    /// "unknown". A healthy round-trip measured ~170 ms on an idle machine, so
    /// this leaves roughly an order of magnitude of headroom for a loaded
    /// system while still bounding the stall on recording start.
    private static let queryTimeout: TimeInterval = 2.0

    private static let queue = DispatchQueue(label: "com.tingmo.mediaremote", qos: .userInitiated)

    // MARK: - Queries

    struct Snapshot: Equatable, Sendable {
        let isPlaying: Bool?
        let pid: pid_t?
    }

    /// Read playback state and app identity in a single subprocess round-trip.
    ///
    /// Both fields come from one `get` call, so unlike the previous two-query
    /// design they always describe the same instant.
    static func snapshot() -> Snapshot {
        guard let payload = trackInfoPayload() else {
            return Snapshot(isPlaying: nil, pid: nil)
        }
        // No Now Playing session at all: the adapter answers with a null
        // payload, which decodes to all-nil fields rather than an error.
        guard let isPlaying = payload.isPlaying else {
            return Snapshot(isPlaying: nil, pid: nil)
        }
        let pid = payload.PID.flatMap { $0 > 0 ? $0 : nil }
        return Snapshot(isPlaying: isPlaying, pid: pid)
    }

    /// `true` if the active Now Playing app is currently playing, `false` if
    /// it is paused/stopped, `nil` if the state could not be read.
    static func isPlaying() -> Bool? { snapshot().isPlaying }

    /// PID of the active Now Playing app, or `nil` when there is none or the
    /// query could not be answered.
    static func nowPlayingApplicationPID() -> pid_t? { snapshot().pid }

    /// One-shot read through the adapter, bounded by `queryTimeout`.
    ///
    /// `getTrackInfo` spawns `perl` and calls back on an internal queue; it has
    /// no timeout of its own, so a wedged helper would otherwise hang the
    /// recording path forever.
    private static func trackInfoPayload() -> TrackInfo.Payload? {
        let box = ResultBox<TrackInfo.Payload>()
        let semaphore = DispatchSemaphore(value: 0)
        // MediaController owns the subprocess plumbing; a fresh instance per
        // query keeps this free of shared mutable state. The callback captures
        // it so that a timed-out query cannot deallocate the controller while
        // its perl child is still running and about to call back.
        let controller = MediaController()
        controller.getTrackInfo { [controller] info in
            withExtendedLifetime(controller) {
                box.value = info?.payload
                semaphore.signal()
            }
        }
        guard semaphore.wait(timeout: .now() + queryTimeout) == .success else {
            NSLog("[TingMo] Now Playing query timed out after \(queryTimeout)s")
            return nil
        }
        return box.value
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
    ///
    /// Note that acceptance only means the command reached `mediaremoted` —
    /// it is returned even when nothing was playing, so it must not be read
    /// as proof that playback stopped.
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

    private final class ResultBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: T?
        var value: T? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); defer { lock.unlock() }; stored = newValue }
        }
    }

    // MARK: - Symbol loaders

    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool

    /// Kept open for the lifetime of the process. Only the *command* symbol is
    /// loaded here; reads go through the adapter (see the type comment).
    private static let frameworkHandle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_NOW | RTLD_LOCAL
    )

    private static let sendCommand: SendCommandFn? = loadFunction(
        name: "MRMediaRemoteSendCommand"
    )

    private static func loadFunction<F>(as type: F.Type = F.self, name: String) -> F? {
        guard let handle = frameworkHandle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: F.self)
    }
}
