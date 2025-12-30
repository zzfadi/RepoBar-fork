import Foundation

enum AppLimits {
    enum GlobalActivity {
        static let limit: Int = 20
        static let previewLimit: Int = 5
    }

    enum GlobalCommits {
        static let limit: Int = 20
        static let previewLimit: Int = 5
    }

    enum RepoActivity {
        static let limit: Int = 10
        static let previewLimit: Int = 5
    }

    enum RecentLists {
        static let limit: Int = 20
        static let previewLimit: Int = 5
        static let cacheTTL: TimeInterval = 90
        static let loadTimeout: TimeInterval = 12
        static let issueLabelChipLimit: Int = 6
    }

    enum LocalRepo {
        static let mainMenuDirtyFileLimit: Int = 3
        static let submenuDirtyFileLimit: Int = 10
        static let discoveryCacheTTL: TimeInterval = 10 * 60
        static let statusCacheTTL: TimeInterval = 2 * 60
        static let snapshotConcurrencyLimit: Int = 6
    }

    enum Autocomplete {
        static let addRepoRecentLimit: Int = 10
        static let settingsSearchLimit: Int = 8
    }
}
