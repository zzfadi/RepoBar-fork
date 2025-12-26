import Foundation
@testable import RepoBarCore
import Testing

struct RepoDetailCacheStoreTests {
    @Test
    func saveAndLoadRoundTrip() throws {
        let baseURL = FileManager.default.temporaryDirectory.appending(path: "repobar-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let store = RepoDetailCacheStore(fileManager: .default, baseURL: baseURL)
        let apiHost = URL(string: "https://api.github.com")!
        let now = Date(timeIntervalSinceReferenceDate: 123_456)

        let cache = RepoDetailCache(
            openPulls: 7,
            openPullsFetchedAt: now,
            ciDetails: CIStatusDetails(status: .passing, runCount: 42),
            ciFetchedAt: now,
            latestActivity: ActivityEvent(
                title: "Merged PR",
                actor: "alice",
                date: now,
                url: URL(string: "https://example.com/pr/1")!
            ),
            activityFetchedAt: now,
            traffic: TrafficStats(uniqueVisitors: 9, uniqueCloners: 2),
            trafficFetchedAt: now,
            heatmap: [HeatmapCell(date: now, count: 3)],
            heatmapFetchedAt: now,
            latestRelease: Release(name: "v1.0.0", tag: "v1.0.0", publishedAt: now, url: URL(string: "https://example.com/release")!),
            releaseFetchedAt: now
        )

        store.save(cache, apiHost: apiHost, owner: "steipete", name: "RepoBar")
        let loaded = store.load(apiHost: apiHost, owner: "steipete", name: "RepoBar")

        let result = try #require(loaded)
        #expect(result.openPulls == 7)
        #expect(result.ciDetails?.status == .passing)
        #expect(result.latestActivity?.actor == "alice")
        #expect(result.traffic?.uniqueVisitors == 9)
        #expect(result.heatmap?.count == 1)
        #expect(result.latestRelease?.tag == "v1.0.0")
    }

    @Test
    func loadCorruptCacheRemovesFile() throws {
        let baseURL = FileManager.default.temporaryDirectory.appending(path: "repobar-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let store = RepoDetailCacheStore(fileManager: .default, baseURL: baseURL)
        let apiHost = URL(string: "https://api.github.com")!

        let cacheFile = baseURL
            .appending(path: "api.github.com")
            .appending(path: "steipete")
            .appending(path: "RepoBar.json")

        try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cacheFile, options: .atomic)

        #expect(store.load(apiHost: apiHost, owner: "steipete", name: "RepoBar") == nil)
        #expect(FileManager.default.fileExists(atPath: cacheFile.path()) == false)
    }

    @Test
    func clearRemovesCacheDirectory() throws {
        let baseURL = FileManager.default.temporaryDirectory.appending(path: "repobar-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let store = RepoDetailCacheStore(fileManager: .default, baseURL: baseURL)
        let apiHost = URL(string: "https://api.github.com")!

        store.save(RepoDetailCache(), apiHost: apiHost, owner: "steipete", name: "RepoBar")
        #expect(FileManager.default.fileExists(atPath: baseURL.path()))

        store.clear()
        #expect(FileManager.default.fileExists(atPath: baseURL.path()) == false)
    }
}
