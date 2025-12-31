# Changelog

## 0.1.1 - 2025-12-31

- iOS: fix light/dark glass styling and switch to a full-screen login layout.
- iOS: use the modern `UILaunchScreen` plist entry to avoid letterboxed launch.
- Fix CLI: allow invoking bundled `repobarcli` directly (argv0 normalization).
- Fix CLI auth refresh: show actionable error when refresh response is missing tokens.
- Add Settings installer to link `repobar` CLI into common Homebrew paths.
- Limit "More Activity/Commits" submenus to 20 entries.
- Include organization and collaborator repositories in repo lists.
- CLI: add `--owner`/`--mine` filters for repos list.

## 0.1.0 - 2025-12-31

First public release of RepoBar — a macOS menubar dashboard for GitHub repo health, activity, and local project state.

### Highlights
- Live repository cards with CI status, activity, releases, and rate‑limit awareness.
- Rich submenus for recent pull requests, issues, releases, workflow runs, discussions, tags, branches, and commits.
- Local Git state surfaced directly in the menu (branch, upstream/ahead/behind, dirty files, worktrees) with safe actions.
- Contribution heatmap header and global activity feed.
- Fast, native menu UI with adaptive layout and caching for performance.

### Feature overview
- **Menubar experience**
  - Repository cards with stats (stars, forks, issues, last push), CI badge, activity preview, and optional heatmaps.
  - Pinned/hidden repos, menu filters, and configurable sorting.
  - Empty/logged‑out states that explain what to do next.

- **Recent activity & insights**
  - Pull requests, issues, releases, workflow runs, discussions, tags, branches, and commit lists per repo.
  - Global activity menu with recent events and commits.
  - Activity links deep‑link to the most relevant GitHub pages.

- **Local projects & Git actions**
  - Local repo status: current branch, upstream sync, dirty counts, and file lists.
  - Worktree and branch menus with metadata and quick actions.
  - Open in Finder/Terminal, checkout, create branch/worktree, sync/rebase/reset.

- **Auth & API**
  - OAuth login, secure token refresh, and shared core used by the CLI.
  - Rate‑limit awareness and caching to minimize GitHub API usage.

- **Contribution heatmap**
  - Header heatmap (cached) with the ability to refresh and clear cache.
  - Optional menu heatmaps aligned to a week‑based date range.

- **Performance & reliability**
  - Cached repo details, activity, and heatmaps for a snappy menu.
  - Menu layout caching, reuse of menu items, and debounced refresh.
  - Timeouts and graceful fallback for slow network requests.

- **CLI** (`repobar`)
  - Status and repo listings with filters, JSON/plain output, and release info.
  - Commands for issues/pulls lists, pinned/hidden scopes, and activity age filtering.

- **Updates**
  - Sparkle updater for signed builds with update‑ready menu entry and full dialog flow.

- **Developer tooling**
  - SwiftPM + pnpm scripts, lint/format, Apollo GraphQL codegen.
