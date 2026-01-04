import Foundation

// MARK: - Formatting Templates

/// Generates correctly formatted templates for each customization type.
/// Addresses the challenge of "models are not great at generating the correct formatting".
public struct FormattingTemplates: Sendable {
    public init() {}

    /// Generate a complete template for a customization type
    public func generateTemplate(
        for type: CustomizationType,
        name: String,
        description: String,
        options: TemplateOptions = .init()
    ) -> GeneratedTemplate {
        switch type {
        case .skill:
            return generateSkillTemplate(name: name, description: description, options: options)
        case .customAgent:
            return generateCustomAgentTemplate(name: name, description: description, options: options)
        case .promptFile:
            return generatePromptFileTemplate(name: name, description: description, options: options)
        case .instruction:
            return generateInstructionTemplate(name: name, description: description, options: options)
        case .mcpServer:
            return generateMCPServerTemplate(name: name, description: description, options: options)
        }
    }

    // MARK: - Skill Template

    private func generateSkillTemplate(name: String, description: String, options: TemplateOptions) -> GeneratedTemplate {
        let folderName = name.lowercased().replacingOccurrences(of: " ", with: "-")

        let indexMd = """
        ---
        name: \(name)
        description: \(description)
        version: 1.0.0
        author: \(options.author ?? "")
        ---

        # \(name)

        \(description)

        ## Usage

        This skill can be invoked by asking Claude to use the "\(name)" skill.

        ## Steps

        1. **Step 1**: Description of first step
        2. **Step 2**: Description of second step
        3. **Step 3**: Description of third step

        ## Scripts

        - `scripts/main.sh` - Main execution script
        - `scripts/validate.sh` - Validation script

        ## Configuration

        This skill accepts the following parameters:

        | Parameter | Type | Required | Description |
        |-----------|------|----------|-------------|
        | param1    | string | Yes | Description of param1 |
        | param2    | boolean | No | Description of param2 |

        """

        let mainScript = """
        #!/bin/bash
        # Main script for \(name) skill
        # This script is executed as part of the skill workflow

        set -e

        echo "Executing \(name) skill..."

        # Add your logic here

        echo "Done."
        """

        return GeneratedTemplate(
            type: .skill,
            name: name,
            files: [
                GeneratedFile(
                    relativePath: ".claude/skills/\(folderName)/index.md",
                    content: indexMd,
                    isDirectory: false
                ),
                GeneratedFile(
                    relativePath: ".claude/skills/\(folderName)/scripts/main.sh",
                    content: mainScript,
                    isDirectory: false,
                    isExecutable: true
                )
            ],
            instructions: """
            Created skill folder structure at .claude/skills/\(folderName)/
            - index.md: Main skill definition with frontmatter
            - scripts/main.sh: Executable script (chmod +x applied)

            Next steps:
            1. Edit index.md to define your skill's steps
            2. Add any additional scripts to the scripts/ folder
            3. Test by asking Claude to use the "\(name)" skill
            """
        )
    }

    // MARK: - Custom Agent Template (GitHub Copilot)

    private func generateCustomAgentTemplate(name: String, description: String, options: TemplateOptions) -> GeneratedTemplate {
        let fileName = name.lowercased().replacingOccurrences(of: " ", with: "-")

        let agentYaml = """
        name: \(name)
        description: \(description)
        instructions: |
          You are a specialized agent for \(description.lowercased()).

          ## Guidelines

          - Follow best practices for the task at hand
          - Ask clarifying questions when requirements are unclear
          - Provide clear explanations of your actions

          ## Scope

          Focus on the specific task requested. Do not make changes outside
          the scope of the request.

        tools:
        \(generateToolsList(options.tools))
        """

        return GeneratedTemplate(
            type: .customAgent,
            name: name,
            files: [
                GeneratedFile(
                    relativePath: ".github/copilot/agents/\(fileName).yaml",
                    content: agentYaml,
                    isDirectory: false
                )
            ],
            instructions: """
            Created custom agent at .github/copilot/agents/\(fileName).yaml

            Available tools to consider adding:
            - read_file: Read file contents
            - write_file: Write/create files
            - run_command: Execute shell commands
            - search_code: Search codebase
            - git_operations: Git commands
            - browser: Web browsing (for research agents)

            To use: @\(fileName) in GitHub Copilot Chat
            """
        )
    }

    // MARK: - Prompt File Template

    private func generatePromptFileTemplate(name: String, description: String, options: TemplateOptions) -> GeneratedTemplate {
        let fileName = name.lowercased().replacingOccurrences(of: " ", with: "-")
        let platform = options.platform ?? .claude

        let frontmatter: String
        let location: String

        switch platform {
        case .claude:
            frontmatter = """
            ---
            description: \(description)
            ---
            """
            location = ".claude/commands/\(fileName).md"
        case .copilot:
            frontmatter = """
            ---
            name: \(name)
            description: \(description)
            ---
            """
            location = ".github/copilot/prompts/\(fileName).md"
        }

        let content = """
        \(frontmatter)

        # \(name)

        \(description)

        ## Instructions

        When this command is invoked:

        1. First, analyze the current context
        2. Then, perform the requested action
        3. Finally, provide a summary of changes made

        ## Parameters

        - `$ARGUMENTS`: Any additional arguments passed to the command

        ## Example Usage

        ```
        /\(fileName) [optional arguments]
        ```

        """

        return GeneratedTemplate(
            type: .promptFile,
            name: name,
            files: [
                GeneratedFile(
                    relativePath: location,
                    content: content,
                    isDirectory: false
                )
            ],
            instructions: """
            Created prompt file at \(location)

            Usage:
            - Claude Code: /\(fileName) [arguments]
            - GitHub Copilot: @workspace /\(fileName)

            The frontmatter format is critical:
            - Must start with --- on its own line
            - Must end with --- on its own line
            - YAML between the markers
            """
        )
    }

    // MARK: - Instruction Template

    private func generateInstructionTemplate(name: String, description: String, options: TemplateOptions) -> GeneratedTemplate {
        let platform = options.platform ?? .claude

        let content: String
        let location: String

        switch platform {
        case .claude:
            location = "CLAUDE.md"
            content = """
            # Project Instructions

            \(description)

            ## Project Overview

            Brief description of this project and its purpose.

            ## Coding Standards

            - Use TypeScript strict mode
            - Follow the existing code style
            - Write tests for new functionality

            ## Architecture

            Describe the project architecture and key patterns used.

            ## Common Tasks

            ### Running Tests
            ```bash
            npm test
            ```

            ### Building
            ```bash
            npm run build
            ```

            ## Important Notes

            - Note any quirks or gotchas
            - Mention any external dependencies
            - Document any non-obvious decisions

            """
        case .copilot:
            location = ".github/copilot-instructions.md"
            content = """
            # GitHub Copilot Instructions

            \(description)

            ## Context

            This file provides context to GitHub Copilot about this project.

            ## Coding Standards

            - Follow existing patterns in the codebase
            - Use descriptive variable and function names
            - Add comments for complex logic

            ## Preferences

            - Prefer functional programming patterns
            - Use async/await over callbacks
            - Keep functions small and focused

            ## Project-Specific Notes

            Add any project-specific guidance here.

            """
        }

        return GeneratedTemplate(
            type: .instruction,
            name: name,
            files: [
                GeneratedFile(
                    relativePath: location,
                    content: content,
                    isDirectory: false
                )
            ],
            instructions: """
            Created instruction file at \(location)

            This file will be automatically included in the context for:
            \(platform == .claude ? "- All Claude Code conversations in this project" : "- All GitHub Copilot interactions in this repository")

            Tips:
            - Keep instructions focused and actionable
            - Update as the project evolves
            - Remove outdated guidance to save tokens
            """
        )
    }

    // MARK: - MCP Server Template

    private func generateMCPServerTemplate(name: String, description: String, options: TemplateOptions) -> GeneratedTemplate {
        let serverName = name.lowercased().replacingOccurrences(of: " ", with: "-")

        let mcpJson = """
        {
          "mcpServers": {
            "\(serverName)": {
              "command": "npx",
              "args": [
                "-y",
                "@modelcontextprotocol/server-\(serverName)"
              ],
              "env": {
                "API_KEY": "${env:API_KEY}"
              }
            }
          }
        }
        """

        let customServerIndex = """
        #!/usr/bin/env node

        /**
         * \(name) MCP Server
         * \(description)
         */

        import { Server } from '@modelcontextprotocol/sdk/server/index.js';
        import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
        import {
          CallToolRequestSchema,
          ListToolsRequestSchema,
        } from '@modelcontextprotocol/sdk/types.js';

        const server = new Server(
          {
            name: '\(serverName)',
            version: '1.0.0',
          },
          {
            capabilities: {
              tools: {},
            },
          }
        );

        // Define available tools
        server.setRequestHandler(ListToolsRequestSchema, async () => {
          return {
            tools: [
              {
                name: 'example_tool',
                description: 'An example tool that demonstrates the MCP pattern',
                inputSchema: {
                  type: 'object',
                  properties: {
                    input: {
                      type: 'string',
                      description: 'The input to process',
                    },
                  },
                  required: ['input'],
                },
              },
            ],
          };
        });

        // Handle tool calls
        server.setRequestHandler(CallToolRequestSchema, async (request) => {
          if (request.params.name === 'example_tool') {
            const input = request.params.arguments?.input;
            return {
              content: [
                {
                  type: 'text',
                  text: `Processed: ${input}`,
                },
              ],
            };
          }

          throw new Error(`Unknown tool: ${request.params.name}`);
        });

        // Start the server
        async function main() {
          const transport = new StdioServerTransport();
          await server.connect(transport);
          console.error('\(name) MCP server running on stdio');
        }

        main().catch(console.error);
        """

        return GeneratedTemplate(
            type: .mcpServer,
            name: name,
            files: [
                GeneratedFile(
                    relativePath: ".claude/mcp.json",
                    content: mcpJson,
                    isDirectory: false
                ),
                GeneratedFile(
                    relativePath: "mcp-servers/\(serverName)/index.js",
                    content: customServerIndex,
                    isDirectory: false
                )
            ],
            instructions: """
            Created MCP server configuration:
            - .claude/mcp.json: Server registration
            - mcp-servers/\(serverName)/index.js: Custom server implementation

            For using existing MCP servers:
            1. Edit .claude/mcp.json to use the correct npm package
            2. Set required environment variables

            For custom MCP servers:
            1. Install dependencies: npm install @modelcontextprotocol/sdk
            2. Implement your tools in index.js
            3. Register in .claude/mcp.json

            Popular MCP servers:
            - @modelcontextprotocol/server-filesystem
            - @modelcontextprotocol/server-github
            - @modelcontextprotocol/server-slack
            """
        )
    }

    // MARK: - Helpers

    private func generateToolsList(_ tools: [String]?) -> String {
        let toolsList = tools ?? ["read_file", "search_code"]
        return toolsList.map { "  - \($0)" }.joined(separator: "\n")
    }
}

// MARK: - Template Types

public struct TemplateOptions: Sendable {
    public let author: String?
    public let tools: [String]?
    public let platform: AIPlatform?

    public init(
        author: String? = nil,
        tools: [String]? = nil,
        platform: AIPlatform? = nil
    ) {
        self.author = author
        self.tools = tools
        self.platform = platform
    }
}

public enum AIPlatform: String, Sendable {
    case claude
    case copilot
}

public struct GeneratedTemplate: Sendable {
    public let type: CustomizationType
    public let name: String
    public let files: [GeneratedFile]
    public let instructions: String
}

public struct GeneratedFile: Sendable {
    public let relativePath: String
    public let content: String
    public let isDirectory: Bool
    public let isExecutable: Bool

    public init(
        relativePath: String,
        content: String,
        isDirectory: Bool = false,
        isExecutable: Bool = false
    ) {
        self.relativePath = relativePath
        self.content = content
        self.isDirectory = isDirectory
        self.isExecutable = isExecutable
    }
}
