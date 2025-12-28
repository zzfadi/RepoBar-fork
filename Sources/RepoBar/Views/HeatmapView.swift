import RepoBarCore
import SwiftUI

struct HeatmapView: View {
    let cells: [HeatmapCell]
    let accentTone: AccentTone
    private let rows = 7
    private let minColumns = 53
    private let spacing: CGFloat = 0.5
    private let height: CGFloat?
    @Environment(\.menuItemHighlighted) private var isHighlighted
    private var summary: String {
        let total = self.cells.map(\.count).reduce(0, +)
        let maxVal = self.cells.map(\.count).max() ?? 0
        return "Commit activity heatmap, total \(total) commits, max \(maxVal) in a day."
    }

    init(cells: [HeatmapCell], accentTone: AccentTone = .githubGreen, height: CGFloat? = nil) {
        self.cells = cells
        self.accentTone = accentTone
        self.height = height
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let cellSide = self.cellSide(for: size)
            let columns = self.columnCount(for: size, cellSide: cellSide)
            let grid = HeatmapLayout.reshape(cells: self.cells, columns: columns, rows: self.rows)
            Canvas { context, _ in
                for (x, column) in grid.enumerated() {
                    for (y, cell) in column.enumerated() {
                        let origin = CGPoint(
                            x: CGFloat(x) * (cellSide + self.spacing),
                            y: CGFloat(y) * (cellSide + self.spacing)
                        )
                        let rect = CGRect(origin: origin, size: CGSize(width: cellSide, height: cellSide))
                        let path = Path(roundedRect: rect, cornerRadius: cellSide * 0.12)
                        context.fill(path, with: .color(self.color(for: cell.count)))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: self.height)
        .accessibilityLabel(self.summary)
        .accessibilityElement(children: .ignore)
    }

    private func color(for count: Int) -> Color {
        let palette = self.palette()
        switch count {
        case 0: return palette[0]
        case 1 ... 3: return palette[1]
        case 4 ... 7: return palette[2]
        case 8 ... 12: return palette[3]
        default: return palette[4]
        }
    }

    private func palette() -> [Color] {
        if self.isHighlighted {
            let base = Color(nsColor: .selectedMenuItemTextColor)
            return [
                base.opacity(0.28),
                base.opacity(0.46),
                base.opacity(0.64),
                base.opacity(0.82),
                base.opacity(0.92)
            ]
        }
        switch self.accentTone {
        case .githubGreen:
            return [
                Color(nsColor: .quaternaryLabelColor),
                Color(red: 0.74, green: 0.86, blue: 0.75).opacity(0.6),
                Color(red: 0.56, green: 0.76, blue: 0.6).opacity(0.65),
                Color(red: 0.3, green: 0.62, blue: 0.38).opacity(0.7),
                Color(red: 0.18, green: 0.46, blue: 0.24).opacity(0.75)
            ]
        case .system:
            let accent = Color.accentColor
            return [
                Color(nsColor: .quaternaryLabelColor),
                accent.opacity(0.22),
                accent.opacity(0.36),
                accent.opacity(0.5),
                accent.opacity(0.65)
            ]
        }
    }

    private func columnCount(for size: CGSize, cellSide: CGFloat) -> Int {
        guard cellSide > 0 else { return self.minColumns }
        let available = max(size.width + self.spacing, 0)
        let columns = Int(floor(available / (cellSide + self.spacing)))
        return max(columns, self.minColumns)
    }

    private func cellSide(for size: CGSize) -> CGFloat {
        let totalSpacingY = CGFloat(self.rows - 1) * self.spacing
        let availableHeight = max(size.height - totalSpacingY, 0)
        let side = availableHeight / CGFloat(self.rows)
        return max(2, min(10, floor(side)))
    }
}

enum HeatmapLayout {
    static func reshape(cells: [HeatmapCell], columns: Int, rows: Int) -> [[HeatmapCell]] {
        var padded = cells
        if padded.count < columns * rows {
            let missing = columns * rows - padded.count
            padded.append(contentsOf: Array(repeating: HeatmapCell(date: Date(), count: 0), count: missing))
        }
        return stride(from: 0, to: padded.count, by: rows).map { index in
            Array(padded[index ..< min(index + rows, padded.count)])
        }
    }
}
