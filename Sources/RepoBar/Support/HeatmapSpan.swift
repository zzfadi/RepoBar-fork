import Foundation

enum HeatmapSpan: Int, CaseIterable, Equatable, Codable {
    case oneMonth = 1
    case threeMonths = 3
    case sixMonths = 6
    case twelveMonths = 12

    var label: String {
        switch self {
        case .oneMonth: "1 month"
        case .threeMonths: "3 months"
        case .sixMonths: "6 months"
        case .twelveMonths: "12 months"
        }
    }

    var months: Int { self.rawValue }
}

enum HeatmapFilter {
    static func filter(_ cells: [HeatmapCell], span: HeatmapSpan, now: Date = Date()) -> [HeatmapCell] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .month, value: -span.months, to: now) else { return cells }
        return cells.filter { $0.date >= cutoff }
    }
}
