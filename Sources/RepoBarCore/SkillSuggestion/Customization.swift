import Foundation

// MARK: - Customization Model

/// Represents a discovered AI customization in a project
public struct Customization: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let type: CustomizationType
    public let name: String
    public let path: String
    public let description: String?
    public let capabilities: Set<CustomizationCapability>
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let usageCount: Int?
    public let lastUsedAt: Date?
    public let source: CustomizationSource
    public let metadata: CustomizationMetadata

    public init(
        id: UUID = UUID(),
        type: CustomizationType,
        name: String,
        path: String,
        description: String? = nil,
        capabilities: Set<CustomizationCapability> = [],
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        usageCount: Int? = nil,
        lastUsedAt: Date? = nil,
        source: CustomizationSource = .local,
        metadata: CustomizationMetadata = .init()
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.path = path
        self.description = description
        self.capabilities = capabilities
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.usageCount = usageCount
        self.lastUsedAt = lastUsedAt
        self.source = source
        self.metadata = metadata
    }

    /// Health status based on usage and staleness
    public var healthStatus: CustomizationHealth {
        guard let lastUsed = lastUsedAt else {
            return .unknown
        }

        let daysSinceUse = Calendar.current.dateComponents([.day], from: lastUsed, to: Date()).day ?? 0

        if daysSinceUse > 90 {
            return .stale
        } else if daysSinceUse > 30 {
            return .warning
        } else {
            return .healthy
        }
    }

    /// Display color for visualization
    public var displayColorHex: String {
        type.colorHex
    }
}

// MARK: - Customization Source

public enum CustomizationSource: String, Codable, Hashable, Sendable {
    case local          // Found in local project
    case global         // User's global config
    case remote         // From a repository/registry
    case builtin        // Built into the tool

    public var displayName: String {
        switch self {
        case .local: "Local"
        case .global: "Global"
        case .remote: "Remote"
        case .builtin: "Built-in"
        }
    }
}

// MARK: - Customization Health

public enum CustomizationHealth: String, Codable, Hashable, Sendable {
    case healthy
    case warning
    case stale
    case unknown

    public var displayName: String {
        switch self {
        case .healthy: "Healthy"
        case .warning: "May need review"
        case .stale: "Stale"
        case .unknown: "Unknown"
        }
    }

    public var colorHex: String {
        switch self {
        case .healthy: "#22C55E"   // Green
        case .warning: "#F59E0B"   // Amber
        case .stale: "#EF4444"     // Red
        case .unknown: "#6B7280"   // Gray
        }
    }
}

// MARK: - Customization Metadata

public struct CustomizationMetadata: Hashable, Sendable {
    public let toolRestrictions: [String]?
    public let requiredTools: [String]?
    public let triggerCommands: [String]?
    public let frontmatter: [String: String]?
    public let scriptPaths: [String]?
    public let dependencies: [String]?

    public init(
        toolRestrictions: [String]? = nil,
        requiredTools: [String]? = nil,
        triggerCommands: [String]? = nil,
        frontmatter: [String: String]? = nil,
        scriptPaths: [String]? = nil,
        dependencies: [String]? = nil
    ) {
        self.toolRestrictions = toolRestrictions
        self.requiredTools = requiredTools
        self.triggerCommands = triggerCommands
        self.frontmatter = frontmatter
        self.scriptPaths = scriptPaths
        self.dependencies = dependencies
    }
}

// MARK: - Customization Collection

/// A collection of customizations with computed statistics
public struct CustomizationCollection: Sendable {
    public let customizations: [Customization]
    public let scannedAt: Date

    public init(customizations: [Customization], scannedAt: Date = Date()) {
        self.customizations = customizations
        self.scannedAt = scannedAt
    }

    /// Group customizations by type
    public var byType: [CustomizationType: [Customization]] {
        Dictionary(grouping: customizations, by: \.type)
    }

    /// Group customizations by health status
    public var byHealth: [CustomizationHealth: [Customization]] {
        Dictionary(grouping: customizations, by: \.healthStatus)
    }

    /// Group customizations by source
    public var bySource: [CustomizationSource: [Customization]] {
        Dictionary(grouping: customizations, by: \.source)
    }

    /// Count per type for visualization
    public var typeDistribution: [(type: CustomizationType, count: Int)] {
        CustomizationType.allCases.map { type in
            (type, byType[type]?.count ?? 0)
        }
    }

    /// Health summary
    public var healthSummary: (healthy: Int, warning: Int, stale: Int, unknown: Int) {
        (
            byHealth[.healthy]?.count ?? 0,
            byHealth[.warning]?.count ?? 0,
            byHealth[.stale]?.count ?? 0,
            byHealth[.unknown]?.count ?? 0
        )
    }

    /// Most recently used customizations
    public var recentlyUsed: [Customization] {
        customizations
            .filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
    }

    /// Potentially stale customizations that may need attention
    public var needsAttention: [Customization] {
        customizations.filter { $0.healthStatus == .stale || $0.healthStatus == .warning }
    }
}
