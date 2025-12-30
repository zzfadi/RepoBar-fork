---
summary: "RepoBar refactor opportunities checklist."
read_when:
  - Reviewing structural refactors or long-term cleanup ideas
---

# Refactor Opportunities

Last updated: 2025-12-28

## Goals
- Reduce drift between menu and CLI behavior.
- Make menu rendering deterministic and testable.
- Isolate data fetching, filtering, sorting, and hydration.
- Keep UI tweaks localized and consistent.
- Improve cache story (repo details, heatmaps, avatars).

## High-Impact Opportunities

### [x] 1) Unify data pipeline (menu + CLI)
- Create a shared pipeline: fetch -> filter -> sort -> hydrate -> limit.
- Single `RepositoryQuery` or `RepositoryPipeline` with config flags:
  - scope (all/pinned/hidden)
  - onlyWith (none/work/issues/prs)
  - includeForks/includeArchived
  - sortKey
  - limit
  - age cutoff (optional)
- Use same filter logic for menu and CLI to avoid mismatches.
- Add unit tests for pipeline with fixtures.

### [x] 2) Split AppState refresh into stages
- `fetchActivityRepos()`
- `applyVisibilityFilters()`
- `applyPinnedOrder()`
- `selectMenuTargets()`
- `hydrateMenuTargets()`
- `mergeHydrated()`
- `applyLimits()`
- `updateSession()`

### [x] 3) Menu building refactor
- Split `StatusBarMenuManager` into:
  - `MenuBuilder` (pure structure)
  - `MenuViewHost` (NSMenu + NSHostingView)
  - `MenuActions` (open/pin/hide/etc)
- Introduce `MenuSection` definitions (header, filters, repo list, footer).
- Centralize submenu structure and ordering rules.

### [x] 4) Repository view models
- Introduce `RepositoryDisplayModel` with precomputed strings, ages, labels.
- Keep logic out of SwiftUI views.
- Compute `activityLine`, `statsLine`, `releaseLine` once.

## Cache + Networking

### [x] 5) Repo detail cache API
- Wrap cache reads/writes behind `RepoDetailStore` interface.
- Define cache freshness with explicit TTLs and stale flags.
- Expose cache state to UI (stale vs fresh).

### [x] 6) Request coordination
- Add fetch coalescing to prevent duplicate requests per repo.
- Cancel previous refresh tasks on new menu open.
- Rate-limit hydration fan-out (TaskGroup with max concurrency).

### [x] 7) Heatmap alignment consistency
- Move heatmap filtering and range alignment into a shared helper.
- Store `HeatmapRange` in session state so header + repo heatmaps align.

## Settings + Config

### [x] 8) Settings migration
- Add versioned migrations for `UserSettings`.
- Example: `showHeatmap -> heatmapDisplay` mapping.

### [x] 9) Typed settings groups
- Split into structs:
  - `HeatmapSettings`
  - `RepoListSettings`
  - `AppearanceSettings`
- Reduce SettingsView boilerplate.

## UI Consistency

### [x] 10) Menu style system
- `MenuStyle` for fonts, spacing, colors, insets.
- Avoid scattered padding tweaks in view code.

### [x] 11) Heatmap rendering consistency
- Single `HeatmapLayout` utility for spacing + inset rules.
- Reuse for header, repo cards, submenu heatmaps.

### [x] 12) Highlight + focus handling
- Centralize highlight styling and focus ring suppression.
- Ensure focus behavior is consistent across NSMenu and SwiftUI items.

## Models + Types

### [x] 13) Event type enums
- Replace string checks for GitHub event types with enum.
- Stronger mapping for icons and labels.
- Easier to add new event types later.

### [x] 14) Activity metadata model
- Add `ActivityMetadata` (actor, action, target, url).
- Derived fields for label + deep link.

### [x] 15) Repo stats value type
- Create `RepositoryStats` to hold issues/PRs/stars/forks/push age.
- Used by both CLI and UI.

## CLI + Menu Parity

### [x] 16) Align filters and defaults
- CLI has age cutoff; menu does not. Decide on common default.
- `onlyWith` filter should behave identically in menu and CLI.

### [x] 17) Shared formatters
- Shared formatting for:
  - ages and time labels
  - event labels
  - release labels

## Testing

### [x] 18) Pipeline tests
- Filter logic (pinned vs hidden, include forks/archived).
- Sort order (activity, issues, PRs, stars).
- onlyWith (work/issues/prs) behavior.

### [x] 19) UI logic tests
- Heatmap range alignment for header + repo.
- Menu selection with pinned + filters.

### [x] 20) Fixtures + regression
- Add fixtures for event mapping (PR merged, release tag, fork).
- Use CLI fixtures for menu parity.

## Performance

### [x] 21) Preload strategy
- Cache last menu snapshot and reuse on reopen.
- Only refresh in background if stale.

### [x] 22) Lazy hydration
- Hydrate only visible rows, then opportunistically hydrate next page.

## Incremental Plan Ideas
- Phase 1: extract menu selection + sorting pipeline + tests.
- Phase 2: split menu builder / actions.
- Phase 3: cache and network coordination.
- Phase 4: settings migration + UI style system.

## Submenu Refactor Checklist (2025-12-30)
- [x] Create a `RecentMenuDescriptor` table to drive submenu config, caching, fetching, and row rendering (remove per-kind switch blocks).
- [x] Extract a shared SwiftUI row layout for recent submenu items (issues/PRs/releases/CI/discussions/tags/branches/contributors/assets).
- [x] Add a GitHubClient helper for recent-list REST calls + decoding to reduce endpoint boilerplate.
- [x] Centralize repo web URL building (actions/discussions/tags/branches/contributors/releases/assets).
- [x] Reuse a single list-submenu builder for releases + release assets + recent list menus.
