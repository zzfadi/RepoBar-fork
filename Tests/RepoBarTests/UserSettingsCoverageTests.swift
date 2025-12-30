import Foundation
import RepoBarCore
import Testing

struct UserSettingsCoverageTests {
    @Test
    func labelsAndSeconds_coverEnumSwitches() {
        #expect(LocalProjectsRefreshInterval.oneMinute.seconds == 60)
        #expect(LocalProjectsRefreshInterval.fifteenMinutes.seconds == 900)
        #expect(LocalProjectsRefreshInterval.twoMinutes.label == "2 minutes")

        #expect(GhosttyOpenMode.newWindow.label == "New Window")
        #expect(GhosttyOpenMode.tab.label == "Tab")

        #expect(RefreshInterval.oneMinute.seconds == 60)
        #expect(RefreshInterval.fifteenMinutes.seconds == 900)

        #expect(HeatmapDisplay.inline.label == "Inline")
        #expect(HeatmapDisplay.submenu.label == "Submenu")

        #expect(CardDensity.comfortable.label == "Comfortable")
        #expect(CardDensity.compact.label == "Compact")

        #expect(AccentTone.system.label == "System accent")
        #expect(AccentTone.githubGreen.label == "GitHub greens")

        #expect(GlobalActivityScope.allActivity.label == "All activity")
        #expect(GlobalActivityScope.myActivity.label == "My activity")
    }
}

