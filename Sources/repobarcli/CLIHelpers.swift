import Commander
import Darwin
import Foundation
import RepoBarCore

protocol CommanderRunnableCommand: ParsableCommand {
    static var commandName: String { get }
    mutating func bind(_ values: ParsedValues) throws
}

extension ParsableCommand {
    static func descriptor() -> CommandDescriptor {
        let description = Self.commandDescription
        let instance = Self()
        let signature = CommandSignature.describe(instance).flattened()
        let name = description.commandName ?? String(describing: Self.self).lowercased()
        let subcommands = description.subcommands.map { $0.descriptor() }
        let defaultName = description.defaultSubcommand?.commandDescription.commandName
            ?? description.defaultSubcommand.map { String(describing: $0).lowercased() }
        return CommandDescriptor(
            name: name,
            abstract: description.abstract,
            discussion: description.discussion,
            signature: signature,
            subcommands: subcommands,
            defaultSubcommandName: defaultName
        )
    }
}

extension ParsedValues {
    func flag(_ label: String) -> Bool {
        flags.contains(label)
    }

    func decodeOption<T: ExpressibleFromArgument>(_ label: String) throws -> T? {
        guard let raw = options[label]?.last else { return nil }
        guard let value = T(argument: raw) else {
            throw ValidationError("Invalid value for --\(label): \(raw)")
        }
        return value
    }
}

struct OutputOptions: CommanderParsable, Sendable {
    @Flag(
        names: [.customLong("json"), .customLong("json-output"), .short("j")],
        help: "Output JSON instead of the formatted table"
    )
    var jsonOutput: Bool = false

    @Flag(names: [.customLong("no-color")], help: "Disable color output")
    var noColor: Bool = false

    init() {}

    mutating func bind(_ values: ParsedValues) {
        self.jsonOutput = values.flag("jsonOutput")
        self.noColor = values.flag("noColor")
    }

    var useColor: Bool {
        self.jsonOutput == false && self.noColor == false && Ansi.supportsColor
    }
}

extension RepositorySortKey: ExpressibleFromArgument {
    public init?(argument: String) {
        switch argument.lowercased() {
        case "activity", "act", "date":
            self = .activity
        case "issues", "issue", "iss":
            self = .issues
        case "prs", "pr", "pulls", "pull":
            self = .pulls
        case "stars", "star":
            self = .stars
        case "repo", "name":
            self = .name
        case "event", "activity-line", "line":
            self = .event
        default:
            return nil
        }
    }
}

enum CLIError: Error {
    case notAuthenticated
    case openFailed
    case unknownCommand(String)

    var message: String {
        switch self {
        case .notAuthenticated:
            "No stored login. Run `repobarcli login` first."
        case .openFailed:
            "Failed to open the browser."
        case let .unknownCommand(command):
            "Unknown command: \(command)"
        }
    }
}

enum Ansi {
    static let reset = "\u{001B}[0m"
    static let bold = Code("\u{001B}[1m")
    static let red = Code("\u{001B}[31m")
    static let yellow = Code("\u{001B}[33m")
    static let magenta = Code("\u{001B}[35m")
    static let cyan = Code("\u{001B}[36m")
    static let gray = Code("\u{001B}[90m")
    static let oscTerminator = "\u{001B}\\"

    static var supportsColor: Bool {
        guard isatty(fileno(stdout)) != 0 else { return false }
        return ProcessInfo.processInfo.environment["NO_COLOR"] == nil
    }

    static var supportsLinks: Bool {
        isatty(fileno(stdout)) != 0
    }

    struct Code {
        let value: String

        init(_ value: String) {
            self.value = value
        }

        func wrap(_ text: String) -> String {
            "\(self.value)\(text)\(Ansi.reset)"
        }
    }

    static func link(_ label: String, url: URL, enabled: Bool) -> String {
        guard enabled else { return "\(label) \(url.absoluteString)" }
        let start = "\u{001B}]8;;\(url.absoluteString)\(Ansi.oscTerminator)"
        let end = "\u{001B}]8;;\(Ansi.oscTerminator)"
        return "\(start)\(label)\(end)"
    }
}

extension String {
    var singleLine: String {
        let noNewlines = self.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .joined(separator: " ")
        return noNewlines.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

func printError(_ message: String) {
    if Ansi.supportsColor {
        print(Ansi.red.wrap("Error: \(message)"))
    } else {
        print("Error: \(message)")
    }
}

func openURL(_ url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.absoluteString]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CLIError.openFailed }
}

func parseHost(_ raw: String) throws -> URL {
    guard var components = URLComponents(string: raw) else {
        throw ValidationError("Invalid host: \(raw)")
    }
    if components.scheme == nil { components.scheme = "https" }
    guard let url = components.url else {
        throw ValidationError("Invalid host: \(raw)")
    }
    return url
}

enum HelpTarget: String {
    case root
    case repos
    case login
    case logout
    case status

    static func from(argv: [String]) -> HelpTarget? {
        guard !argv.isEmpty else { return .root }

        if argv.count > 1, argv[1] == "help" {
            let target = argv.dropFirst(2).first
            return HelpTarget.from(token: target)
        }

        guard argv.contains("--help") || argv.contains("-h") else { return nil }
        let target = argv.dropFirst().first(where: { !$0.hasPrefix("-") })
        return HelpTarget.from(token: target)
    }

    private static func from(token: String?) -> HelpTarget {
        guard let token else { return .root }
        switch token {
        case ReposCommand.commandName:
            return .repos
        case LoginCommand.commandName:
            return .login
        case LogoutCommand.commandName:
            return .logout
        case StatusCommand.commandName:
            return .status
        default:
            return .root
        }
    }
}

func printHelp(_ target: HelpTarget) {
    let text = switch target {
    case .root:
        """
        repobarcli - list repositories by activity, issues, PRs, stars

        Usage:
          repobarcli [repos] [--limit N] [--age DAYS] [--url] [--json] [--sort KEY]
          repobarcli login [--host URL] [--client-id ID] [--client-secret SECRET] [--loopback-port PORT]
          repobarcli logout
          repobarcli status [--json]

        Options:
          --limit N    Max repositories to fetch (default: all accessible)
          --age DAYS   Only show repos with activity in the last N days (default: 365)
          --url        Include clickable URLs in output
          --json       Output JSON instead of formatted table
          --sort KEY   Sort by activity, issues, prs, stars, repo, or event
          --no-color   Disable color output
          -h, --help   Show help
        """
    case .repos:
        """
        repobarcli repos - list repositories

        Usage:
          repobarcli repos [--limit N] [--age DAYS] [--url] [--json] [--sort KEY]

        Options:
          --limit N    Max repositories to fetch (default: all accessible)
          --age DAYS   Only show repos with activity in the last N days (default: 365)
          --url        Include clickable URLs in output
          --json       Output JSON instead of formatted table
          --sort KEY   Sort by activity, issues, prs, stars, repo, or event
          --no-color   Disable color output
        """
    case .login:
        """
        repobarcli login - sign in via browser OAuth

        Usage:
          repobarcli login [--host URL] [--client-id ID] [--client-secret SECRET] [--loopback-port PORT]
        """
    case .logout:
        """
        repobarcli logout - clear stored credentials

        Usage:
          repobarcli logout
        """
    case .status:
        """
        repobarcli status - show login state

        Usage:
          repobarcli status [--json]
        """
    }
    print(text)
}
