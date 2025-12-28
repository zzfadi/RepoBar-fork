import Foundation
@testable import RepoBarCore
import Testing

struct LoopbackServerTests {
    @Test
    func parseExtractsCodeAndState() {
        let request = "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let parsed = LoopbackServer.parse(request: request)
        #expect(parsed?.code == "abc")
        #expect(parsed?.state == "xyz")
    }

    @Test
    @MainActor
    func waitForCallbackReturnsResult() async throws {
        let (server, redirectURL) = try await Self.startServer()
        defer { server.stop() }

        let expectedCode = "code-1"
        let expectedState = "state-1"

        let sendTask = Task {
            try await Task.sleep(nanoseconds: 120_000_000)
            var components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "code", value: expectedCode),
                URLQueryItem(name: "state", value: expectedState)
            ]
            // Best-effort fire-and-forget; if this fails, the test still fails by timing out on the server side.
            _ = try? await URLSession.shared.data(from: components.url!)
        }
        defer { sendTask.cancel() }

        let result = try await server.waitForCallback(timeout: 3)
        #expect(result.code == expectedCode)
        #expect(result.state == expectedState)
    }

    @Test
    @MainActor
    func waitForCallbackTimesOut() async throws {
        let (server, _) = try await Self.startServer()
        defer { server.stop() }

        do {
            _ = try await server.waitForCallback(timeout: 0.05)
            Issue.record("Expected timeout")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        }
    }
}

private extension LoopbackServerTests {
    @MainActor
    static func startServer() async throws -> (LoopbackServer, URL) {
        var lastError: Error?
        for _ in 0 ..< 40 {
            let port = Int.random(in: 49152 ... 65000)
            let server = LoopbackServer(port: port)
            do {
                let redirectURL = try server.start()
                return (server, redirectURL)
            } catch {
                lastError = error
                server.stop()
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }
}
