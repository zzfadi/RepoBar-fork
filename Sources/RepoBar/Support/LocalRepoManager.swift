import Foundation
import RepoBarCore

actor LocalRepoManager {
    private let notifier = LocalSyncNotifier.shared
    private let discoveryCacheTTL: TimeInterval = 10 * 60
    private let statusCacheTTL: TimeInterval = 2 * 60
    private var discoveryCache: [String: DiscoveryCacheEntry] = [:]
    private var statusCache: [String: StatusCacheEntry] = [:]

    struct SnapshotResult: Sendable {
        let discoveredCount: Int
        let repoIndex: LocalRepoIndex
        let accessDenied: Bool
    }

    func snapshot(
        rootPath: String?,
        rootBookmarkData: Data?,
        autoSyncEnabled: Bool,
        matchRepoNames: Set<String>,
        forceRescan: Bool
    ) async -> SnapshotResult {
        guard let rootPath,
              rootPath.isEmpty == false
        else {
            return SnapshotResult(discoveredCount: 0, repoIndex: .empty, accessDenied: false)
        }

        let now = Date()

        let fallbackURL = URL(fileURLWithPath: PathFormatter.expandTilde(rootPath), isDirectory: true)
        let resolvedBookmark = rootBookmarkData.flatMap(SecurityScopedBookmark.resolve)
        let scopedURL = resolvedBookmark ?? fallbackURL

        let didStart = scopedURL.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                scopedURL.stopAccessingSecurityScopedResource()
            }
        }

        if rootBookmarkData != nil, resolvedBookmark == nil || didStart == false {
            return SnapshotResult(discoveredCount: 0, repoIndex: .empty, accessDenied: true)
        }

        // Security-scoped bookmarks can resolve to file reference URLs (`/.file/id=…`).
        // FileManager APIs expect a path-based file URL for traversal.
        let rootURL = (scopedURL as NSURL).filePathURL ?? scopedURL
        let resolvedRoot = rootURL.resolvingSymlinksInPath().path

        let repoRoots = self.discoverRepoRoots(
            rootURL: rootURL,
            resolvedRoot: resolvedRoot,
            now: now,
            forceRescan: forceRescan
        )

        let (cachedStatuses, refreshRoots) = self.partitionStatusesToRefresh(
            repoRoots: repoRoots,
            matchRepoNames: matchRepoNames,
            now: now,
            forceRefresh: forceRescan,
            autoSyncEnabled: autoSyncEnabled
        )

        let refreshedSnapshot = await LocalProjectsService().snapshot(
            repoRoots: refreshRoots,
            autoSyncEnabled: autoSyncEnabled,
            includeOnlyRepoNames: nil,
            concurrencyLimit: 6
        )

        for status in refreshedSnapshot.statuses {
            self.statusCache[status.path.path] = StatusCacheEntry(status: status, updatedAt: now)
        }

        for status in refreshedSnapshot.syncedStatuses {
            await self.notifier.notifySync(for: status)
        }

        let allStatuses = cachedStatuses + refreshedSnapshot.statuses
        return SnapshotResult(
            discoveredCount: repoRoots.count,
            repoIndex: LocalRepoIndex(statuses: allStatuses),
            accessDenied: false
        )
    }

    private struct DiscoveryCacheEntry {
        let repoRoots: [URL]
        let discoveredAt: Date
    }

    private struct StatusCacheEntry {
        let status: LocalRepoStatus
        let updatedAt: Date
    }

    private func discoverRepoRoots(
        rootURL: URL,
        resolvedRoot: String,
        now: Date,
        forceRescan: Bool
    ) -> [URL] {
        if forceRescan == false,
           let cached = self.discoveryCache[resolvedRoot],
           now.timeIntervalSince(cached.discoveredAt) < self.discoveryCacheTTL {
            return cached.repoRoots
        }

        let roots = LocalProjectsService().discoverRepoRoots(rootURL: rootURL, maxDepth: 2)
        self.discoveryCache[resolvedRoot] = DiscoveryCacheEntry(repoRoots: roots, discoveredAt: now)
        return roots
    }

    private func partitionStatusesToRefresh(
        repoRoots: [URL],
        matchRepoNames: Set<String>,
        now: Date,
        forceRefresh: Bool,
        autoSyncEnabled: Bool
    ) -> (cached: [LocalRepoStatus], refresh: [URL]) {
        guard repoRoots.isEmpty == false else { return ([], []) }

        let interesting: [URL] = if matchRepoNames.isEmpty {
            []
        } else {
            repoRoots.filter { matchRepoNames.contains($0.lastPathComponent) }
        }

        var cached: [LocalRepoStatus] = []
        var refresh: [URL] = []
        cached.reserveCapacity(interesting.count)
        refresh.reserveCapacity(interesting.count)

        for repoURL in interesting {
            let key = repoURL.path
            guard let entry = self.statusCache[key] else {
                refresh.append(repoURL)
                continue
            }

            if forceRefresh {
                refresh.append(repoURL)
                continue
            }

            if autoSyncEnabled, entry.status.canAutoSync {
                refresh.append(repoURL)
                continue
            }

            if now.timeIntervalSince(entry.updatedAt) < self.statusCacheTTL {
                cached.append(entry.status)
            } else {
                refresh.append(repoURL)
            }
        }

        return (cached, refresh)
    }
}
