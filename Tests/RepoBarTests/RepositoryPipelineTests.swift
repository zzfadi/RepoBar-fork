import Foundation
import RepoBarCore
import Testing

@Suite("RepositoryPipeline")
struct RepositoryPipelineTests {
    @Test("Filters onlyWith work")
    func filtersOnlyWithWork() {
        let repos = [
            Self.makeRepo("a/one", issues: 2, pulls: 1),
            Self.makeRepo("b/two", issues: 0, pulls: 2),
            Self.makeRepo("c/three", issues: 0, pulls: 0)
        ]
        let query = RepositoryQuery(
            onlyWith: RepositoryOnlyWith(requireIssues: true, requirePRs: true)
        )
        let result = RepositoryPipeline.apply(repos, query: query)
        #expect(result.map(\.fullName) == ["a/one", "b/two"])
    }

    @Test("Pinned priority overrides sort order")
    func pinnedPriorityOverridesSort() {
        let repos = [
            Self.makeRepo("a/alpha", issues: 10, pulls: 1),
            Self.makeRepo("b/bravo", issues: 1, pulls: 1)
        ]
        let query = RepositoryQuery(
            sortKey: .issues,
            pinned: ["b/bravo"],
            pinPriority: true
        )
        let result = RepositoryPipeline.apply(repos, query: query)
        #expect(result.map(\.fullName) == ["b/bravo", "a/alpha"])
    }

    @Test("Applies age cutoff against activityDate")
    func appliesAgeCutoff() {
        let now = Date()
        let recent = Self.makeRepo("a/recent", issues: 0, pulls: 0, pushedAt: now.addingTimeInterval(-60))
        let stale = Self.makeRepo("b/stale", issues: 0, pulls: 0, pushedAt: now.addingTimeInterval(-86400 * 10))
        let query = RepositoryQuery(ageCutoff: now.addingTimeInterval(-86400))
        let result = RepositoryPipeline.apply([recent, stale], query: query)
        #expect(result.map(\.fullName) == ["a/recent"])
    }

    @Test("Hidden scope returns only hidden repositories")
    func hiddenScopeFiltersHidden() {
        let repos = [
            Self.makeRepo("a/one", issues: 0, pulls: 0),
            Self.makeRepo("b/two", issues: 0, pulls: 0),
            Self.makeRepo("c/three", issues: 0, pulls: 0)
        ]
        let query = RepositoryQuery(
            scope: .hidden,
            hidden: Set(["b/two"])
        )
        let result = RepositoryPipeline.apply(repos, query: query)
        #expect(result.map(\.fullName) == ["b/two"])
    }

    @Test("Pinned scope filters to pinned list")
    func pinnedScopeFiltersPinned() {
        let repos = [
            Self.makeRepo("a/one", issues: 0, pulls: 0),
            Self.makeRepo("b/two", issues: 0, pulls: 0),
            Self.makeRepo("c/three", issues: 0, pulls: 0)
        ]
        let query = RepositoryQuery(
            scope: .pinned,
            pinned: ["c/three", "a/one"],
            pinPriority: true
        )
        let result = RepositoryPipeline.apply(repos, query: query)
        #expect(result.map(\.fullName) == ["c/three", "a/one"])
    }

    @Test("Pinned scope matches case-insensitively")
    func pinnedScopeMatchesCaseInsensitively() {
        let repos = [
            Self.makeRepo("Owner/Repo", issues: 0, pulls: 0),
            Self.makeRepo("other/repo", issues: 0, pulls: 0)
        ]
        let query = RepositoryQuery(
            scope: .pinned,
            pinned: ["owner/repo"],
            pinPriority: true
        )
        let result = RepositoryPipeline.apply(repos, query: query)
        #expect(result.map(\.fullName) == ["Owner/Repo"])
    }

    @Test("Default age cutoff applies only to all scope")
    func ageCutoffDefaults() {
        let now = Date()
        #expect(RepositoryQueryDefaults.ageCutoff(now: now, scope: .pinned) == nil)
        #expect(RepositoryQueryDefaults.ageCutoff(now: now, scope: .hidden) == nil)
        #expect(RepositoryQueryDefaults.ageCutoff(now: now, scope: .all) != nil)
    }

    private static func makeRepo(
        _ fullName: String,
        issues: Int,
        pulls: Int,
        stars: Int = 0,
        forks: Int = 0,
        pushedAt: Date? = nil,
        isFork: Bool = false,
        isArchived: Bool = false
    ) -> Repository {
        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        let owner = parts.first ?? ""
        let name = parts.dropFirst().first ?? ""
        return Repository(
            id: fullName,
            name: name,
            owner: owner,
            isFork: isFork,
            isArchived: isArchived,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: issues,
            openPulls: pulls,
            stars: stars,
            forks: forks,
            pushedAt: pushedAt,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
    }
}
