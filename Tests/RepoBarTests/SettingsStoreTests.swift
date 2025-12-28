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
        settings.repoList.displayLimit = 9
        settings.repoList.pinnedRepositories = ["steipete/RepoBar", "steipete/clawdis"]
        settings.repoList.hiddenRepositories = ["steipete/agent-scripts"]
        settings.enterpriseHost = URL(string: "https://ghe.example.com")!
        settings.debugPaneEnabled = true

        store.save(settings)
        #expect(store.load() == settings)
    }

    @Test
    func migrateLegacyShowHeatmap() throws {
        let suiteName = "repobar.settings.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct LegacyPayload: Codable {
            let showHeatmap: Bool
        }

        let legacy = LegacyPayload(showHeatmap: false)
        let data = try JSONEncoder().encode(legacy)
        defaults.set(data, forKey: SettingsStore.storageKey)

        let store = SettingsStore(defaults: defaults)
        let settings = store.load()
        #expect(settings.heatmap.display == .submenu)
    }

    @Test
    func migrateLegacyEnvelope() throws {
        let suiteName = "repobar.settings.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct LegacyPayload: Codable {
            let showHeatmap: Bool
        }

        struct LegacyEnvelope: Codable {
            let version: Int
            let settings: LegacyPayload
        }

        let legacy = LegacyEnvelope(version: 1, settings: LegacyPayload(showHeatmap: true))
        let data = try JSONEncoder().encode(legacy)
        defaults.set(data, forKey: SettingsStore.storageKey)

        let store = SettingsStore(defaults: defaults)
        let settings = store.load()
        #expect(settings.heatmap.display == .inline)
    }
}
