import Foundation
@testable import RepoBarCore
import Testing

struct SettingsStoreTests {
    @Test
    func saveAndLoad() throws {
        let suiteName = "repobar.settings.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        #expect(store.load() == UserSettings())

        var settings = UserSettings()
        settings.repoDisplayLimit = 9
        settings.pinnedRepositories = ["steipete/RepoBar", "steipete/clawdis"]
        settings.hiddenRepositories = ["steipete/agent-scripts"]
        settings.enterpriseHost = URL(string: "https://ghe.example.com")!
        settings.debugPaneEnabled = true

        store.save(settings)
        #expect(store.load() == settings)
    }
}
