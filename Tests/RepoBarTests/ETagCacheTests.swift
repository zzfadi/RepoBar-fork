import Foundation
@testable import RepoBarCore
import Testing

struct ETagCacheTests {
    @Test
    func saveAndRetrieve() async {
        let cache = ETagCache()
        let url = URL(string: "https://example.com/a")!

        await cache.save(url: url, etag: nil, data: Data("x".utf8))
        #expect(await cache.count() == 0)

        await cache.save(url: url, etag: "etag-1", data: Data("payload".utf8))
        #expect(await cache.count() == 1)

        let hit = await cache.cached(for: url)
        #expect(hit?.etag == "etag-1")
        #expect(hit?.data == Data("payload".utf8))
    }

    @Test
    func rateLimitExpiresAndClears() async {
        let cache = ETagCache()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let until = now.addingTimeInterval(10)

        await cache.setRateLimitReset(date: until)
        #expect(await cache.isRateLimited(now: now))

        #expect(await cache.isRateLimited(now: now.addingTimeInterval(11)) == false)
        #expect(await cache.rateLimitUntil(now: now.addingTimeInterval(11)) == nil)
    }

    @Test
    func clearDropsEntriesAndRateLimit() async {
        let cache = ETagCache()
        let url = URL(string: "https://example.com/a")!
        await cache.save(url: url, etag: "etag-1", data: Data("payload".utf8))
        await cache.setRateLimitReset(date: Date().addingTimeInterval(60))

        await cache.clear()
        #expect(await cache.count() == 0)
        #expect(await cache.isRateLimited() == false)
    }
}
