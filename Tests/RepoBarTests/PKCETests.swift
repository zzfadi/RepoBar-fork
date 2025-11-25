@testable import RepoBar
import Testing

struct PKCETests {
    @Test
    func verifierAndChallengeNotEmpty() {
        let pkce = PKCE.generate()
        #expect(!pkce.verifier.isEmpty)
        #expect(!pkce.challenge.isEmpty)
    }
}
