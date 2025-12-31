# Changelog

## 0.1.2 - 2025-12-31

- Fix menubar menu not reopening after Settings close by rehydrating the main menu on attach.
- CLI: add repo submenu list commands (releases, CI runs, discussions, tags, branches, contributors, commits, activity).
- CLI: add local actions (sync/rebase/reset), local branch/worktree listings, Finder/Terminal open, and checkout.
- CLI: add pin/hide and settings show/set commands; update CLI docs for parity.
- CLI: normalize `local ...`, `open ...`, and `settings ...` subcommands for friendlier usage.
- Add swift-log integration with OSLog + optional file logging sink.
- Add debug logging settings (verbosity + file logging) for macOS and iOS.
- Fix contribution header heatmap sizing on first launch/loading.
- Fix auto-opening settings when tokens already exist.
- iOS: clarify repo detail errors with access/refresh guidance and log error domains/codes.
- iOS: suppress discussions error when the feature is disabled.

## 0.1.1 - 2025-12-31

- Add repo submenu changelog preview (CHANGELOG.md or CHANGELOG) with inline markdown rendering.
- Changelog submenu: move under Open in GitHub, make preview scrollable, and show entry counts since last release.
- Improve menu loading UX (repo loading row, earlier contribution fetch) and restore markdown formatting in changelog preview.
- Fix settings login to use default GitHub credentials when blank, refresh after sign-in, and avoid stuck state.
- Dev: SwiftLint cleanup in changelog loader.
- iOS: fix light/dark glass styling and switch to a full-screen login layout.
- iOS: use the modern `UILaunchScreen` plist entry to avoid letterboxed launch.
- iOS: add a close button to the Settings sheet.
- iOS: switch GitHub auth callback to `https://repobar.app/oauth-callback`.
- Site: add Apple App Site Association for `repobar.app` universal links.
- iOS: add `webcredentials` associated domain for HTTPS auth callbacks.
- iOS: silence AppIntents metadata build warnings.
- iOS: add the RepoBar logo to the login screen and app icon.
- iOS: present the logo in a squircle with more padding on login.
- iOS: add activity/commit icons in the activity list.
- iOS: add a repo detail hierarchy with category drill-down lists.
- iOS: declare iPad orientations to silence Xcode build warnings.
- iOS: show avatars in activity and repo detail lists.
- iOS: soften the glass background to match native palettes.
- iOS: keep file browser navigation within the repo detail stack.
- iOS: improve repo detail error messaging and logging.
- Fix CLI: allow invoking bundled `repobarcli` directly (argv0 normalization).
- Fix CLI auth refresh: show actionable error when refresh response is missing tokens.
- CLI: add markdown rendering command backed by Swiftdansi.
- CLI: add changelog parser command and end-to-end markdown/changelog tests.
- CLI: default changelog command to CHANGELOG files in the repo when no path is provided.
- Add Settings installer to link `repobar` CLI into common Homebrew paths.
- Add Display settings to reorder/hide main menu and repo submenu items (reset to defaults included).
- Make Display reset action destructive and stabilize spacing for rows without subtitles.
- Invalidate menu cache and rebuild if the menu appears too small when opening.
- Add padding between About links and bump settings window height for more breathing room.
- Increase padding between Display list entries.
- Remove pinned repo move up/down commands from repo submenu.
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
