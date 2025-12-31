@testable import repobarcli
import RepoBarCore
import Testing

struct CLIArgumentNormalizerTests {
    @Test
    func normalizesBinaryNameToRepobar() {
        let argv = CLIArgumentNormalizer.normalize(["/Applications/RepoBar.app/Contents/MacOS/repobarcli", "status"])
        #expect(argv.first == RepoBarRoot.commandName)
        #expect(argv.dropFirst().first == "status")
    }

    @Test
    func normalizesLegacyAliases() {
        #expect(CLIArgumentNormalizer.normalize(["repobar", "list"]).dropFirst().first == "repos")
        #expect(CLIArgumentNormalizer.normalize(["repobar", "pr"]).dropFirst().first == "pulls")
        #expect(CLIArgumentNormalizer.normalize(["repobar", "prs"]).dropFirst().first == "pulls")
    }
}
