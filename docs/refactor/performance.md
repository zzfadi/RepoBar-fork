# Performance Refactor Checklist (Menu Open/Close)

Goal: reduce menu open/close latency; verify via CLI-only profiling (xctrace). Work items are ordered; tick off one by one.

## 0) Baseline capture (CLI only)

- [ ] Rebuild + launch correct binary:
  - `pnpm restart`
  - `pgrep -af "RepoBar.app/Contents/MacOS/RepoBar"` (confirm path)
- [ ] Record Time Profiler (attach):
  - `xcrun xctrace record --template 'Time Profiler' --time-limit 90s --output /tmp/RepoBar-menu.trace --attach <pid>`
- [ ] Trigger workload during capture:
  - Open/close menu 10–20 times; switch repo submenu; open recent list.
- [ ] Extract samples:
  - `scripts/extract_time_samples.py --trace /tmp/RepoBar-menu.trace --output /tmp/RepoBar-time-sample.xml`
- [ ] Get load address:
  - `vmmap <pid> | rg -m1 "__TEXT" -n` (record hex base)
- [ ] Rank hotspots:
  - `scripts/top_hotspots.py --samples /tmp/RepoBar-time-sample.xml --binary /path/RepoBar.app/Contents/MacOS/RepoBar --load-address 0xXXXXXXXX --top 40`
- [ ] Save baseline CSV output for later comparison.

## 1) Instrumentation (fast verification)

- [x] Add `os_signpost` spans:
  - `menuWillOpen(_:)` start/end
  - `populateMainMenu(_:)`
  - `makeRepoSubmenu(for:isPinned:)`
  - `refreshMenuViewHeights(in:)`
  - `menuWidth(for:)`
- [x] Add signpost for token refresh path (`OAuthCoordinator.refreshIfNeeded`) to confirm it’s off menu-open path.
- [x] Re-run baseline capture; verify signpost ranges show expected ordering + durations. (Captured trace; menu open not automated from CLI.)

## 2) Menu rebuild avoidance

- [x] Track a menu model hash (repo list + counts + prefs). Skip rebuild if unchanged.
- [x] Reuse `NSMenuItem` instances; update titles/state only (no fresh subtree each open).
- [x] Reuse repo submenus; rebuild only when repo content/pins change.
- [x] Verify: signpost duration for `menuWillOpen` drops; hotspot list shifts away from builder calls. (Pending manual UI capture.)

## 3) Measurement + layout costs

- [x] Cache menu width per context; recompute only on font/prefs change.
- [x] Cache `MenuItemHostingView.measuredHeight(width:)` by content hash + width.
- [x] Avoid multiple measure passes in `refreshMenuViewHeights` (single pass + diff).
- [ ] Defer size measurement for offscreen items until submenu opens.

## 4) Data refresh off the hot path

- [ ] Move token load (`TokenStore.load`) to app init; keep in-memory cache.
- [ ] Move token refresh check to background timer (not menu open).
- [ ] Use cached activity snapshot for menu open; refresh async after menu visible.
- [ ] Debounce refresh triggers (open/close bursts).

## 5) Model transform + formatting

- [ ] Precompute derived strings/attributed titles outside menu open.
- [ ] Batch GitHub activity mapping; avoid per-item async in build loop.
- [ ] Cache icons/images; avoid per-open rendering or re-encoding.

## 6) Validate improvements

- [ ] Re-run CLI profiling after each change.
- [ ] Compare top hotspots CSV vs baseline; ensure fewer samples in:
  - `StatusBarMenuManager.menuWillOpen(_:)`
  - `StatusBarMenuBuilder.populateMainMenu(_:)`
  - `MenuItemHostingView.measuredHeight(width:)`
- [ ] Verify UI correctness (menu contents, pinned state, counts).

## 7) Guardrails

- [ ] Ensure no token/log leakage in signposts.
- [ ] Keep files <500 LOC; split helpers if needed.
- [ ] Add regression tests if logic changes are non-trivial.
