import Foundation
import SwiftData

// MARK: - Filters

enum PeriodFilter: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case year
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Hoy"
        case .week: return "Semana"
        case .month: return "Mes"
        case .year: return "Año"
        case .custom: return "Rango"
        }
    }

    /// Periods without a custom range (used by the branch views).
    static let simpleOptions: [PeriodFilter] = [.today, .week, .month, .year]

    func range(customStart: Date = .now, customEnd: Date = .now, now: Date = .now) -> DateRange {
        let calendar = AppCalendar.calendar
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return DateRange(start: start, end: end)
        case .week:
            return DateRange(interval: calendar.dateInterval(of: .weekOfYear, for: now), fallback: now)
        case .month:
            return DateRange(interval: calendar.dateInterval(of: .month, for: now), fallback: now)
        case .year:
            return DateRange(interval: calendar.dateInterval(of: .year, for: now), fallback: now)
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let lastDay = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            return DateRange(start: start, end: end)
        }
    }
}

/// Fuel filter of the general dashboard.
enum FuelFilter: String, CaseIterable, Identifiable {
    case all
    case diesel
    case regular
    case premium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todos"
        case .diesel: return FuelType.diesel.displayName
        case .regular: return FuelType.regular.displayName
        case .premium: return FuelType.premium.displayName
        }
    }

    var fuels: [FuelType] {
        switch self {
        case .all: return FuelType.allCases
        case .diesel: return [.diesel]
        case .regular: return [.regular]
        case .premium: return [.premium]
        }
    }
}

struct DateRange {
    let start: Date
    let end: Date

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    init(interval: DateInterval?, fallback: Date) {
        self.start = interval?.start ?? fallback
        self.end = interval?.end ?? fallback
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// Range of the same length immediately before this one.
    var previous: DateRange {
        let length = end.timeIntervalSince(start)
        return DateRange(start: start.addingTimeInterval(-length), end: start)
    }

    var dayCount: Int {
        AppCalendar.calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

// MARK: - Results

struct BranchMetricRow: Identifiable {
    let id: PersistentIdentifier
    let name: String
    var gallons: [FuelType: Double] = [:]
    var sales: [FuelType: Double] = [:]
    var purchases: Double = 0
    var lossGallons: Double = 0
    var lossAmount: Double = 0
    var closedCuts = 0

    var totalGallons: Double { gallons.values.reduce(0, +) }
    var totalSales: Double { sales.values.reduce(0, +) }
    /// Gross margin: sales − fuel purchases − valued losses.
    var margin: Double { totalSales - purchases - lossAmount }
}

struct ChartBucket: Identifiable {
    let id = UUID()
    let label: String
    let start: Date
    let end: Date
    var sales: [FuelType: Double] = [:]
}

struct DashboardMetrics {
    var rows: [BranchMetricRow] = []
    var buckets: [ChartBucket] = []
    var previousSales: Double = 0

    func gallons(_ fuel: FuelType) -> Double { rows.reduce(0) { $0 + ($1.gallons[fuel] ?? 0) } }
    func sales(_ fuel: FuelType) -> Double { rows.reduce(0) { $0 + ($1.sales[fuel] ?? 0) } }

    var totalGallons: Double { rows.reduce(0) { $0 + $1.totalGallons } }
    var totalSales: Double { rows.reduce(0) { $0 + $1.totalSales } }
    var purchases: Double { rows.reduce(0) { $0 + $1.purchases } }
    var lossGallons: Double { rows.reduce(0) { $0 + $1.lossGallons } }
    var lossAmount: Double { rows.reduce(0) { $0 + $1.lossAmount } }
    var margin: Double { rows.reduce(0) { $0 + $1.margin } }
    var closedCuts: Int { rows.reduce(0) { $0 + $1.closedCuts } }

    var gallonsByFuel: [FuelType: Double] {
        Dictionary(uniqueKeysWithValues: FuelType.allCases.map { ($0, gallons($0)) })
    }

    /// Relative change of sales against the previous period (nil when not comparable).
    var salesChange: Double? {
        guard previousSales > 0 else { return nil }
        return (totalSales - previousSales) / previousSales
    }

    static let empty = DashboardMetrics()
}

// MARK: - Calculator

/// Pure business logic: consolidates the closed cuts into dashboard metrics.
enum DashboardCalculator {

    static func compute(branches: [Branch], range: DateRange, fuels: [FuelType] = FuelType.allCases) -> DashboardMetrics {
        var metrics = DashboardMetrics()
        var buckets = makeBuckets(for: range)

        for branch in branches {
            var row = BranchMetricRow(id: branch.persistentModelID, name: branch.name)
            for cut in branch.closedCuts where range.contains(cut.referenceDate) {
                row.closedCuts += 1
                for fuel in fuels {
                    let gallons = cut.gallonsSold(fuel)
                    let amount = cut.salesAmount(fuel)
                    row.gallons[fuel, default: 0] += gallons
                    row.sales[fuel, default: 0] += amount
                    row.purchases += cut.purchaseAmount(fuel)
                    row.lossGallons += cut.gallonsLost(fuel)
                    row.lossAmount += cut.lossAmount(fuel)
                    if let index = buckets.firstIndex(where: { cut.referenceDate >= $0.start && cut.referenceDate < $0.end }) {
                        buckets[index].sales[fuel, default: 0] += amount
                    }
                }
            }
            metrics.rows.append(row)
        }

        metrics.buckets = buckets
        metrics.previousSales = totalSales(of: branches, in: range.previous, fuels: fuels)
        return metrics
    }

    static func totalSales(of branches: [Branch], in range: DateRange, fuels: [FuelType] = FuelType.allCases) -> Double {
        branches.reduce(0) { total, branch in
            total + branch.closedCuts
                .filter { range.contains($0.referenceDate) }
                .reduce(0) { subtotal, cut in subtotal + fuels.reduce(0) { $0 + cut.salesAmount($1) } }
        }
    }

    // MARK: Chart buckets

    private enum Granularity {
        case cut, day, week, month
    }

    static func makeBuckets(for range: DateRange) -> [ChartBucket] {
        let calendar = AppCalendar.calendar
        let days = range.dayCount
        let granularity: Granularity
        if days <= 1 {
            granularity = .cut
        } else if days <= 8 {
            granularity = .day
        } else if days <= 62 {
            granularity = .week
        } else {
            granularity = .month
        }

        var result: [ChartBucket] = []
        var cursor = range.start
        var index = 0

        while cursor < range.end && index < 60 {
            let next: Date
            switch granularity {
            case .cut:
                // Morning cut (reference 10:00) before 14:00, evening cut after.
                next = calendar.date(byAdding: .hour, value: index == 0 ? 14 : 10, to: cursor) ?? range.end
            case .day:
                next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? range.end
            case .week:
                next = calendar.dateInterval(of: .weekOfYear, for: cursor)?.end ?? range.end
            case .month:
                next = calendar.dateInterval(of: .month, for: cursor)?.end ?? range.end
            }
            let end = min(next, range.end)
            guard end > cursor else { break }

            let label: String
            switch granularity {
            case .cut: label = index == 0 ? "Matutino" : "Vespertino"
            case .day: label = AppFormat.date(cursor, format: "EEE d")
            case .week: label = "Sem \(index + 1)"
            case .month: label = AppFormat.date(cursor, format: "MMM")
            }

            result.append(ChartBucket(label: label, start: cursor, end: end))
            cursor = end
            index += 1
        }
        return result
    }
}
