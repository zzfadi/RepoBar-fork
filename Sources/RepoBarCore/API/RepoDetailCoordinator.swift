import Foundation

final class RepoDetailCoordinator {
    private var store: RepoDetailStore
    private let policy: RepoDetailCachePolicy
    private let restAPI: GitHubRestAPI

    init(
        restAPI: GitHubRestAPI,
        policy: RepoDetailCachePolicy,
        store: RepoDetailStore = RepoDetailStore()
    ) {
        self.restAPI = restAPI
        self.policy = policy
        self.store = store
    }

    func fullRepository(owner: String, name: String) async throws -> Repository {
        var accumulator = RepoErrorAccumulator()

        let details: RepoItem
        do {
            details = try await self.restAPI.repoDetails(owner: owner, name: name)
        } catch {
            accumulator.absorb(error)
            return Repository.placeholder(
                owner: owner,
                name: name,
                error: accumulator.message,
                rateLimitedUntil: accumulator.rateLimit
            )
        }

        let now = Date()
        let resolvedOwner = details.owner.login
        let resolvedName = details.name
        var cache = self.store.load(apiHost: self.restAPI.apiHost(), owner: resolvedOwner, name: resolvedName)
        let cacheState = self.policy.state(for: cache, now: now)
        let cachedOpenPulls = cache.openPulls ?? 0
        let cachedCiDetails = cache.ciDetails ?? CIStatusDetails(status: .unknown, runCount: nil)
        let cachedActivity = cache.latestActivity
        let cachedActivityEvents = cache.activityEvents ?? []
        let cachedTraffic = cache.traffic
        let cachedHeatmap = cache.heatmap ?? []
        let cachedRelease = cache.latestRelease

        let shouldFetchPulls = cacheState.openPulls.needsRefresh
        let shouldFetchCI = cacheState.ci.needsRefresh
        let shouldFetchActivity = cacheState.activity.needsRefresh
        let shouldFetchTraffic = cacheState.traffic.needsRefresh
        let shouldFetchHeatmap = cacheState.heatmap.needsRefresh
        let shouldFetchRelease = cacheState.release.needsRefresh
        var didUpdateCache = false

        // Run all expensive lookups in parallel; individual failures are folded into the accumulator.
        async let openPullsResult: Result<Int, Error> = shouldFetchPulls
            ? self.capture { try await self.restAPI.openPullRequestCount(owner: resolvedOwner, name: resolvedName) }
            : .success(cachedOpenPulls)
        async let ciResult: Result<CIStatusDetails, Error> = shouldFetchCI
            ? self.capture { try await self.restAPI.ciStatus(owner: resolvedOwner, name: resolvedName) }
            : .success(cachedCiDetails)
        async let activityResult: Result<ActivitySnapshot, Error> = shouldFetchActivity
            ? self.capture { try await self.restAPI.recentActivity(owner: resolvedOwner, name: resolvedName, limit: 10) }
            : .success(ActivitySnapshot(events: cachedActivityEvents, latest: cachedActivity))
        async let trafficResult: Result<TrafficStats?, Error> = shouldFetchTraffic
            ? self.capture { try await self.restAPI.trafficStats(owner: resolvedOwner, name: resolvedName) }
            : .success(cachedTraffic)
        async let heatmapResult: Result<[HeatmapCell], Error> = shouldFetchHeatmap
            ? self.capture { try await self.restAPI.commitHeatmap(owner: resolvedOwner, name: resolvedName) }
            : .success(cachedHeatmap)
        async let releaseResult: Result<Release?, Error> = shouldFetchRelease
            ? self.capture { try await self.restAPI.latestReleaseAny(owner: resolvedOwner, name: resolvedName) }
            : .success(cachedRelease)

        let openPulls: Int
        switch await openPullsResult {
        case let .success(value):
            openPulls = value
            if shouldFetchPulls {
                cache.openPulls = value
                cache.openPullsFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            openPulls = cache.openPulls ?? 0
        }
        let issues = max(details.openIssuesCount - openPulls, 0)

        let ciDetails: CIStatusDetails?
        switch await ciResult {
        case let .success(value):
            ciDetails = value
            if shouldFetchCI {
                cache.ciDetails = value
                cache.ciFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            ciDetails = cache.ciDetails
        }
        let ci = ciDetails?.status ?? .unknown
        let ciRunCount = ciDetails?.runCount

        let activity: ActivityEvent?
        let activityEvents: [ActivityEvent]
        switch await activityResult {
        case let .success(snapshot):
            activity = snapshot.latest ?? snapshot.events.first
            activityEvents = snapshot.events
            if shouldFetchActivity {
                cache.latestActivity = activity
                cache.activityEvents = snapshot.events
                cache.activityFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            activity = cache.latestActivity
            activityEvents = cache.activityEvents ?? []
        }

        let traffic: TrafficStats?
        switch await trafficResult {
        case let .success(value):
            traffic = value
            if shouldFetchTraffic {
                cache.traffic = value
                cache.trafficFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            traffic = cache.traffic
        }

        let heatmap: [HeatmapCell]
        switch await heatmapResult {
        case let .success(value):
            heatmap = value
            if shouldFetchHeatmap {
                cache.heatmap = value
                cache.heatmapFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            heatmap = cache.heatmap ?? []
        }

        let releaseREST: Release?
        switch await releaseResult {
        case let .success(value):
            releaseREST = value
            if shouldFetchRelease {
                cache.latestRelease = value
                cache.releaseFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            releaseREST = cache.latestRelease
        }

        let finalCacheState = self.policy.state(for: cache, now: now)
        if didUpdateCache {
            self.store.save(cache, apiHost: self.restAPI.apiHost(), owner: resolvedOwner, name: resolvedName)
        }

        return Repository.from(
            item: details,
            openPulls: openPulls,
            issues: issues,
            ciStatus: ci,
            ciRunCount: ciRunCount,
            latestRelease: releaseREST,
            latestActivity: activity,
            activityEvents: activityEvents,
            traffic: traffic,
            heatmap: heatmap,
            error: accumulator.message,
            rateLimitedUntil: accumulator.rateLimit,
            detailCacheState: finalCacheState
        )
    }

    func clearCache() {
        self.store.clear()
    }

    private func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return try await .success(work()) } catch { return .failure(error) }
    }
}
