import XCTest
@testable import TingMo

final class MediaPlaybackGuardTests: XCTestCase {

    private final class Spy {
        var playing = false
        var toggleCount = 0
    }

    private func makeGuard(spy: Spy) -> MediaPlaybackGuard {
        MediaPlaybackGuard(
            isSystemAudioPlaying: { spy.playing },
            togglePlayPause: { spy.toggleCount += 1 }
        )
    }

    func testPausesWhenAudioIsPlaying() {
        let spy = Spy()
        spy.playing = true
        let guard_ = makeGuard(spy: spy)

        guard_.pauseForRecording()

        XCTAssertEqual(spy.toggleCount, 1)
        XCTAssertTrue(guard_.pausedByUs)
    }

    func testDoesNothingWhenAudioIsSilent() {
        let spy = Spy()
        spy.playing = false
        let guard_ = makeGuard(spy: spy)

        guard_.pauseForRecording()
        guard_.resumeAfterRecording()

        XCTAssertEqual(spy.toggleCount, 0)
        XCTAssertFalse(guard_.pausedByUs)
    }

    func testResumesExactlyOnceAfterPausing() {
        let spy = Spy()
        spy.playing = true
        let guard_ = makeGuard(spy: spy)

        guard_.pauseForRecording()
        guard_.resumeAfterRecording()
        guard_.resumeAfterRecording() // second teardown path must be a no-op

        XCTAssertEqual(spy.toggleCount, 2)
        XCTAssertFalse(guard_.pausedByUs)
    }

    func testNewRecordingResetsStaleResumeState() {
        let spy = Spy()
        spy.playing = true
        let guard_ = makeGuard(spy: spy)
        guard_.pauseForRecording() // paused, but caller never resumed

        spy.playing = false
        guard_.pauseForRecording() // next recording starts in silence

        guard_.resumeAfterRecording()
        XCTAssertEqual(spy.toggleCount, 1, "stale pause must not trigger a resume")
    }
}
