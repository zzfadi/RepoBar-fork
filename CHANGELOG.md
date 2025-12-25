# Changelog

## Unreleased

### Added
- RepoBarCore shared module for GitHub API/auth/models used by the app and CLI.
- repobarcli bundled CLI with login/logout/status and repo listing (activity, issues, PRs, stars), JSON output, and limit flag.
- CLI repo listing now filters to the signed-in user and owned orgs (admin membership).
- repobarcli now defaults to 365-day activity filtering and supports `--age` to override.
- repobarcli can emit clickable URLs in table output with `--url`.
- Repo list sorting now uses the same activity/issue/PR/star ordering in the mac app and CLI.
- Clicking a repo card opens the repository in the browser.

### Changed
- OAuth/login helpers moved to RepoBarCore so app and CLI share the same keychain flow.
- repobarcli now uses Commander for command parsing and subcommand routing.
