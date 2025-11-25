import Foundation
@testable import RepoBar
import Testing

struct MenuContentViewModelTests {
    @Test
    func sortedRespectsPinnedOrderThenAlpha() {
        let repos = [
            Repository(
                id: "1",
                name: "B",
                owner: "me",
                sortOrder: 1,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .passing,
                openIssues: 0,
                openPulls: 0,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            ),
            Repository(
                id: "2",
                name: "A",
                owner: "me",
                sortOrder: 0,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .passing,
                openIssues: 0,
                openPulls: 0,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            ),
            Repository(
                id: "3",
                name: "C",
                owner: "me",
                sortOrder: nil,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .passing,
                openIssues: 0,
                openPulls: 0,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            )
        ].map { RepositoryViewModel(repo: $0) }

        let ordered = TestableRepoGrid.sortedForTest(repos)
        #expect(ordered.map(\.id) == ["2", "1", "3"])
    }

    @Test
    func moveStepCalculatesBounds() {
        let repos = [
            RepositoryViewModel(repo: Repository(
                id: "1",
                name: "A",
                owner: "me",
                sortOrder: 0,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .passing,
                openIssues: 0,
                openPulls: 0,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            )),
            RepositoryViewModel(repo: Repository(
                id: "2",
                name: "B",
                owner: "me",
                sortOrder: 1,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .passing,
                openIssues: 0,
                openPulls: 0,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            ))
        ]

        var moveCalls: [(IndexSet, Int)] = []
        TestableRepoGrid.moveStepForTest(repo: repos[0], in: repos, direction: 1) { source, dest in
            moveCalls.append((source, dest))
        }
        #expect(moveCalls.count == 1)
        #expect(moveCalls.first?.0 == IndexSet(integer: 0))
    }
}

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

    static func moveStepForTest(
        repo: RepositoryViewModel,
        in ordered: [RepositoryViewModel],
        direction: Int,
        move: (IndexSet, Int) -> Void
    ) {
        guard let currentIndex = ordered.firstIndex(of: repo) else { return }
        let maxIndex = max(ordered.count - 1, 0)
        let target = max(0, min(maxIndex, currentIndex + direction))
        guard target != currentIndex else { return }
        move(IndexSet(integer: currentIndex), target > currentIndex ? target + 1 : target)
    }
}
