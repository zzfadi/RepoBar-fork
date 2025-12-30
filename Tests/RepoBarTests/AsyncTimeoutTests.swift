@testable import RepoBar
import Testing

@Suite("AsyncTimeout")
struct AsyncTimeoutTests {
    @Test
    func returnsValueBeforeTimeout() async throws {
        let task = Task<Int, Error> {
            try await Task.sleep(nanoseconds: 20_000_000)
            return 42
        }

        let value = try await AsyncTimeout.value(within: 0.5, task: task)
        #expect(value == 42)
    }

    @Test
    func timesOutAndCancelsTask() async {
        let cancellationFlag = CancellationFlag()
        let task = Task<Int, Error> {
            try await withTaskCancellationHandler {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return 1
            } onCancel: {
                cancellationFlag.markCancelled()
            }
        }

        do {
            _ = try await AsyncTimeout.value(within: 0.05, task: task)
            #expect(Bool(false), "Expected timeout")
        } catch is AsyncTimeoutError {
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }

        for _ in 0 ..< 50 {
            if cancellationFlag.isCancelled {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(cancellationFlag.isCancelled)
        #expect(task.isCancelled)
    }
}

private final class CancellationFlag {
    private let lock = NSLock()
    private(set) var isCancelled = false

    func markCancelled() {
        self.lock.lock()
        self.isCancelled = true
        self.lock.unlock()
    }
}
