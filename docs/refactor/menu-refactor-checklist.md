# Refactor Checklist

- [x] Extract shared submenu icon column view (icon + placeholder) to reduce per-view layout duplication.
- [x] Split `LocalRepoStateMenuView` into smaller subviews (header/details/dirty files/actions).
- [ ] Refactor list menu item creation in `StatusBarMenuManager.populateListMenu` into helpers to remove duplicated NSMenuItem setup.
