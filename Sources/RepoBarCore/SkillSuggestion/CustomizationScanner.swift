import Foundation

// MARK: - Customization Scanner

/// Scans projects for existing AI customizations.
/// Inspired by RepoBar's LocalProjectManager pattern.
public actor CustomizationScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Scan a project directory for all customizations
    public func scan(projectPath: String) async throws -> CustomizationCollection {
        var customizations: [Customization] = []

        // Scan for Claude Code customizations
        customizations.append(contentsOf: try await scanClaudeSkills(in: projectPath))
        customizations.append(contentsOf: try await scanClaudeCommands(in: projectPath))
        customizations.append(contentsOf: try await scanClaudeMCP(in: projectPath))
        customizations.append(contentsOf: try await scanInstructionFiles(in: projectPath))

        // Scan for GitHub Copilot customizations
        customizations.append(contentsOf: try await scanCopilotAgents(in: projectPath))
        customizations.append(contentsOf: try await scanCopilotPrompts(in: projectPath))
        customizations.append(contentsOf: try await scanCopilotInstructions(in: projectPath))

        return CustomizationCollection(customizations: customizations)
    }

    // MARK: - Claude Code Scanning

    private func scanClaudeSkills(in projectPath: String) async throws -> [Customization] {
        let skillsPath = (projectPath as NSString).appendingPathComponent(".claude/skills")
        guard fileManager.fileExists(atPath: skillsPath) else { return [] }

        var customizations: [Customization] = []

        let contents = try fileManager.contentsOfDirectory(atPath: skillsPath)
        for item in contents {
            let itemPath = (skillsPath as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false

            if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory), isDirectory.boolValue {
                // This is a skill folder
                let skillMetadata = try await parseSkillMetadata(at: itemPath)

                customizations.append(Customization(
                    type: .skill,
                    name: item,
                    path: itemPath,
                    description: skillMetadata.description,
                    capabilities: skillMetadata.capabilities,
                    modifiedAt: try? fileModificationDate(at: itemPath),
                    source: .local,
                    metadata: skillMetadata.metadata
                ))
            }
        }

        return customizations
    }

    private func scanClaudeCommands(in projectPath: String) async throws -> [Customization] {
        let commandsPath = (projectPath as NSString).appendingPathComponent(".claude/commands")
        guard fileManager.fileExists(atPath: commandsPath) else { return [] }

        return try await scanMarkdownFiles(in: commandsPath, type: .promptFile)
    }

    private func scanClaudeMCP(in projectPath: String) async throws -> [Customization] {
        let mcpPath = (projectPath as NSString).appendingPathComponent(".claude/mcp.json")
        guard fileManager.fileExists(atPath: mcpPath) else { return [] }

        var customizations: [Customization] = []

        if let data = fileManager.contents(atPath: mcpPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let servers = json["mcpServers"] as? [String: Any] {
            for (name, _) in servers {
                customizations.append(Customization(
                    type: .mcpServer,
                    name: name,
                    path: mcpPath,
                    description: "MCP Server: \(name)",
                    capabilities: [.externalIntegration, .scriptExecution],
                    modifiedAt: try? fileModificationDate(at: mcpPath),
                    source: .local
                ))
            }
        }

        return customizations
    }

    private func scanInstructionFiles(in projectPath: String) async throws -> [Customization] {
        var customizations: [Customization] = []

        let instructionFiles = ["AGENTS.md", "CLAUDE.md", ".claude/settings.json"]

        for fileName in instructionFiles {
            let filePath = (projectPath as NSString).appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: filePath) {
                let frontmatter = fileName.hasSuffix(".md")
                    ? try? await parseMarkdownFrontmatter(at: filePath)
                    : nil

                customizations.append(Customization(
                    type: .instruction,
                    name: fileName,
                    path: filePath,
                    description: frontmatter?["description"],
                    capabilities: [.contextInjection],
                    modifiedAt: try? fileModificationDate(at: filePath),
                    source: .local,
                    metadata: CustomizationMetadata(frontmatter: frontmatter)
                ))
            }
        }

        return customizations
    }

    // MARK: - GitHub Copilot Scanning

    private func scanCopilotAgents(in projectPath: String) async throws -> [Customization] {
        let agentsPath = (projectPath as NSString).appendingPathComponent(".github/copilot/agents")
        guard fileManager.fileExists(atPath: agentsPath) else { return [] }

        var customizations: [Customization] = []

        let contents = try fileManager.contentsOfDirectory(atPath: agentsPath)
        for item in contents where item.hasSuffix(".yaml") || item.hasSuffix(".yml") {
            let itemPath = (agentsPath as NSString).appendingPathComponent(item)
            let agentMetadata = try await parseCopilotAgentMetadata(at: itemPath)

            customizations.append(Customization(
                type: .customAgent,
                name: item.replacingOccurrences(of: ".yaml", with: "").replacingOccurrences(of: ".yml", with: ""),
                path: itemPath,
                description: agentMetadata.description,
                capabilities: agentMetadata.capabilities,
                modifiedAt: try? fileModificationDate(at: itemPath),
                source: .local,
                metadata: agentMetadata.metadata
            ))
        }

        return customizations
    }

    private func scanCopilotPrompts(in projectPath: String) async throws -> [Customization] {
        let promptsPath = (projectPath as NSString).appendingPathComponent(".github/copilot/prompts")
        guard fileManager.fileExists(atPath: promptsPath) else { return [] }

        return try await scanMarkdownFiles(in: promptsPath, type: .promptFile)
    }

    private func scanCopilotInstructions(in projectPath: String) async throws -> [Customization] {
        var customizations: [Customization] = []

        let copilotInstructionsPath = (projectPath as NSString).appendingPathComponent(".github/copilot-instructions.md")
        if fileManager.fileExists(atPath: copilotInstructionsPath) {
            customizations.append(Customization(
                type: .instruction,
                name: "copilot-instructions.md",
                path: copilotInstructionsPath,
                description: "GitHub Copilot instructions",
                capabilities: [.contextInjection],
                modifiedAt: try? fileModificationDate(at: copilotInstructionsPath),
                source: .local
            ))
        }

        return customizations
    }

    // MARK: - Helpers

    private func scanMarkdownFiles(in directory: String, type: CustomizationType) async throws -> [Customization] {
        var customizations: [Customization] = []

        let contents = try fileManager.contentsOfDirectory(atPath: directory)
        for item in contents where item.hasSuffix(".md") {
            let itemPath = (directory as NSString).appendingPathComponent(item)
            let frontmatter = try? await parseMarkdownFrontmatter(at: itemPath)

            customizations.append(Customization(
                type: type,
                name: item.replacingOccurrences(of: ".md", with: ""),
                path: itemPath,
                description: frontmatter?["description"],
                capabilities: [.contextInjection, .commandShortcut],
                modifiedAt: try? fileModificationDate(at: itemPath),
                source: .local,
                metadata: CustomizationMetadata(
                    triggerCommands: ["/\(item.replacingOccurrences(of: ".md", with: ""))"],
                    frontmatter: frontmatter
                )
            ))
        }

        return customizations
    }

    private func parseSkillMetadata(at path: String) async throws -> (description: String?, capabilities: Set<CustomizationCapability>, metadata: CustomizationMetadata) {
        // Look for a skill.md or index.md file
        let potentialReadmes = ["skill.md", "index.md", "README.md"]
        var description: String?
        var frontmatter: [String: String]?

        for readme in potentialReadmes {
            let readmePath = (path as NSString).appendingPathComponent(readme)
            if fileManager.fileExists(atPath: readmePath) {
                frontmatter = try? await parseMarkdownFrontmatter(at: readmePath)
                description = frontmatter?["description"]
                break
            }
        }

        // Scan for scripts
        var scriptPaths: [String] = []
        if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
            for item in contents where item.hasSuffix(".sh") || item.hasSuffix(".py") || item.hasSuffix(".js") {
                scriptPaths.append(item)
            }
        }

        var capabilities: Set<CustomizationCapability> = [.proceduralSteps, .fileOrganization]
        if !scriptPaths.isEmpty {
            capabilities.insert(.scriptExecution)
        }

        return (
            description,
            capabilities,
            CustomizationMetadata(frontmatter: frontmatter, scriptPaths: scriptPaths.isEmpty ? nil : scriptPaths)
        )
    }

    private func parseCopilotAgentMetadata(at path: String) async throws -> (description: String?, capabilities: Set<CustomizationCapability>, metadata: CustomizationMetadata) {
        guard let data = fileManager.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return (nil, [.toolRestriction], CustomizationMetadata())
        }

        // Basic YAML parsing for description and tools
        var description: String?
        var toolRestrictions: [String] = []

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("description:") {
                description = line.replacingOccurrences(of: "description:", with: "").trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("  - ") && lines.contains(where: { $0.contains("tools:") }) {
                toolRestrictions.append(line.replacingOccurrences(of: "  - ", with: "").trimmingCharacters(in: .whitespaces))
            }
        }

        return (
            description,
            [.toolRestriction, .contextInjection],
            CustomizationMetadata(toolRestrictions: toolRestrictions.isEmpty ? nil : toolRestrictions)
        )
    }

    private func parseMarkdownFrontmatter(at path: String) async throws -> [String: String]? {
        guard let data = fileManager.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Check for YAML frontmatter (between --- markers)
        guard content.hasPrefix("---") else { return nil }

        let lines = content.components(separatedBy: .newlines)
        var inFrontmatter = false
        var frontmatter: [String: String] = [:]

        for line in lines {
            if line == "---" {
                if inFrontmatter {
                    break // End of frontmatter
                } else {
                    inFrontmatter = true
                    continue
                }
            }

            if inFrontmatter, let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                frontmatter[key] = value
            }
        }

        return frontmatter.isEmpty ? nil : frontmatter
    }

    private func fileModificationDate(at path: String) throws -> Date? {
        let attributes = try fileManager.attributesOfItem(atPath: path)
        return attributes[.modificationDate] as? Date
    }
}

// MARK: - Scanner Errors

public enum CustomizationScannerError: Error, LocalizedError {
    case directoryNotFound(String)
    case accessDenied(String)
    case parsingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            "Directory not found: \(path)"
        case .accessDenied(let path):
            "Access denied: \(path)"
        case .parsingFailed(let path):
            "Failed to parse: \(path)"
        }
    }
}
