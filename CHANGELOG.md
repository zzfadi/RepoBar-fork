# Changelog

## Unreleased

### Added
- RepoBarCore shared module for GitHub API/auth/models used by the app and CLI.
- repobarcli bundled CLI with login/logout/status and repo listing (activity, issues, PRs, stars), JSON output, and limit flag.
- CLI repo listing now filters to the signed-in user and owned orgs (admin membership).
- repobarcli now defaults to 365-day activity filtering and supports `--age` to override.
- repobarcli shows clickable repo links by default (use `--plain` for no links/colors/URLs).
- repobarcli can show latest release tag/date with `--release`.
- Forked repositories are hidden by default in the mac app and CLI (use `--forks` or enable “Include forked repositories” in Settings).
- Archived repositories are hidden by default in the mac app and CLI (use `--archived` or enable “Include archived repositories” in Settings).
- Repo list sorting now uses the same activity/issue/PR/star ordering in the mac app and CLI.
- Clicking a repo card opens the repository in the browser.
- Repo detail cache now persists on disk to survive app restarts.

### Changed
- OAuth/login helpers moved to RepoBarCore so app and CLI share the same keychain flow.
- repobarcli now uses Commander for command parsing and subcommand routing.
- repobarcli debug builds are now codesigned with a stable identifier (no repeated Keychain prompts after rebuilds).
- mac app now caches repo detail fetches for 1 hour to reduce API usage.
- Token refresh now preserves OAuth client credentials and shows a clearer error when refresh fails.
