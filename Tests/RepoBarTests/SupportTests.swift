import Foundation
@testable import RepoBar
@testable import RepoBarCore
import Testing

@MainActor
struct RefreshAndBackoffTests {
    @Test
    func forceRefreshTriggersTick() async throws {
        let scheduler = RefreshScheduler()
        var fired = false
        scheduler.configure(interval: 60, fireImmediately: false) {
            fired = true
        }

        scheduler.forceRefresh()
        #expect(fired)
    }

    @Test
    func backoffTracksCooldown() async {
        let tracker = BackoffTracker()
        let url = URL(string: "https://example.com/path")!
        let initial = await tracker.isCoolingDown(url: url)
        #expect(initial == false)

        let until = Date().addingTimeInterval(30)
        await tracker.setCooldown(url: url, until: until)

        let cooling = await tracker.isCoolingDown(url: url)
        #expect(cooling)
        let reported = await tracker.cooldown(for: url)
        #expect(reported != nil)
        if let reported {
            #expect(abs(reported.timeIntervalSince1970 - until.timeIntervalSince1970) < 0.5)
        }
    }

    @Test
    func mapsCertificateErrors() {
        let error = URLError(.serverCertificateUntrusted)
        #expect(error.userFacingMessage == "Enterprise host certificate is not trusted.")
    }

    @Test
    func mapsCannotParseResponse() {
        let error = URLError(.cannotParseResponse)
        #expect(error.userFacingMessage == "GitHub returned an unexpected response.")
    }

    @Test
    func authenticationFailureDetection() {
        let unauthorized: Error = GitHubAPIError.badStatus(code: 401, message: nil)
        #expect(unauthorized.isAuthenticationFailure)

        let refreshFailure: Error = GitHubAPIError.badStatus(
            code: 400,
            message: "Authentication refresh failed (HTTP 400). Please sign in again."
        )
        #expect(refreshFailure.isAuthenticationFailure)

        let urlAuth: Error = URLError(.userAuthenticationRequired)
        #expect(urlAuth.isAuthenticationFailure)
    }

    @Test
    func loopbackParsesCodeAndState() {
        let request = "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1:53682\r\n\r\n"
        let parsed = LoopbackServer.parse(request: request)
        #expect(parsed?.code == "abc")
        #expect(parsed?.state == "xyz")
    }
}
