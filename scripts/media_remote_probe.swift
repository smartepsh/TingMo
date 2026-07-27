import Darwin
import Foundation

private final class MediaRemoteProbe {
    private typealias GetBoolFn = @convention(c) (
        dispatch_queue_t,
        @escaping @convention(block) (Bool) -> Void
    ) -> Void
    private typealias GetPIDFn = @convention(c) (
        dispatch_queue_t,
        @escaping @convention(block) (Int32) -> Void
    ) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool

    private let queue = DispatchQueue(label: "com.tingmo.media-remote-probe")
    private let handle: UnsafeMutableRawPointer?
    private let getIsPlaying: GetBoolFn?
    private let getPID: GetPIDFn?
    private let sendCommand: SendCommandFn?

    init() {
        handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW | RTLD_LOCAL
        )
        getIsPlaying = Self.load(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        getPID = Self.load(handle, "MRMediaRemoteGetNowPlayingApplicationPID")
        sendCommand = Self.load(handle, "MRMediaRemoteSendCommand")
    }

    var frameworkLoaded: Bool { handle != nil }
    var symbolsLoaded: Bool {
        getIsPlaying != nil && getPID != nil && sendCommand != nil
    }

    func status() -> (isPlaying: Bool?, pid: pid_t?) {
        let playing: Bool? = getIsPlaying.flatMap { function in
            wait { done in function(queue, done) }
        }
        let pid: pid_t? = getPID.flatMap { function in
            let value: Int32? = wait { done in function(queue, done) }
            guard let value, value > 0 else { return nil }
            return value
        }
        return (playing, pid)
    }

    func send(_ command: Command) -> Bool? {
        sendCommand?(command.rawValue, nil)
    }

    enum Command: Int32 {
        case play = 0
        case pause = 1
    }

    private func wait<T>(
        timeout: TimeInterval = 1,
        start: (@escaping (T) -> Void) -> Void
    ) -> T? {
        let lock = NSLock()
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        start { value in
            lock.lock()
            result = value
            lock.unlock()
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return result
    }

    private static func load<F>(
        _ handle: UnsafeMutableRawPointer?,
        _ name: String
    ) -> F? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: F.self)
    }
}

private func describe(_ value: Bool?) -> String {
    value.map(String.init) ?? "nil (no callback or timeout)"
}

private func printStatus(_ probe: MediaRemoteProbe, label: String) {
    let status = probe.status()
    let pid = status.pid.map(String.init) ?? "nil"
    print("\(label): isPlaying=\(describe(status.isPlaying)), pid=\(pid)")
}

let usage = "Usage: swift scripts/media_remote_probe.swift [status|pause|play]"
let action = CommandLine.arguments.dropFirst().first ?? "status"
guard ["status", "pause", "play"].contains(action) else {
    FileHandle.standardError.write(Data("\(usage)\n".utf8))
    exit(2)
}

private let probe = MediaRemoteProbe()
print("frameworkLoaded=\(probe.frameworkLoaded), symbolsLoaded=\(probe.symbolsLoaded)")
printStatus(probe, label: "before")

if action != "status" {
    let command: MediaRemoteProbe.Command = action == "pause" ? .pause : .play
    let accepted = probe.send(command).map(String.init) ?? "nil (symbol missing)"
    print("\(action) accepted=\(accepted)")
    Thread.sleep(forTimeInterval: 0.3)
    printStatus(probe, label: "after")
}
