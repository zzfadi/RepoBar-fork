import Foundation
import RepoBarCore

struct RepositoryViewModel: Identifiable, Equatable {
    let source: Repository
    let id: String
    let title: String
    let latestRelease: String?
    let latestReleaseDate: String?
    let lastPushAge: String?
    let ciStatus: CIStatus
    let ciRunCount: Int?
    let issues: Int
    let pulls: Int
    let trafficVisitors: Int?
    let trafficCloners: Int?
    let stars: Int
    let forks: Int
    let activityLine: String?
    let activityURL: URL?
    let heatmap: [HeatmapCell]
    let sortOrder: Int?
    let error: String?
    let rateLimitedUntil: Date?

    init(repo: Repository, now: Date = Date()) {
        self.source = repo
        self.id = repo.id
        self.title = repo.fullName
        self.ciStatus = repo.ciStatus
        self.ciRunCount = repo.ciRunCount
        self.issues = repo.openIssues
        self.pulls = repo.openPulls
        self.trafficVisitors = repo.traffic?.uniqueVisitors
        self.trafficCloners = repo.traffic?.uniqueCloners
        self.stars = repo.stars
        self.forks = repo.forks
        self.heatmap = repo.heatmap
        self.sortOrder = repo.sortOrder
        self.error = repo.error
        self.rateLimitedUntil = repo.rateLimitedUntil

        if let release = repo.latestRelease {
            self.latestRelease = release.name
            self.latestReleaseDate = RelativeFormatter.string(from: release.publishedAt, relativeTo: now)
        } else {
            self.latestRelease = nil
            self.latestReleaseDate = nil
        }

        if let pushedAt = repo.pushedAt {
            self.lastPushAge = RelativeFormatter.string(from: pushedAt, relativeTo: now)
        } else {
            self.lastPushAge = nil
        }

        self.activityLine = repo.activityLine
        self.activityURL = repo.activityURL
    }
}
