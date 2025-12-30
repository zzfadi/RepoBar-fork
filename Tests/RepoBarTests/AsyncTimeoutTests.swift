@testable import RepoBar
import Testing

@Suite("AsyncTimeout")
struct AsyncTimeoutTests {
    @Test
    func returnsValueBeforeTimeout() async throws {
        let task = Task<Int, Error> {
            try await Task.sleep(nanoseconds: 5_000_000)
            return 42
        }

        let value = try await AsyncTimeout.value(within: 1.0, task: task)
        #expect(value == 42)
    }

    @Test
    func timesOutAndCancelsTask() async {
        let task = Task<Int, Error> {
            try await withTaskCancellationHandler {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return 1
            } onCancel: {}
        }

        do {
            _ = try await AsyncTimeout.value(within: 0.05, task: task)
            #expect(Bool(false), "Expected timeout")
        } catch is AsyncTimeoutError {
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }

        #expect(task.isCancelled)
    }
}
