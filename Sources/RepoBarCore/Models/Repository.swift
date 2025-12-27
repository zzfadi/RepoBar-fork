import Foundation

public struct Repository: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let owner: String
    public let isFork: Bool
    public let sortOrder: Int?
    public var error: String?
    public var rateLimitedUntil: Date?
    public var ciStatus: CIStatus
    public var ciRunCount: Int?
    public var openIssues: Int
    public var openPulls: Int
    public var stars: Int
    public var pushedAt: Date?
    public var latestRelease: Release?
    public var latestActivity: ActivityEvent?
    public var traffic: TrafficStats?
    public var heatmap: [HeatmapCell]

    public init(
        id: String,
        name: String,
        owner: String,
        isFork: Bool = false,
        sortOrder: Int?,
        error: String?,
        rateLimitedUntil: Date?,
        ciStatus: CIStatus,
        ciRunCount: Int? = nil,
        openIssues: Int,
        openPulls: Int,
        stars: Int = 0,
        pushedAt: Date? = nil,
        latestRelease: Release?,
        latestActivity: ActivityEvent?,
        traffic: TrafficStats?,
        heatmap: [HeatmapCell]
    ) {
        self.id = id
        self.name = name
        self.owner = owner
        self.isFork = isFork
        self.sortOrder = sortOrder
        self.error = error
        self.rateLimitedUntil = rateLimitedUntil
        self.ciStatus = ciStatus
        self.ciRunCount = ciRunCount
        self.openIssues = openIssues
        self.openPulls = openPulls
        self.stars = stars
        self.pushedAt = pushedAt
        self.latestRelease = latestRelease
        self.latestActivity = latestActivity
        self.traffic = traffic
        self.heatmap = heatmap
    }

    public var fullName: String { "\(self.owner)/\(self.name)" }

    public func withOrder(_ order: Int?) -> Repository {
        Repository(
            id: self.id,
            name: self.name,
            owner: self.owner,
            isFork: self.isFork,
            sortOrder: order,
            error: self.error,
            rateLimitedUntil: self.rateLimitedUntil,
            ciStatus: self.ciStatus,
            ciRunCount: self.ciRunCount,
            openIssues: self.openIssues,
            openPulls: self.openPulls,
            stars: self.stars,
            pushedAt: self.pushedAt,
            latestRelease: self.latestRelease,
            latestActivity: self.latestActivity,
            traffic: self.traffic,
            heatmap: self.heatmap
        )
    }
}

public enum CIStatus: Codable, Equatable, Sendable {
    case passing
    case failing
    case pending
    case unknown
}

public struct Release: Codable, Equatable, Sendable {
    public let name: String
    public let tag: String
    public let publishedAt: Date
    public let url: URL

    public init(name: String, tag: String, publishedAt: Date, url: URL) {
        self.name = name
        self.tag = tag
        self.publishedAt = publishedAt
        self.url = url
    }
}

public struct TrafficStats: Codable, Equatable, Sendable {
    public let uniqueVisitors: Int
    public let uniqueCloners: Int

    public init(uniqueVisitors: Int, uniqueCloners: Int) {
        self.uniqueVisitors = uniqueVisitors
        self.uniqueCloners = uniqueCloners
    }
}

public struct ActivityEvent: Codable, Equatable, Sendable {
    public let title: String
    public let actor: String
    public let date: Date
    public let url: URL

    public init(title: String, actor: String, date: Date, url: URL) {
        self.title = title
        self.actor = actor
        self.date = date
        self.url = url
    }
}

public struct HeatmapCell: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let count: Int

    public init(id: UUID = UUID(), date: Date, count: Int) {
        self.id = id
        self.date = date
        self.count = count
    }
}

public struct CIStatusDetails: Codable, Sendable {
    public let status: CIStatus
    public let runCount: Int?

    public init(status: CIStatus, runCount: Int?) {
        self.status = status
        self.runCount = runCount
    }
}
