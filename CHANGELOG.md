# Changelog

## Unreleased

### Added
- RepoBarCore shared module for GitHub API/auth/models used by the app and CLI.
- repobarcli bundled CLI with login/logout/status and repo listing (activity, issues, PRs, stars), JSON output, and limit flag.
- CLI repo listing now filters to the signed-in user and owned orgs (admin membership).
- repobarcli now defaults to 365-day activity filtering and supports `--age` to override.
- repobarcli shows clickable repo links by default (use `--plain` for no links/colors/URLs).
- repobarcli can show latest release tag/date with `--release`.
- repobarcli can fetch contribution heatmaps, refresh pinned repositories, and show repo detail data.
- repobarcli can filter to pinned repos with `--pinned-only`.
- Forked repositories are hidden by default in the mac app and CLI (use `--forks` or enable “Include forked repositories” in Settings).
- Archived repositories are hidden by default in the mac app and CLI (use `--archived` or enable “Include archived repositories” in Settings).
- repobarcli can filter to repos with work using `--only-with work` (or `issues`, `prs`).
- Repo list sorting now uses the same activity/issue/PR/star ordering in the mac app and CLI.
- Clicking a repo card opens the repository in the browser.
- Repo detail cache now persists on disk to survive app restarts.

### Changed
- OAuth/login helpers moved to RepoBarCore so app and CLI share the same keychain flow.
- repobarcli now uses Commander for command parsing and subcommand routing.
- repobarcli debug builds are now codesigned with a stable identifier (no repeated Keychain prompts after rebuilds).
- mac app now caches repo detail fetches for 1 hour to reduce API usage.
- Token refresh now preserves OAuth client credentials and shows a clearer error when refresh fails.
- Menubar repository rows now use tighter, more native spacing with submenu indicators and icons.
- Menubar heatmaps adapt width to the visible span and use a muted palette on highlight.
- Menu filters use compact segmented controls and the update prompt is labeled “Restart to update”.
- Menu filters now sit on a single row and the menu includes an About item.
- Menu filter toggles now refresh the menu immediately.
- Menu bar now uses SwiftUI MenuBarExtra and opens Preferences directly from the menu.
- Empty repo state now explains active filters and keeps filter controls visible.

### Fixed
- mac app no longer crashes on launch due to the hidden keepalive window; Settings opens via AppKit action.
- `pnpm start` now packages and launches a proper `.app` bundle (stable bundle identifier for menubar behavior).
- Contribution heatmap date parsing handles both date-only and ISO8601 timestamps.
- Sparkle updater initialization now defers controller setup until after `super.init`.
