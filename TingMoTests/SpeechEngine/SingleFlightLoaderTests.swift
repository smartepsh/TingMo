import XCTest
@testable import TingMo

final class SingleFlightLoaderTests: XCTestCase {
    private actor Counter {
        private(set) var value = 0

        func increment() -> Int {
            value += 1
            return value
        }
    }

    private enum TestError: Error {
        case failed
    }

    func testConcurrentCallersShareOneLoadTask() async throws {
        let loader = SingleFlightLoader<Int>()
        let counter = Counter()

        async let first = loader.load {
            let invocation = await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            return invocation
        }
        async let second = loader.load {
            let invocation = await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            return invocation
        }

        let values = try await (first, second)

        let invocationCount = await counter.value
        XCTAssertEqual(values.0, values.1)
        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(loader.status, .loaded)
        XCTAssertEqual(loader.value, values.0)
    }

    func testFailureIsReportedAndNextCallCanRetry() async throws {
        let loader = SingleFlightLoader<Int>()

        do {
            _ = try await loader.load { throw TestError.failed }
            XCTFail("Expected the first load to fail")
        } catch TestError.failed {
            // Expected.
        }

        guard case .failed = loader.status else {
            return XCTFail("Expected a failed load state")
        }

        let value = try await loader.load { 42 }

        XCTAssertEqual(value, 42)
        XCTAssertEqual(loader.status, .loaded)
    }

    func testInvalidatePreventsAnOldTaskFromPublishingItsValue() async throws {
        let loader = SingleFlightLoader<Int>()
        let started = expectation(description: "load started")
        let mayFinish = AsyncStream.makeStream(of: Void.self)

        let loadTask = Task {
            try await loader.load {
                started.fulfill()
                for await _ in mayFinish.stream { break }
                return 7
            }
        }

        await fulfillment(of: [started], timeout: 1)
        loader.invalidate()
        mayFinish.continuation.yield(())
        mayFinish.continuation.finish()

        do {
            _ = try await loadTask.value
            XCTFail("Expected invalidated load to be rejected")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(loader.status, .unloaded)
        XCTAssertNil(loader.value)
    }
}
