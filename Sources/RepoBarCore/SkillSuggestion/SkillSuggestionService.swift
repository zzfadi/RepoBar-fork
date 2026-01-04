import Foundation

// MARK: - Skill Suggestion Service

/// Main service that orchestrates the skill suggestion functionality.
/// Combines scanning, analysis, and suggestion generation.
public actor SkillSuggestionService {
    private let scanner: CustomizationScanner
    private let suggestionEngine: SuggestionEngine
    private let templates: FormattingTemplates

    private var cachedCollection: CustomizationCollection?
    private var cacheTimestamp: Date?

    public init() {
        self.scanner = CustomizationScanner()
        self.suggestionEngine = SuggestionEngine()
        self.templates = FormattingTemplates()
    }

    // MARK: - Scanning

    /// Scan a project for existing customizations
    public func scanProject(at path: String) async throws -> CustomizationCollection {
        let collection = try await scanner.scan(projectPath: path)
        cachedCollection = collection
        cacheTimestamp = Date()
        return collection
    }

    /// Get cached collection or scan if stale
    public func getCustomizations(
        projectPath: String,
        maxAge: TimeInterval = 300 // 5 minutes
    ) async throws -> CustomizationCollection {
        if let cached = cachedCollection,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < maxAge {
            return cached
        }

        return try await scanProject(at: path)
    }

    // MARK: - Suggestions

    /// Get suggestions for a use case description
    public func suggestForUseCase(_ useCase: String) -> SuggestionResult {
        suggestionEngine.suggest(for: useCase)
    }

    /// Get suggestions for a specific category
    public func suggestForCategory(_ category: UseCaseCategory) -> [TypeSuggestion] {
        suggestionEngine.suggest(forCategory: category)
    }

    /// Get suggestions based on required capabilities
    public func suggestForCapabilities(_ capabilities: Set<CustomizationCapability>) -> [CustomizationType] {
        suggestionEngine.suggest(forCapabilities: capabilities)
    }

    // MARK: - Template Generation

    /// Generate a template for a customization type
    public func generateTemplate(
        type: CustomizationType,
        name: String,
        description: String,
        options: TemplateOptions = .init()
    ) -> GeneratedTemplate {
        templates.generateTemplate(for: type, name: name, description: description, options: options)
    }

    /// Write generated template files to disk
    public func writeTemplate(
        _ template: GeneratedTemplate,
        to projectPath: String
    ) async throws {
        let fileManager = FileManager.default

        for file in template.files {
            let fullPath = (projectPath as NSString).appendingPathComponent(file.relativePath)
            let directory = (fullPath as NSString).deletingLastPathComponent

            // Create directory if needed
            if !fileManager.fileExists(atPath: directory) {
                try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
            }

            // Write file
            try file.content.write(toFile: fullPath, atomically: true, encoding: .utf8)

            // Set executable permission if needed
            if file.isExecutable {
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fullPath)
            }
        }
    }

    // MARK: - Visualization

    /// Get rainbow power view model for visualization
    public func getRainbowPowerView(projectPath: String) async throws -> RainbowPowerViewModel {
        let collection = try await scanProject(at: projectPath)
        return RainbowPowerViewModel(collection: collection)
    }

    /// Get card view models for a specific type
    public func getCardsForType(
        _ type: CustomizationType,
        projectPath: String
    ) async throws -> [CustomizationCardViewModel] {
        let collection = try await getCustomizations(projectPath: projectPath)
        let customizations = collection.byType[type] ?? []
        return customizations.map { CustomizationCardViewModel(customization: $0) }
    }

    // MARK: - Analysis

    /// Analyze existing customizations and provide recommendations
    public func analyzeProject(at path: String) async throws -> ProjectAnalysis {
        let collection = try await scanProject(at: path)

        var recommendations: [String] = []
        var warnings: [String] = []

        // Check for stale customizations
        let staleCount = collection.needsAttention.count
        if staleCount > 0 {
            warnings.append("\(staleCount) customization(s) may be stale and need review")
        }

        // Check for missing instruction files
        let hasInstruction = collection.byType[.instruction]?.isEmpty == false
        if !hasInstruction {
            recommendations.append("Consider adding a CLAUDE.md or AGENTS.md for project context")
        }

        // Check for skill opportunities
        let hasSkills = collection.byType[.skill]?.isEmpty == false
        if !hasSkills && collection.customizations.count > 3 {
            recommendations.append("Consider organizing related customizations into a Skill")
        }

        // Check for external integration opportunities
        let hasMCP = collection.byType[.mcpServer]?.isEmpty == false
        if !hasMCP {
            recommendations.append("MCP servers can provide external tool integration")
        }

        return ProjectAnalysis(
            collection: collection,
            recommendations: recommendations,
            warnings: warnings,
            overallHealth: calculateOverallHealth(collection)
        )
    }

    private func calculateOverallHealth(_ collection: CustomizationCollection) -> HealthScore {
        let summary = collection.healthSummary
        let total = collection.customizations.count

        guard total > 0 else { return .unknown }

        let healthyRatio = Double(summary.healthy) / Double(total)

        if healthyRatio >= 0.8 {
            return .excellent
        } else if healthyRatio >= 0.6 {
            return .good
        } else if healthyRatio >= 0.4 {
            return .fair
        } else {
            return .needsAttention
        }
    }
}

// MARK: - Project Analysis

public struct ProjectAnalysis: Sendable {
    public let collection: CustomizationCollection
    public let recommendations: [String]
    public let warnings: [String]
    public let overallHealth: HealthScore
}

public enum HealthScore: String, Sendable {
    case excellent
    case good
    case fair
    case needsAttention
    case unknown

    public var displayName: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .fair: "Fair"
        case .needsAttention: "Needs Attention"
        case .unknown: "Unknown"
        }
    }

    public var colorHex: String {
        switch self {
        case .excellent: "#22C55E"
        case .good: "#84CC16"
        case .fair: "#F59E0B"
        case .needsAttention: "#EF4444"
        case .unknown: "#6B7280"
        }
    }
}
