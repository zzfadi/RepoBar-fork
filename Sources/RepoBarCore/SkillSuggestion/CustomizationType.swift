import Foundation

// MARK: - Customization Types

/// Represents the different types of AI customizations available in Claude Code and Copilot ecosystems.
/// Each type has different capabilities, formatting requirements, and best use cases.
public enum CustomizationType: String, CaseIterable, Codable, Hashable, Sendable {
    case skill              // Procedural, multi-step workflows with organized scripts
    case customAgent        // Specialized agents with tool restrictions
    case promptFile         // .md files with frontmatter for context injection
    case instruction        // AGENTS.md or CLAUDE.md files for project context
    case mcpServer          // Model Context Protocol servers for external tool integration

    public var displayName: String {
        switch self {
        case .skill: "Skill"
        case .customAgent: "Custom Agent"
        case .promptFile: "Prompt File"
        case .instruction: "Instructions File"
        case .mcpServer: "MCP Server"
        }
    }

    public var description: String {
        switch self {
        case .skill:
            """
            Procedural multi-step workflows with organized folder structure.
            Best for: Complex automation that requires scripts, tools, and clear steps.
            Example: PR review workflow, test automation, debugging procedures.
            """
        case .customAgent:
            """
            Specialized agents with tool restrictions and custom instructions.
            Best for: Focused tasks with specific tool access (e.g., read-only explorer).
            Example: Code reviewer agent, documentation agent, security audit agent.
            """
        case .promptFile:
            """
            Markdown files with YAML frontmatter for context injection.
            Best for: Reusable context, templates, and command shortcuts.
            Example: /review command, /fix command, project context.
            """
        case .instruction:
            """
            AGENTS.md or CLAUDE.md files for project-wide context.
            Best for: Project conventions, architecture decisions, coding standards.
            Example: "Always use TypeScript strict mode", "Follow ABC architecture".
            """
        case .mcpServer:
            """
            Model Context Protocol servers for external tool integration.
            Best for: Connecting to external APIs, databases, or custom tools.
            Example: Database query tool, Slack integration, custom API access.
            """
        }
    }

    public var fileExtension: String? {
        switch self {
        case .skill: nil  // Directory-based
        case .customAgent: "yaml"
        case .promptFile: "md"
        case .instruction: "md"
        case .mcpServer: "json"
        }
    }

    public var typicalLocation: String {
        switch self {
        case .skill: ".claude/skills/"
        case .customAgent: ".github/copilot/agents/"
        case .promptFile: ".claude/commands/ or .github/copilot/prompts/"
        case .instruction: "AGENTS.md, CLAUDE.md, or .github/copilot-instructions.md"
        case .mcpServer: ".claude/mcp.json or settings"
        }
    }

    /// Color for visualization (inspired by contribution heatmap palette)
    public var colorHex: String {
        switch self {
        case .skill: "#9945FF"          // Purple - most powerful
        case .customAgent: "#F97316"     // Orange - specialized
        case .promptFile: "#22C55E"      // Green - common
        case .instruction: "#3B82F6"     // Blue - foundational
        case .mcpServer: "#EC4899"       // Pink - external
        }
    }
}

// MARK: - Customization Capability

/// Capabilities that different customization types can provide
public enum CustomizationCapability: String, CaseIterable, Codable, Hashable, Sendable {
    case toolRestriction        // Limit available tools
    case proceduralSteps        // Multi-step workflows
    case scriptExecution        // Run custom scripts
    case contextInjection       // Add context to prompts
    case externalIntegration    // Connect to external services
    case codeGeneration         // Generate code
    case fileOrganization       // Organize files/folders
    case commandShortcut        // Slash command shortcut

    public var supportedBy: Set<CustomizationType> {
        switch self {
        case .toolRestriction:
            [.customAgent, .skill]
        case .proceduralSteps:
            [.skill]
        case .scriptExecution:
            [.skill, .mcpServer]
        case .contextInjection:
            [.promptFile, .instruction, .skill, .customAgent]
        case .externalIntegration:
            [.mcpServer]
        case .codeGeneration:
            [.skill, .customAgent, .promptFile]
        case .fileOrganization:
            [.skill]
        case .commandShortcut:
            [.promptFile, .skill]
        }
    }
}

// MARK: - Use Case Categories

/// Common use case categories for suggesting customization types
public enum UseCaseCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case prReview = "pr_review"
    case testing = "testing"
    case debugging = "debugging"
    case ciCd = "ci_cd"
    case documentation = "documentation"
    case codeGeneration = "code_generation"
    case refactoring = "refactoring"
    case security = "security"
    case projectSetup = "project_setup"
    case externalApi = "external_api"
    case dataAnalysis = "data_analysis"
    case learning = "learning"

    public var displayName: String {
        switch self {
        case .prReview: "PR Review"
        case .testing: "Testing"
        case .debugging: "Debugging"
        case .ciCd: "CI/CD"
        case .documentation: "Documentation"
        case .codeGeneration: "Code Generation"
        case .refactoring: "Refactoring"
        case .security: "Security"
        case .projectSetup: "Project Setup"
        case .externalApi: "External API"
        case .dataAnalysis: "Data Analysis"
        case .learning: "Learning"
        }
    }

    /// Recommended customization types for this use case, ordered by preference
    public var recommendedTypes: [CustomizationType] {
        switch self {
        case .prReview:
            [.skill, .customAgent, .promptFile]
        case .testing:
            [.skill, .promptFile, .instruction]
        case .debugging:
            [.skill, .promptFile]
        case .ciCd:
            [.skill, .mcpServer]
        case .documentation:
            [.customAgent, .promptFile, .instruction]
        case .codeGeneration:
            [.promptFile, .skill, .instruction]
        case .refactoring:
            [.customAgent, .promptFile]
        case .security:
            [.customAgent, .skill]
        case .projectSetup:
            [.instruction, .skill]
        case .externalApi:
            [.mcpServer, .skill]
        case .dataAnalysis:
            [.mcpServer, .skill, .promptFile]
        case .learning:
            [.instruction, .promptFile]
        }
    }

    public var description: String {
        switch self {
        case .prReview:
            "Automating pull request review workflows"
        case .testing:
            "Running tests and analyzing results"
        case .debugging:
            "Finding and fixing issues"
        case .ciCd:
            "Continuous integration and deployment"
        case .documentation:
            "Writing and maintaining documentation"
        case .codeGeneration:
            "Generating code from specifications"
        case .refactoring:
            "Improving code structure"
        case .security:
            "Security audits and vulnerability scanning"
        case .projectSetup:
            "Setting up new projects or features"
        case .externalApi:
            "Integrating with external services"
        case .dataAnalysis:
            "Analyzing data and generating reports"
        case .learning:
            "Understanding codebase or learning patterns"
        }
    }
}
