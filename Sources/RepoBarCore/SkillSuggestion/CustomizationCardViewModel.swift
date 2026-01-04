import Foundation

// MARK: - Customization Card View Model

/// View model for displaying a customization card, inspired by RepoBar's RepoCardView.
/// Supports the "rainbow power view" concept with color-coded customization types.
public struct CustomizationCardViewModel: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let customization: Customization

    public init(customization: Customization) {
        self.id = customization.id
        self.customization = customization
    }

    // MARK: - Display Properties

    public var displayName: String {
        customization.name
    }

    public var typeLabel: String {
        customization.type.displayName
    }

    public var typeBadgeColor: String {
        customization.type.colorHex
    }

    public var description: String {
        customization.description ?? customization.type.description
    }

    public var location: String {
        customization.path
    }

    public var sourceLabel: String {
        customization.source.displayName
    }

    public var healthIndicatorColor: String {
        customization.healthStatus.colorHex
    }

    public var healthLabel: String {
        customization.healthStatus.displayName
    }

    // MARK: - Capabilities Display

    public var capabilityTags: [CapabilityTag] {
        customization.capabilities.map { capability in
            CapabilityTag(
                name: formatCapabilityName(capability),
                colorHex: colorForCapability(capability)
            )
        }
    }

    // MARK: - Activity Display

    public var lastModifiedLabel: String? {
        guard let date = customization.modifiedAt else { return nil }
        return formatRelativeDate(date)
    }

    public var lastUsedLabel: String? {
        guard let date = customization.lastUsedAt else { return nil }
        return "Last used \(formatRelativeDate(date))"
    }

    public var usageCountLabel: String? {
        guard let count = customization.usageCount else { return nil }
        return "\(count) uses"
    }

    // MARK: - Metadata Display

    public var triggerCommands: [String] {
        customization.metadata.triggerCommands ?? []
    }

    public var toolRestrictions: [String] {
        customization.metadata.toolRestrictions ?? []
    }

    public var scripts: [String] {
        customization.metadata.scriptPaths ?? []
    }

    // MARK: - Helpers

    private func formatCapabilityName(_ capability: CustomizationCapability) -> String {
        capability.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func colorForCapability(_ capability: CustomizationCapability) -> String {
        switch capability {
        case .toolRestriction: "#F97316"    // Orange
        case .proceduralSteps: "#9945FF"    // Purple
        case .scriptExecution: "#EF4444"    // Red
        case .contextInjection: "#3B82F6"   // Blue
        case .externalIntegration: "#EC4899" // Pink
        case .codeGeneration: "#22C55E"     // Green
        case .fileOrganization: "#6366F1"   // Indigo
        case .commandShortcut: "#14B8A6"    // Teal
        }
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Capability Tag

public struct CapabilityTag: Hashable, Sendable {
    public let name: String
    public let colorHex: String
}

// MARK: - Rainbow Power View

/// Aggregated view model for the "rainbow power view" - a colorful visualization
/// of all customizations organized by type and health.
public struct RainbowPowerViewModel: Sendable {
    public let collection: CustomizationCollection
    public let generatedAt: Date

    public init(collection: CustomizationCollection) {
        self.collection = collection
        self.generatedAt = Date()
    }

    // MARK: - Type Distribution (Rainbow Visualization)

    /// Color-coded segments for each customization type
    public var typeSegments: [TypeSegment] {
        CustomizationType.allCases.compactMap { type in
            let customizations = collection.byType[type] ?? []
            guard !customizations.isEmpty else { return nil }

            return TypeSegment(
                type: type,
                count: customizations.count,
                colorHex: type.colorHex,
                percentage: Double(customizations.count) / Double(max(1, collection.customizations.count))
            )
        }
    }

    /// Cards organized by type for drill-down
    public var cardsByType: [(type: CustomizationType, cards: [CustomizationCardViewModel])] {
        CustomizationType.allCases.compactMap { type in
            let customizations = collection.byType[type] ?? []
            guard !customizations.isEmpty else { return nil }

            return (type, customizations.map { CustomizationCardViewModel(customization: $0) })
        }
    }

    // MARK: - Health Overview

    public var healthOverview: HealthOverview {
        let summary = collection.healthSummary
        return HealthOverview(
            healthy: summary.healthy,
            warning: summary.warning,
            stale: summary.stale,
            unknown: summary.unknown,
            total: collection.customizations.count
        )
    }

    // MARK: - Insights

    public var insights: [Insight] {
        var insights: [Insight] = []

        // Stale customizations warning
        let staleCount = collection.needsAttention.count
        if staleCount > 0 {
            insights.append(Insight(
                type: .warning,
                title: "\(staleCount) customization\(staleCount == 1 ? "" : "s") may need review",
                description: "Some customizations haven't been used recently and may be outdated.",
                actionLabel: "Review stale customizations"
            ))
        }

        // Type coverage gaps
        let missingTypes = CustomizationType.allCases.filter { collection.byType[$0]?.isEmpty ?? true }
        if !missingTypes.isEmpty {
            insights.append(Insight(
                type: .suggestion,
                title: "Consider adding: \(missingTypes.map { $0.displayName }.joined(separator: ", "))",
                description: "These customization types aren't being used in this project.",
                actionLabel: nil
            ))
        }

        // High usage recognition
        if let mostUsed = collection.recentlyUsed.first {
            insights.append(Insight(
                type: .success,
                title: "Most active: \(mostUsed.name)",
                description: "This \(mostUsed.type.displayName.lowercased()) is frequently used.",
                actionLabel: nil
            ))
        }

        return insights
    }

    // MARK: - Quick Stats

    public var totalCount: Int {
        collection.customizations.count
    }

    public var localCount: Int {
        collection.bySource[.local]?.count ?? 0
    }

    public var globalCount: Int {
        collection.bySource[.global]?.count ?? 0
    }
}

// MARK: - Type Segment

public struct TypeSegment: Identifiable, Hashable, Sendable {
    public var id: CustomizationType { type }
    public let type: CustomizationType
    public let count: Int
    public let colorHex: String
    public let percentage: Double

    public var displayLabel: String {
        "\(type.displayName): \(count)"
    }
}

// MARK: - Health Overview

public struct HealthOverview: Sendable {
    public let healthy: Int
    public let warning: Int
    public let stale: Int
    public let unknown: Int
    public let total: Int

    public var healthPercentage: Double {
        guard total > 0 else { return 0 }
        return Double(healthy) / Double(total) * 100
    }
}

// MARK: - Insight

public struct Insight: Identifiable, Sendable {
    public let id = UUID()
    public let type: InsightType
    public let title: String
    public let description: String
    public let actionLabel: String?
}

public enum InsightType: String, Sendable {
    case warning
    case suggestion
    case success
    case info

    public var colorHex: String {
        switch self {
        case .warning: "#F59E0B"
        case .suggestion: "#3B82F6"
        case .success: "#22C55E"
        case .info: "#6B7280"
        }
    }
}
