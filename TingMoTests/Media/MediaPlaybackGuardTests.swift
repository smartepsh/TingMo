import XCTest
@testable import TingMo

final class MediaPlaybackGuardTests: XCTestCase {
    private nonisolated final class Spy: @unchecked Sendable {
        private let lock = NSLock()
        private var storedSnapshot = MediaPlaybackGuard.PlaybackSnapshot(isPlaying: false, pid: nil)
        private var storedPauseAccepted = true
        private var storedPauseCount = 0
        private var storedPlayCount = 0
        private var storedQueryCount = 0
        var pauseChangesPlaybackState = true

        var snapshot: MediaPlaybackGuard.PlaybackSnapshot {
            get { withLock { storedSnapshot } }
            set { withLock { storedSnapshot = newValue } }
        }

        var pauseAccepted: Bool {
            get { withLock { storedPauseAccepted } }
            set { withLock { storedPauseAccepted = newValue } }
        }

        var pauseCount: Int { withLock { storedPauseCount } }
        var playCount: Int { withLock { storedPlayCount } }
        var queryCount: Int { withLock { storedQueryCount } }

        func query() -> MediaPlaybackGuard.PlaybackSnapshot {
            withLock {
                storedQueryCount += 1
                return storedSnapshot
            }
        }

        func pause() -> Bool {
            withLock {
                storedPauseCount += 1
                guard storedPauseAccepted else { return false }
                if pauseChangesPlaybackState {
                    storedSnapshot.isPlaying = false
                }
                return true
            }
        }

        func play() -> Bool {
            withLock {
                storedPlayCount += 1
                storedSnapshot.isPlaying = true
                return true
            }
        }

        private func withLock<Result>(_ operation: () -> Result) -> Result {
            lock.lock()
            defer { lock.unlock() }
            return operation()
        }
    }

    private func makeGuard(spy: Spy) -> MediaPlaybackGuard {
        MediaPlaybackGuard(
            queryPlayback: { spy.query() },
            pausePlayback: { spy.pause() },
            resumePlayback: { spy.play() },
            retryDelay: 0
        )
    }

    func testPlayingMediaIsPausedAndResumedForSameApplication() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: true, pid: 42)
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        let result = await guard_.beginSession(id: sessionID)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(result, .ready)
        XCTAssertEqual(spy.pauseCount, 1)
        XCTAssertEqual(spy.playCount, 1)
    }

    func testPlayingMediaWithoutPIDIsPausedAndResumed() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: true, pid: nil)
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        let result = await guard_.beginSession(id: sessionID)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(result, .ready)
        XCTAssertEqual(spy.pauseCount, 1)
        XCTAssertEqual(spy.playCount, 1)
    }

    func testInitiallyPausedMediaReceivesNoCommands() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: false, pid: 42)
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        let result = await guard_.beginSession(id: sessionID)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(result, .ready)
        XCTAssertEqual(spy.pauseCount, 0)
        XCTAssertEqual(spy.playCount, 0)
    }

    func testNoNowPlayingApplicationReceivesNoCommands() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: false, pid: nil)
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        _ = await guard_.beginSession(id: sessionID)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(spy.pauseCount, 0)
        XCTAssertEqual(spy.playCount, 0)
    }

    func testUnknownPlaybackStateRetriesThenContinuesWithoutCommands() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: nil, pid: nil)
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        let result = await guard_.beginSession(id: sessionID)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(result, .unverified)
        XCTAssertEqual(spy.queryCount, 2)
        XCTAssertEqual(spy.pauseCount, 0)
        XCTAssertEqual(spy.playCount, 0)
    }

    func testRejectedPauseDoesNotCreateResumeDebt() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: true, pid: 42)
        spy.pauseAccepted = false
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        let result = await guard_.beginSession(id: sessionID)
        spy.snapshot = .init(isPlaying: false, pid: 42)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(result, .unverified)
        XCTAssertEqual(spy.pauseCount, 1)
        XCTAssertEqual(spy.playCount, 0)
    }

    func testAcceptedPauseStillCreatesDebtWhenConfirmationIsUnavailable() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: true, pid: 42)
        spy.pauseChangesPlaybackState = false
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        let result = await guard_.beginSession(id: sessionID)
        spy.snapshot = .init(isPlaying: false, pid: 42)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(result, .unverified)
        XCTAssertEqual(spy.pauseCount, 1)
        XCTAssertEqual(spy.playCount, 1)
    }

    func testUnknownResumeStateNeverSendsPlayWhenPausedApplicationWasKnown() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: true, pid: 42)
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        _ = await guard_.beginSession(id: sessionID)
        spy.snapshot = .init(isPlaying: nil, pid: nil)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(spy.playCount, 0)
    }

    func testPIDLessSessionPaysResumeDebtWithoutAnotherStateQuery() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: true, pid: nil)
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        _ = await guard_.beginSession(id: sessionID)
        spy.snapshot = .init(isPlaying: nil, pid: nil)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(spy.playCount, 1)
    }

    func testResumesWhenPIDBecomesUnavailableAfterPause() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: true, pid: 42)
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        _ = await guard_.beginSession(id: sessionID)
        spy.snapshot = .init(isPlaying: false, pid: nil)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(spy.playCount, 1)
    }

    func testDoesNotResumeWhenUserAlreadyResumedManually() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: true, pid: 42)
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        _ = await guard_.beginSession(id: sessionID)
        spy.snapshot = .init(isPlaying: true, pid: 42)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(spy.playCount, 0)
    }

    func testDoesNotResumeWhenNowPlayingApplicationChanged() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: true, pid: 42)
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        _ = await guard_.beginSession(id: sessionID)
        spy.snapshot = .init(isPlaying: false, pid: 99)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(spy.playCount, 0)
    }

    func testEndSessionResumesAtMostOnce() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: true, pid: 42)
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        _ = await guard_.beginSession(id: sessionID)
        await guard_.endSession(id: sessionID)
        await guard_.endSession(id: sessionID)

        XCTAssertEqual(spy.playCount, 1)
    }

    func testCancelSessionPaysTheSameResumeDebt() async {
        let spy = Spy()
        spy.snapshot = .init(isPlaying: true, pid: 42)
        let guard_ = makeGuard(spy: spy)
        let sessionID = UUID()

        _ = await guard_.beginSession(id: sessionID)
        await guard_.cancelSession(id: sessionID)

        XCTAssertEqual(spy.playCount, 1)
    }
}
