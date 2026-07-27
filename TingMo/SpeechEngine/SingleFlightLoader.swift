import Foundation

/// Coordinates an asynchronous resource load so every concurrent caller waits
/// for the same task. A failed load can be retried, and invalidation prevents a
/// stale in-flight task from publishing its result.
nonisolated final class SingleFlightLoader<Value: Sendable>: @unchecked Sendable {
    enum Status: Equatable, Sendable {
        case unloaded
        case loading
        case loaded
        case failed(String)
    }

    private enum Storage {
        case unloaded
        case loading(generation: UInt64, task: Task<Value, Error>)
        case loaded(generation: UInt64, value: Value)
        case failed(generation: UInt64, message: String)
    }

    private enum LoadAction {
        case returnValue(Value)
        case awaitTask(generation: UInt64, task: Task<Value, Error>)
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var storage: Storage = .unloaded

    var status: Status {
        withLock {
            switch storage {
            case .unloaded: .unloaded
            case .loading: .loading
            case .loaded: .loaded
            case .failed(_, let message): .failed(message)
            }
        }
    }

    var value: Value? {
        withLock {
            guard case .loaded(_, let value) = storage else { return nil }
            return value
        }
    }

    func load(
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let action = withLock { () -> LoadAction in
            switch storage {
            case .loaded(_, let value):
                return .returnValue(value)
            case .loading(let generation, let task):
                return .awaitTask(generation: generation, task: task)
            case .unloaded, .failed:
                generation &+= 1
                let currentGeneration = generation
                let task = Task { try await operation() }
                storage = .loading(generation: currentGeneration, task: task)
                return .awaitTask(generation: currentGeneration, task: task)
            }
        }

        switch action {
        case .returnValue(let value):
            return value
        case .awaitTask(let generation, let task):
            do {
                let value = try await task.value
                guard publish(value, for: generation) else {
                    throw CancellationError()
                }
                return value
            } catch {
                recordFailure(error, for: generation)
                throw error
            }
        }
    }

    /// Discard the loaded value and reject any result from the current task.
    /// Cancellation is best-effort; the generation check is what prevents a
    /// loader that ignores cancellation from publishing stale state.
    func invalidate() {
        let task = withLock { () -> Task<Value, Error>? in
            generation &+= 1
            let task: Task<Value, Error>?
            if case .loading(_, let loadingTask) = storage {
                task = loadingTask
            } else {
                task = nil
            }
            storage = .unloaded
            return task
        }
        task?.cancel()
    }

    private func publish(_ value: Value, for completedGeneration: UInt64) -> Bool {
        withLock {
            switch storage {
            case .loading(let currentGeneration, _) where currentGeneration == completedGeneration:
                storage = .loaded(generation: completedGeneration, value: value)
                return true
            case .loaded(let currentGeneration, _) where currentGeneration == completedGeneration:
                // Another waiter for this same task already published it.
                return true
            default:
                return false
            }
        }
    }

    private func recordFailure(_ error: Error, for failedGeneration: UInt64) {
        withLock {
            guard case .loading(let currentGeneration, _) = storage,
                  currentGeneration == failedGeneration
            else { return }

            storage = .failed(
                generation: failedGeneration,
                message: error.localizedDescription
            )
        }
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
