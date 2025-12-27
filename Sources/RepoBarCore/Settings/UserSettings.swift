import Foundation

public struct UserSettings: Equatable, Codable {
    public var showContributionHeader = true
    public var repoDisplayLimit: Int = 5
    public var showForks = false
    public var refreshInterval: RefreshInterval = .fiveMinutes
    public var launchAtLogin = false
    public var showHeatmap = true
    public var heatmapSpan: HeatmapSpan = .threeMonths
    public var cardDensity: CardDensity = .comfortable
    public var accentTone: AccentTone = .githubGreen
    public var debugPaneEnabled: Bool = false
    public var diagnosticsEnabled: Bool = false
    public var githubHost: URL = .init(string: "https://github.com")!
    public var enterpriseHost: URL?
    public var loopbackPort: Int = 53682
    public var pinnedRepositories: [String] = [] // owner/name
    public var hiddenRepositories: [String] = [] // owner/name

    public init() {}
}

public enum RefreshInterval: CaseIterable, Equatable, Codable {
    case oneMinute, twoMinutes, fiveMinutes, fifteenMinutes

    public var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        }
    }
}

public enum CardDensity: String, CaseIterable, Equatable, Codable {
    case comfortable
    case compact

    public var label: String {
        switch self {
        case .comfortable: "Comfortable"
        case .compact: "Compact"
        }
    }
}

public enum AccentTone: String, CaseIterable, Equatable, Codable {
    case system
    case githubGreen

    public var label: String {
        switch self {
        case .system: "System accent"
        case .githubGreen: "GitHub greens"
        }
    }
}
