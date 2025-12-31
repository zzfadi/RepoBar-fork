import Commander
import Foundation
import RepoBarCore

@main
@MainActor
enum RepoBarCLI {
    static func main() async {
        let argv = CLIArgumentNormalizer.normalize(CommandLine.arguments)
        if let helpTarget = HelpTarget.from(argv: argv) {
            printHelp(helpTarget)
            return
        }

        do {
            let program = Program(descriptors: [RepoBarRoot.descriptor()])
            let invocation = try program.resolve(argv: argv)
            var command = try makeCommand(from: invocation)
            try await command.run()
        } catch {
            self.handleError(error)
        }
    }

    private static func makeCommand(from invocation: CommandInvocation) throws -> any CommanderRunnableCommand {
        guard let name = invocation.path.last else {
            throw CLIError.unknownCommand("repobar")
        }
        guard let type = commandRegistry[name] else {
            throw CLIError.unknownCommand(name)
        }
        var command = type.init()
        try command.bind(invocation.parsedValues)
        return command
    }

    private static let commandRegistry: [String: CommanderRunnableCommand.Type] = [
        ReposCommand.commandName: ReposCommand.self,
        RepoCommand.commandName: RepoCommand.self,
        IssuesCommand.commandName: IssuesCommand.self,
        PullsCommand.commandName: PullsCommand.self,
        LocalProjectsCommand.commandName: LocalProjectsCommand.self,
        RefreshCommand.commandName: RefreshCommand.self,
        ContributionsCommand.commandName: ContributionsCommand.self,
        LoginCommand.commandName: LoginCommand.self,
        LogoutCommand.commandName: LogoutCommand.self,
        StatusCommand.commandName: StatusCommand.self
    ]

    private static func handleError(_ error: Error) {
        let message: String = switch error {
        case let error as CLIError:
            error.message
        case let error as CommanderProgramError:
            error.description
        case let error as ValidationError:
            error.description
        default:
            error.userFacingMessage
        }
        printError(message)
        exit(1)
    }
}
