# Changelog

## Unreleased

### Added
- RepoBarCore shared module for GitHub API/auth/models used by the app and CLI.
- repobar bundled CLI with login/logout/status and repo listing (activity, issues, PRs, stars), JSON output, and limit flag.
- repobar CLI now supports `issues` and `pulls` to list the 20 most recently updated open items for a repository.
- CLI repo listing now filters to the signed-in user and owned orgs (admin membership).
- repobar now defaults to 365-day activity filtering and supports `--age` to override.
- repobar shows clickable repo links by default (use `--plain` for no links/colors/URLs).
- repobar can show latest release tag/date with `--release`.
- repobar can fetch contribution heatmaps, refresh pinned repositories, and show repo detail data.
- repobar can filter to pinned repos with `--pinned-only`.
- repobar repo listing now supports `--scope` (all/pinned/hidden) and `--filter` (all/work/issues/prs).
- Forked repositories are hidden by default in the mac app and CLI (use `--forks` or enable “Include forked repositories” in Settings).
- Archived repositories are hidden by default in the mac app and CLI (use `--archived` or enable “Include archived repositories” in Settings).
- repobar can filter to repos with work using `--only-with work` (or `issues`, `prs`).
- Repo list sorting now uses the same activity/issue/PR/star ordering in the mac app and CLI.
- Clicking a repo card opens the repository in the browser.
- Repo detail cache now persists on disk to survive app restarts.
- Repo display limit options expanded to 3/6/9/12 (default 6).

### Changed
- OAuth/login helpers moved to RepoBarCore so app and CLI share the same keychain flow.
- repobar now uses Commander for command parsing and subcommand routing.
- repobar debug builds are now codesigned with a stable identifier (no repeated Keychain prompts after rebuilds).
- repobar CLI now installs as `repobar` (with `repobarcli` alias via pnpm).
- mac app now caches repo detail fetches for 1 hour to reduce API usage.
- Token refresh now preserves OAuth client credentials and shows a clearer error when refresh fails.
- Menubar repository rows now use tighter, more native spacing with submenu indicators and icons.
- Menubar repository cards now include more breathing room between entries.
- Menubar heatmaps adapt width to the visible span and use a muted palette on highlight.
- Menu filters use compact segmented controls and the update prompt is labeled “Restart to update”.
- Menu filters now sit on a single row and the menu includes an About item.
- Menu filter toggles now refresh the menu immediately.
- Menu bar now uses MenuBarExtraAccess with an AppKit NSMenu for native layout while still opening Preferences directly from the menu.
- Empty repo state now explains active filters and keeps filter controls visible.
- SwiftUI and app models now use `@Observable`/`@Bindable` for state updates.
- Menu sort order is now configurable in the menu and saved in Settings.
- Accounts settings pane now uses grouped styling, labeled fields, and a compact signed-in status block.
- Settings window height increased; Quit button now uses standard styling.
- Repo menu headers now combine CI dot, repository name, and release/time on a single row.
- Repo menu stat row now includes stars and forks for quick popularity context.
- Repo menu stat row now includes last push age.
- Repo submenus now list remaining repository details like CI run count and traffic stats when available.
- Repo submenus now include an “Open Activity” link and a single Activity list (up to 10 items) with quick links.
- Repo submenus now include nested lists for Issues and Pull Requests (20 most recently updated open items).
- Repo recent item submenus now prefetch and reuse cached results to avoid showing a loading state.
- Repo submenus now show item count badges for nested Issues/PRs/Releases.
- Activity event links now deep-link to stars, releases, forks, and commits when available.
- Recent activity now includes action/number labels, repo targets, and avatar icons.
- Activity row now shows the latest activity timestamp aligned to the right.
- Contribution and repository heatmaps now align to the same week-based date range.
- Inline heatmaps now include the date range axis labels.
- Heatmap rendering now uses cached CoreGraphics rasterization for faster menu redraws.
- Heatmaps now stretch to the full available menu width (respecting existing card padding).
- `pnpm restart` now rebuilds and relaunches without running tests; use `pnpm test` for tests and `pnpm check:coverage` for coverage.
- `repobar local --sync` now shows a per-repo SYNC column and includes a `synced` flag in JSON output.

### Fixed
- Settings now open via SwiftUI `openSettings` from the MenuBarExtra.
- `pnpm start` now packages and launches a proper `.app` bundle (stable bundle identifier for menubar behavior).
- Contribution heatmap date parsing handles both date-only and ISO8601 timestamps.
- Sparkle updater initialization now defers controller setup until after `super.init`.
- Activity labels now use readable event names and prefer issue/PR titles over raw event types.
- Menu no longer preselects the first item on open.
- Fixed a crash when opening menus with the raster heatmap renderer.
- Menu item hosting now opts into modern sizing behavior to avoid clipped content.
- Heatmaps now pixel-align to avoid uneven left/right padding in the menu.
- Heatmaps now fill the full menu row width (reclaim submenu chevron padding).
- Local projects branch detection now uses the first available git binary on PATH/Homebrew to avoid “unknown.”
- Local projects scanning now correctly traverses security-scoped folder bookmarks resolved to file reference URLs.
- CI status dots now increase contrast on highlighted menu rows.
- GitHub “stats still generating” (HTTP 202) no longer clutters the main repo list and is now shown in repo details instead.
- Fixed CLI/app binary naming collisions on case-insensitive filesystems (CLI builds as `repobarcli` and is embedded as `repobarcli` in the app bundle).
