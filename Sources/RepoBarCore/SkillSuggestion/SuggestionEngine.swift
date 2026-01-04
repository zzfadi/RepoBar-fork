import Foundation

// MARK: - Suggestion Engine

/// Engine that suggests the most appropriate customization type based on use case analysis.
/// Addresses the challenge of "lots of conflict between these types of customization"
/// by providing a structured decision framework.
public struct SuggestionEngine: Sendable {
    public init() {}

    /// Analyze a use case description and suggest appropriate customization types
    public func suggest(for useCase: String) -> SuggestionResult {
        let analyzed = analyzeUseCase(useCase)
        let scores = scoreCustomizationTypes(for: analyzed)
        let ranked = rankSuggestions(scores: scores, analysis: analyzed)

        return SuggestionResult(
            query: useCase,
            analysis: analyzed,
            suggestions: ranked,
            confidence: calculateConfidence(scores: scores)
        )
    }

    /// Suggest based on required capabilities
    public func suggest(forCapabilities capabilities: Set<CustomizationCapability>) -> [CustomizationType] {
        CustomizationType.allCases.sorted { typeA, typeB in
            let scoreA = capabilities.filter { $0.supportedBy.contains(typeA) }.count
            let scoreB = capabilities.filter { $0.supportedBy.contains(typeB) }.count
            return scoreA > scoreB
        }
    }

    /// Suggest based on a known use case category
    public func suggest(forCategory category: UseCaseCategory) -> [TypeSuggestion] {
        category.recommendedTypes.enumerated().map { index, type in
            TypeSuggestion(
                type: type,
                score: 1.0 - (Double(index) * 0.2),
                reasons: [reasonForCategory(category, type: type)],
                caveats: caveatsForType(type)
            )
        }
    }

    // MARK: - Analysis

    private func analyzeUseCase(_ useCase: String) -> UseCaseAnalysis {
        let lowercased = useCase.lowercased()

        var detectedCapabilities: Set<CustomizationCapability> = []
        var detectedCategories: Set<UseCaseCategory> = []
        var complexity: UseCaseComplexity = .simple

        // Detect capabilities from keywords
        if containsAny(lowercased, keywords: ["restrict", "limit", "only allow", "read-only", "no write"]) {
            detectedCapabilities.insert(.toolRestriction)
        }
        if containsAny(lowercased, keywords: ["step", "workflow", "process", "procedure", "then", "after that"]) {
            detectedCapabilities.insert(.proceduralSteps)
            complexity = .moderate
        }
        if containsAny(lowercased, keywords: ["script", "run", "execute", "bash", "shell"]) {
            detectedCapabilities.insert(.scriptExecution)
        }
        if containsAny(lowercased, keywords: ["context", "background", "remember", "always", "convention"]) {
            detectedCapabilities.insert(.contextInjection)
        }
        if containsAny(lowercased, keywords: ["api", "external", "slack", "database", "connect", "integrate"]) {
            detectedCapabilities.insert(.externalIntegration)
        }
        if containsAny(lowercased, keywords: ["generate", "create code", "scaffold", "boilerplate"]) {
            detectedCapabilities.insert(.codeGeneration)
        }
        if containsAny(lowercased, keywords: ["command", "shortcut", "slash", "/", "quick"]) {
            detectedCapabilities.insert(.commandShortcut)
        }

        // Detect categories from keywords
        if containsAny(lowercased, keywords: ["pr", "pull request", "review", "code review"]) {
            detectedCategories.insert(.prReview)
        }
        if containsAny(lowercased, keywords: ["test", "testing", "spec", "unit test", "integration"]) {
            detectedCategories.insert(.testing)
        }
        if containsAny(lowercased, keywords: ["debug", "bug", "fix", "issue", "error", "troubleshoot"]) {
            detectedCategories.insert(.debugging)
        }
        if containsAny(lowercased, keywords: ["ci", "cd", "deploy", "pipeline", "build", "release"]) {
            detectedCategories.insert(.ciCd)
        }
        if containsAny(lowercased, keywords: ["doc", "documentation", "readme", "explain"]) {
            detectedCategories.insert(.documentation)
        }
        if containsAny(lowercased, keywords: ["security", "vulnerability", "audit", "scan"]) {
            detectedCategories.insert(.security)
        }
        if containsAny(lowercased, keywords: ["refactor", "clean up", "improve", "restructure"]) {
            detectedCategories.insert(.refactoring)
        }
        if containsAny(lowercased, keywords: ["setup", "configure", "initialize", "bootstrap"]) {
            detectedCategories.insert(.projectSetup)
        }

        // Adjust complexity
        if detectedCapabilities.count >= 3 {
            complexity = .complex
        }
        if containsAny(lowercased, keywords: ["complex", "multiple", "advanced", "comprehensive"]) {
            complexity = .complex
        }

        return UseCaseAnalysis(
            originalQuery: useCase,
            detectedCapabilities: detectedCapabilities,
            detectedCategories: detectedCategories,
            complexity: complexity
        )
    }

    private func scoreCustomizationTypes(for analysis: UseCaseAnalysis) -> [CustomizationType: Double] {
        var scores: [CustomizationType: Double] = [:]

        for type in CustomizationType.allCases {
            var score: Double = 0

            // Score based on capability match
            for capability in analysis.detectedCapabilities {
                if capability.supportedBy.contains(type) {
                    score += 1.0
                }
            }

            // Score based on category match
            for category in analysis.detectedCategories {
                if let index = category.recommendedTypes.firstIndex(of: type) {
                    score += 1.0 - (Double(index) * 0.2)
                }
            }

            // Adjust for complexity
            switch analysis.complexity {
            case .simple:
                if type == .promptFile || type == .instruction {
                    score += 0.5
                }
            case .moderate:
                if type == .skill || type == .customAgent {
                    score += 0.5
                }
            case .complex:
                if type == .skill {
                    score += 1.0
                }
            }

            scores[type] = score
        }

        return scores
    }

    private func rankSuggestions(scores: [CustomizationType: Double], analysis: UseCaseAnalysis) -> [TypeSuggestion] {
        scores.sorted { $0.value > $1.value }
            .map { type, score in
                TypeSuggestion(
                    type: type,
                    score: normalizeScore(score, maxPossible: Double(analysis.detectedCapabilities.count + analysis.detectedCategories.count + 2)),
                    reasons: generateReasons(for: type, analysis: analysis),
                    caveats: caveatsForType(type)
                )
            }
    }

    private func normalizeScore(_ score: Double, maxPossible: Double) -> Double {
        guard maxPossible > 0 else { return 0.5 }
        return min(1.0, score / maxPossible)
    }

    private func calculateConfidence(scores: [CustomizationType: Double]) -> SuggestionConfidence {
        let sortedScores = scores.values.sorted(by: >)
        guard sortedScores.count >= 2 else { return .low }

        let topScore = sortedScores[0]
        let secondScore = sortedScores[1]

        if topScore == 0 {
            return .low
        }

        let gap = topScore - secondScore

        if gap > 2.0 {
            return .high
        } else if gap > 1.0 {
            return .medium
        } else {
            return .low
        }
    }

    private func generateReasons(for type: CustomizationType, analysis: UseCaseAnalysis) -> [String] {
        var reasons: [String] = []

        // Capability-based reasons
        for capability in analysis.detectedCapabilities {
            if capability.supportedBy.contains(type) {
                reasons.append("Supports \(capability.rawValue.replacingOccurrences(of: "_", with: " "))")
            }
        }

        // Category-based reasons
        for category in analysis.detectedCategories {
            if category.recommendedTypes.contains(type) {
                reasons.append("Commonly used for \(category.displayName.lowercased())")
            }
        }

        // Type-specific reasons
        switch type {
        case .skill:
            if analysis.complexity == .complex {
                reasons.append("Handles complex multi-step workflows")
            }
            reasons.append("Organized folder structure for scripts and tools")
        case .customAgent:
            reasons.append("Focused agent with specific tool restrictions")
        case .promptFile:
            if analysis.complexity == .simple {
                reasons.append("Simple and quick to create")
            }
            reasons.append("Reusable as slash command")
        case .instruction:
            reasons.append("Applies to entire project automatically")
        case .mcpServer:
            if analysis.detectedCapabilities.contains(.externalIntegration) {
                reasons.append("Required for external service integration")
            }
        }

        return reasons
    }

    private func caveatsForType(_ type: CustomizationType) -> [String] {
        switch type {
        case .skill:
            return [
                "Requires more setup and organization",
                "Models may treat as regular instructions",
                "Higher token usage for complex skills"
            ]
        case .customAgent:
            return [
                "Limited to specific tool configurations",
                "May need GUI to select tools correctly",
                "Tool naming requires API awareness"
            ]
        case .promptFile:
            return [
                "Less structured than Skills",
                "Frontmatter formatting must be exact",
                "Limited procedural capabilities"
            ]
        case .instruction:
            return [
                "Applied globally - may affect unintended contexts",
                "Can become stale as project evolves",
                "No tool restrictions available"
            ]
        case .mcpServer:
            return [
                "Requires external server setup",
                "Security considerations for API access",
                "More complex maintenance"
            ]
        }
    }

    private func reasonForCategory(_ category: UseCaseCategory, type: CustomizationType) -> String {
        "\(type.displayName) is recommended for \(category.displayName.lowercased()) workflows"
    }

    private func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

// MARK: - Analysis Types

public struct UseCaseAnalysis: Sendable {
    public let originalQuery: String
    public let detectedCapabilities: Set<CustomizationCapability>
    public let detectedCategories: Set<UseCaseCategory>
    public let complexity: UseCaseComplexity
}

public enum UseCaseComplexity: String, Sendable {
    case simple
    case moderate
    case complex

    public var displayName: String {
        rawValue.capitalized
    }
}

public enum SuggestionConfidence: String, Sendable {
    case high
    case medium
    case low

    public var displayName: String {
        switch self {
        case .high: "High confidence"
        case .medium: "Medium confidence"
        case .low: "Multiple options viable"
        }
    }
}

// MARK: - Suggestion Result

public struct SuggestionResult: Sendable {
    public let query: String
    public let analysis: UseCaseAnalysis
    public let suggestions: [TypeSuggestion]
    public let confidence: SuggestionConfidence

    public var topSuggestion: TypeSuggestion? {
        suggestions.first
    }

    public var alternativeSuggestions: [TypeSuggestion] {
        Array(suggestions.dropFirst())
    }
}

public struct TypeSuggestion: Sendable {
    public let type: CustomizationType
    public let score: Double
    public let reasons: [String]
    public let caveats: [String]

    public var scorePercentage: Int {
        Int(score * 100)
    }
}
