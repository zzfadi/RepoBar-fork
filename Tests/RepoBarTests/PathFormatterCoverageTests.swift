import Foundation
import RepoBarCore
import Testing

struct PathFormatterCoverageTests {
    @Test
    func expandTilde_handlesBareAndSubpaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(PathFormatter.expandTilde("~") == home)
        #expect(PathFormatter.expandTilde("~/tmp").hasPrefix(home + "/"))
    }

    @Test
    func abbreviateHome_fallsBackForNonHomePaths() {
        #expect(PathFormatter.abbreviateHome("/private/tmp") == "/private/tmp")
    }
}

