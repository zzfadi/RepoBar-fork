import Foundation
import RepoBarCore

enum CLIArgumentNormalizer {
    static func normalize(_ args: [String]) -> [String] {
        guard !args.isEmpty else { return [RepoBarRoot.commandName] }

        var normalized = args
        let invokedName = URL(fileURLWithPath: args[0]).lastPathComponent

        // Commander expects argv[0] to be the command name used in help/usage. Our binary name can vary
        // (e.g. `repobarcli` when bundled inside the app), but the public interface stays `repobar`.
        if invokedName != RepoBarRoot.commandName {
            normalized[0] = RepoBarRoot.commandName
        } else {
            normalized[0] = invokedName
        }

        if normalized.count > 1, normalized[1] == "list" {
            normalized[1] = "repos"
        }
        if normalized.count > 1, ["pr", "prs"].contains(normalized[1]) {
            normalized[1] = "pulls"
        }

        return normalized
    }
}
