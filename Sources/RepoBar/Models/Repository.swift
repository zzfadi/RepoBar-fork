import Foundation

struct Repository: Identifiable, Equatable {
    let id: String
    let name: String
    let owner: String
    let sortOrder: Int?
    var error: String?
    var rateLimitedUntil: Date?
    var ciStatus: CIStatus
    var openIssues: Int
    var openPulls: Int
    var latestRelease: Release?
    var latestActivity: ActivityEvent?
    var traffic: TrafficStats?
    var heatmap: [HeatmapCell]

    var fullName: String { "\(self.owner)/\(self.name)" }

    func withOrder(_ order: Int?) -> Repository {
        Repository(
            id: self.id,
            name: self.name,
            owner: self.owner,
            sortOrder: order,
            error: self.error,
            rateLimitedUntil: self.rateLimitedUntil,
            ciStatus: self.ciStatus,
            openIssues: self.openIssues,
            openPulls: self.openPulls,
            latestRelease: self.latestRelease,
            latestActivity: self.latestActivity,
            traffic: self.traffic,
            heatmap: self.heatmap
        )
    }
}

enum CIStatus: Equatable {
    case passing
    case failing
    case pending
    case unknown
}

struct Release: Equatable {
    let name: String
    let tag: String
    let publishedAt: Date
    let url: URL
}

struct TrafficStats: Equatable {
    let uniqueVisitors: Int
    let uniqueCloners: Int
}

struct ActivityEvent: Equatable {
    let title: String
    let actor: String
    let date: Date
    let url: URL
}

struct HeatmapCell: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let count: Int
}
