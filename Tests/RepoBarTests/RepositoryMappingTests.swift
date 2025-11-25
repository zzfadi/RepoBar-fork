import Foundation
@testable import RepoBar
import Testing

struct RepositoryMappingTests {
    @Test
    func repoViewModelRespectsPinnedOrderThenAlpha() {
        let repos = [
            Repository(id: "1", name: "b", owner: "z", sortOrder: 2, error: nil, rateLimitedUntil: nil, ciStatus: .unknown, openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: []),
            Repository(id: "2", name: "a", owner: "z", sortOrder: 0, error: nil, rateLimitedUntil: nil, ciStatus: .unknown, openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: []),
            Repository(id: "3", name: "c", owner: "z", sortOrder: nil, error: nil, rateLimitedUntil: nil, ciStatus: .unknown, openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: [])
        ]
        let viewModels = repos.map { RepositoryViewModel(repo: $0) }
        let sorted = TestableRepoGrid.sortedForTest(viewModels)
        let titles = sorted.map(\.title)
        #expect(titles == ["z/a", "z/b", "z/c"])
    }

    @Test
    func trafficAndErrorsPropagate() {
        let repo = Repository(
            id: "99",
            name: "repo",
            owner: "me",
            sortOrder: nil,
            error: "Rate limited",
            rateLimitedUntil: Date().addingTimeInterval(120),
            ciStatus: .pending,
            openIssues: 4,
            openPulls: 1,
            latestRelease: nil,
            latestActivity: nil,
            traffic: TrafficStats(uniqueVisitors: 10, uniqueCloners: 3),
            heatmap: []
        )
        let vm = RepositoryViewModel(repo: repo, now: Date())
        #expect(vm.error == "Rate limited")
        #expect(vm.rateLimitedUntil != nil)
        #expect(vm.trafficVisitors == 10)
        #expect(vm.trafficCloners == 3)
    }
}

// Reuse helper from MenuContentViewModelTests
private enum TestableRepoGrid {
    static func sortedForTest(_ repos: [RepositoryViewModel]) -> [RepositoryViewModel] {
        repos.sorted { lhs, rhs in
            switch (lhs.sortOrder, rhs.sortOrder) {
            case let (left?, right?): left < right
            case (.none, .some): false
            case (.some, .none): true
            default: lhs.title < rhs.title
            }
        }
    }
}
