import Foundation
@testable import RepoBarCore
import Testing

struct HeatmapFilterTests {
    @Test
    func spanLabelsAreStable() {
        #expect(HeatmapSpan.oneMonth.label == "1 month")
        #expect(HeatmapSpan.threeMonths.label == "3 months")
        #expect(HeatmapSpan.sixMonths.label == "6 months")
        #expect(HeatmapSpan.twelveMonths.label == "12 months")
    }

    @Test
    func filterDropsOlderCells() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = calendar.date(from: DateComponents(year: 2025, month: 12, day: 15, hour: 12))!
        let recent = calendar.date(byAdding: .day, value: -10, to: now)!
        let old = calendar.date(byAdding: .day, value: -80, to: now)!

        let cells = [
            HeatmapCell(date: old, count: 1),
            HeatmapCell(date: recent, count: 2)
        ]

        let filtered = HeatmapFilter.filter(cells, span: .oneMonth, now: now)
        #expect(filtered.count == 1)
        #expect(filtered.first?.date == recent)
    }
}
