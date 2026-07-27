import XCTest
@testable import TingMo

final class MediaPlaybackGuardTests: XCTestCase {

    private final class Spy {
        /// What the Now Playing query reports: `true` playing, `false`
        /// paused/none, `nil` unknown (framework unavailable or timeout).
        var nowPlaying: Bool?
        var nowPlayingPID: pid_t?
        var pauseCount = 0
        var playCount = 0
    }

    private func makeGuard(spy: Spy) -> MediaPlaybackGuard {
        MediaPlaybackGuard(
            isNowPlayingAppPlaying: { spy.nowPlaying },
            nowPlayingPID: { spy.nowPlayingPID },
            pausePlayback: { spy.pauseCount += 1 },
            resumePlayback: { spy.playCount += 1 }
        )
    }

    func testPausesWhenNowPlayingAppIsPlaying() {
        let spy = Spy()
        spy.nowPlaying = true
        let guard_ = makeGuard(spy: spy)

        guard_.pauseForRecording()

        XCTAssertEqual(spy.pauseCount, 1)
        XCTAssertTrue(guard_.pausedByUs)
    }

    func testDoesNothingWhenNowPlayingAppIsPaused() {
        let spy = Spy()
        spy.nowPlaying = false
        let guard_ = makeGuard(spy: spy)

        guard_.pauseForRecording()
        guard_.resumeAfterRecording()

        XCTAssertEqual(spy.pauseCount, 0)
        XCTAssertEqual(spy.playCount, 0)
        XCTAssertFalse(guard_.pausedByUs)
    }

    func testDoesNothingWhenPlaybackStateIsUnknown() {
        // Unknown state (no Now Playing app, MediaRemote unavailable, query
        // timeout) must never trigger a command — guessing is what used to
        // start paused tracks and launch Apple Music.
        let spy = Spy()
        spy.nowPlaying = nil
        let guard_ = makeGuard(spy: spy)

        guard_.pauseForRecording()
        guard_.resumeAfterRecording()

        XCTAssertEqual(spy.pauseCount, 0)
        XCTAssertEqual(spy.playCount, 0)
        XCTAssertFalse(guard_.pausedByUs)
    }

    func testResumesExactlyOnceAfterPausing() {
        let spy = Spy()
        spy.nowPlaying = true
        spy.nowPlayingPID = 42
        let guard_ = makeGuard(spy: spy)

        guard_.pauseForRecording()
        spy.nowPlaying = false // our own pause took effect
        guard_.resumeAfterRecording()
        guard_.resumeAfterRecording() // second teardown path must be a no-op

        XCTAssertEqual(spy.pauseCount, 1)
        XCTAssertEqual(spy.playCount, 1)
        XCTAssertFalse(guard_.pausedByUs)
    }

    func testNewRecordingResetsStaleResumeState() {
        let spy = Spy()
        spy.nowPlaying = true
        let guard_ = makeGuard(spy: spy)
        guard_.pauseForRecording() // paused, but caller never resumed

        spy.nowPlaying = false
        guard_.pauseForRecording() // next recording starts in silence

        guard_.resumeAfterRecording()
        XCTAssertEqual(spy.playCount, 0, "stale pause must not trigger a resume")
    }

    func testDoesNotResumeWhenUserAlreadyResumedManually() {
        let spy = Spy()
        spy.nowPlaying = true
        spy.nowPlayingPID = 42
        let guard_ = makeGuard(spy: spy)

        guard_.pauseForRecording()
        // User hit play themselves mid-recording; sending another play is
        // harmless but resuming is not our debt anymore — stay out of it.
        guard_.resumeAfterRecording()

        XCTAssertEqual(spy.playCount, 0)
        XCTAssertFalse(guard_.pausedByUs)
    }

    func testDoesNotResumeWhenNowPlayingAppChangedDuringRecording() {
        let spy = Spy()
        spy.nowPlaying = true
        spy.nowPlayingPID = 42
        let guard_ = makeGuard(spy: spy)

        guard_.pauseForRecording()
        spy.nowPlaying = false
        spy.nowPlayingPID = 99 // user switched to a different player
        guard_.resumeAfterRecording()

        XCTAssertEqual(spy.playCount, 0, "must not start an app we never paused")
        XCTAssertFalse(guard_.pausedByUs)
    }

    func testResumesWhenPIDUnavailable() {
        // PID queries can fail independently of the playing query; a missing
        // PID must not strand the media app paused.
        let spy = Spy()
        spy.nowPlaying = true
        spy.nowPlayingPID = nil
        let guard_ = makeGuard(spy: spy)

        guard_.pauseForRecording()
        spy.nowPlaying = false
        guard_.resumeAfterRecording()

        XCTAssertEqual(spy.playCount, 1)
        XCTAssertFalse(guard_.pausedByUs)
    }
}
