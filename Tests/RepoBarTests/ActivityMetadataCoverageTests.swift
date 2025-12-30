import Foundation
import RepoBarCore
import Testing

struct ActivityMetadataCoverageTests {
    @Test
    func label_formatsCommonTargets() {
        let url = URL(string: "https://example.com")!

        #expect(ActivityMetadata(actor: "a", action: "Forked", target: "→ org/repo", url: url).label == "Forked → org/repo")
        #expect(ActivityMetadata(actor: "a", action: "Commented", target: "#123", url: url).label == "Commented #123")
        #expect(ActivityMetadata(actor: "a", action: "Opened", target: "Issue", url: url).label == "Opened: Issue")
        #expect(ActivityMetadata(actor: "a", action: "Pushed", target: nil, url: url).label == "Pushed")
        #expect(ActivityMetadata(actor: "a", action: nil, target: "Repo", url: url).label == "Repo")
        #expect(ActivityMetadata(actor: "a", action: nil, target: nil, url: url).label.isEmpty)
    }

    @Test
    func deepLink_isURL() {
        let url = URL(string: "https://example.com")!
        #expect(ActivityMetadata(actor: "a", action: nil, target: nil, url: url).deepLink == url)
    }
}

