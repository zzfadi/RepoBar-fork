import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

struct HeatmapBinningTests {
    @Test
    func fillsGridToExpectedSize() {
        let cells = (0 ..< 20).map { HeatmapCell(date: Date().addingTimeInterval(Double(-$0) * 86400), count: $0 % 3) }
        let grid = HeatmapLayout.reshape(cells: cells, columns: 4)
        #expect(grid.count == 4)
        #expect(grid.allSatisfy { $0.count == HeatmapLayout.rows })
    }

    @Test
    func padsWhenInputIsSmaller() {
        let grid = HeatmapLayout.reshape(cells: [], columns: 3)
        #expect(grid.count == 3)
        #expect(grid.flatMap { $0 }.count == 3 * HeatmapLayout.rows)
    }
}
