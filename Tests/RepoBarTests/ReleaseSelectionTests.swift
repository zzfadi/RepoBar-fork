import Foundation
import Testing
@testable import RepoBar

struct ReleaseSelectionTests {
    @Test
    func picksNewestPublishedRelease() {
        let releases = [
            ReleaseResponse(name: "v0.1", tagName: "v0.1", publishedAt: Date(timeIntervalSince1970: 1_700_000_000), createdAt: Date(timeIntervalSince1970: 1_699_000_000), draft: false, prerelease: false, htmlUrl: URL(string: "https://example.com/0.1")!),
            ReleaseResponse(name: "v0.4.1", tagName: "v0.4.1", publishedAt: Date(timeIntervalSince1970: 1_700_100_000), createdAt: Date(timeIntervalSince1970: 1_700_050_000), draft: false, prerelease: false, htmlUrl: URL(string: "https://example.com/0.4.1")!)
        ]

        let picked = GitHubClient.latestRelease(from: releases)
        #expect(picked?.tag == "v0.4.1")
    }

    @Test
    func skipsDraftsAndFallsBackToCreatedDate() {
        let releases = [
            ReleaseResponse(name: "draft", tagName: "draft", publishedAt: nil, createdAt: Date(timeIntervalSince1970: 1_700_200_000), draft: true, prerelease: false, htmlUrl: URL(string: "https://example.com/draft")!),
            ReleaseResponse(name: "v0.5.0", tagName: "v0.5.0", publishedAt: nil, createdAt: Date(timeIntervalSince1970: 1_700_150_000), draft: false, prerelease: false, htmlUrl: URL(string: "https://example.com/0.5.0")!)
        ]

        let picked = GitHubClient.latestRelease(from: releases)
        #expect(picked?.tag == "v0.5.0")
        #expect(picked?.publishedAt == Date(timeIntervalSince1970: 1_700_150_000))
    }
}
