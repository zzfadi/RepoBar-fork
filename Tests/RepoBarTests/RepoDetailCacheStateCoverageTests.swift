import RepoBarCore
import Testing

struct RepoDetailCacheStateCoverageTests {
    @Test
    func cacheFreshness_needsRefresh() {
        #expect(CacheFreshness.fresh.needsRefresh == false)
        #expect(CacheFreshness.stale.needsRefresh == true)
        #expect(CacheFreshness.missing.needsRefresh == true)
    }

    @Test
    func missing_isAllMissing() {
        let state = RepoDetailCacheState.missing
        #expect(state.openPulls == .missing)
        #expect(state.release == .missing)
    }
}

