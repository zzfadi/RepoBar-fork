import AppKit
import RepoBarCore

struct MainMenuPlan {
    let repos: [RepositoryDisplayModel]
    let signature: MenuBuildSignature
}

struct MenuBuildSignature: Hashable {
    let account: AccountSignature
    let settings: MenuSettingsSignature
    let hasLoadedRepositories: Bool
    let rateLimitReset: Date?
    let lastError: String?
    let contribution: ContributionSignature
    let heatmapRangeStart: TimeInterval
    let heatmapRangeEnd: TimeInterval
    let reposDigest: Int
    let timeBucket: Int
}

struct AccountSignature: Hashable {
    let state: String
    let user: String?
    let host: String?

    init(_ account: AccountState) {
        switch account {
        case .loggedOut:
            self.state = "loggedOut"
            self.user = nil
            self.host = nil
        case .loggingIn:
            self.state = "loggingIn"
            self.user = nil
            self.host = nil
        case let .loggedIn(user):
            self.state = "loggedIn"
            self.user = user.username
            self.host = user.host.host
        }
    }
}

struct MenuSettingsSignature: Hashable {
    let showContributionHeader: Bool
    let cardDensity: CardDensity
    let accentTone: AccentTone
    let heatmapDisplay: HeatmapDisplay
    let heatmapSpan: HeatmapSpan
    let displayLimit: Int
    let showForks: Bool
    let showArchived: Bool
    let menuSortKey: RepositorySortKey
    let pinned: [String]
    let hidden: [String]
    let selection: MenuRepoSelection

    init(settings: UserSettings, selection: MenuRepoSelection) {
        self.showContributionHeader = settings.appearance.showContributionHeader
        self.cardDensity = settings.appearance.cardDensity
        self.accentTone = settings.appearance.accentTone
        self.heatmapDisplay = settings.heatmap.display
        self.heatmapSpan = settings.heatmap.span
        self.displayLimit = settings.repoList.displayLimit
        self.showForks = settings.repoList.showForks
        self.showArchived = settings.repoList.showArchived
        self.menuSortKey = settings.repoList.menuSortKey
        self.pinned = settings.repoList.pinnedRepositories
        self.hidden = settings.repoList.hiddenRepositories
        self.selection = selection
    }
}

struct ContributionSignature: Hashable {
    let user: String?
    let error: String?
    let heatmapCount: Int
}

struct RepoSignature: Hashable {
    let fullName: String
    let ciStatus: CIStatus
    let ciRunCount: Int?
    let issues: Int
    let pulls: Int
    let stars: Int
    let forks: Int
    let pushedAt: Date?
    let latestReleaseTag: String?
    let latestActivityDate: Date?
    let activityEventCount: Int
    let trafficVisitors: Int?
    let trafficCloners: Int?
    let heatmapCount: Int
    let error: String?
    let rateLimitedUntil: Date?
    let localBranch: String?
    let localSyncState: LocalSyncState?
    let localDirtySummary: String?

    static func digest(for repos: [RepositoryDisplayModel]) -> Int {
        var hasher = Hasher()
        repos.map(Self.init).forEach { hasher.combine($0) }
        return hasher.finalize()
    }

    init(_ repo: RepositoryDisplayModel) {
        self.fullName = repo.title
        self.ciStatus = repo.ciStatus
        self.ciRunCount = repo.ciRunCount
        self.issues = repo.issues
        self.pulls = repo.pulls
        self.stars = repo.stars
        self.forks = repo.forks
        self.pushedAt = repo.source.stats.pushedAt
        self.latestReleaseTag = repo.source.latestRelease?.tag
        self.latestActivityDate = repo.source.latestActivity?.date
        self.activityEventCount = repo.activityEvents.count
        self.trafficVisitors = repo.trafficVisitors
        self.trafficCloners = repo.trafficCloners
        self.heatmapCount = repo.heatmap.count
        self.error = repo.error
        self.rateLimitedUntil = repo.rateLimitedUntil
        self.localBranch = repo.localStatus?.branch
        self.localSyncState = repo.localStatus?.syncState
        self.localDirtySummary = repo.localStatus?.dirtyCounts?.summary
    }
}

struct RepoSubmenuCacheEntry {
    let menu: NSMenu
    let signature: RepoSubmenuSignature
}

struct RepoRecentCountSignature: Hashable {
    let releases: Int?
    let discussions: Int?
    let tags: Int?
    let branches: Int?
    let contributors: Int?
}

struct RepoSubmenuSignature: Hashable {
    let fullName: String
    let issues: Int
    let pulls: Int
    let ciRunCount: Int?
    let activityURLPresent: Bool
    let localPath: String?
    let localBranch: String?
    let localSyncState: LocalSyncState?
    let localDirtySummary: String?
    let trafficVisitors: Int?
    let trafficCloners: Int?
    let heatmapDisplay: HeatmapDisplay
    let heatmapCount: Int
    let heatmapRangeStart: TimeInterval
    let heatmapRangeEnd: TimeInterval
    let activityDigest: Int
    let recentCounts: RepoRecentCountSignature
    let isPinned: Bool

    init(
        repo: RepositoryDisplayModel,
        settings: UserSettings,
        heatmapRange: HeatmapRange,
        recentCounts: RepoRecentCountSignature,
        isPinned: Bool
    ) {
        self.fullName = repo.title
        self.issues = repo.issues
        self.pulls = repo.pulls
        self.ciRunCount = repo.ciRunCount
        self.activityURLPresent = repo.activityURL != nil
        self.localPath = repo.localStatus?.path.path
        self.localBranch = repo.localStatus?.branch
        self.localSyncState = repo.localStatus?.syncState
        self.localDirtySummary = repo.localStatus?.dirtyCounts?.summary
        self.trafficVisitors = repo.trafficVisitors
        self.trafficCloners = repo.trafficCloners
        self.heatmapDisplay = settings.heatmap.display
        self.heatmapCount = repo.heatmap.count
        self.heatmapRangeStart = heatmapRange.start.timeIntervalSinceReferenceDate
        self.heatmapRangeEnd = heatmapRange.end.timeIntervalSinceReferenceDate
        self.activityDigest = RepoSubmenuSignature.digest(events: repo.activityEvents)
        self.recentCounts = recentCounts
        self.isPinned = isPinned
    }

    private static func digest(events: [ActivityEvent]) -> Int {
        var hasher = Hasher()
        events.prefix(10).forEach { event in
            hasher.combine(event.title)
            hasher.combine(event.actor)
            hasher.combine(event.date.timeIntervalSinceReferenceDate)
            hasher.combine(event.eventType ?? "")
        }
        return hasher.finalize()
    }
}
