import Foundation
import SwiftData

/// Current level of one tank plus the indicators used for restocking alerts.
struct TankLevel: Identifiable {
    let fuel: FuelType
    let stock: Double
    let capacity: Double
    /// Average gallons sold per day in the last 7 days.
    let dailyAverage: Double

    var id: String { fuel.rawValue }

    var ratio: Double {
        guard capacity > 0 else { return 0 }
        return min(max(stock / capacity, 0), 1)
    }

    /// Estimated days until the tank runs out at the current pace (nil when there are no recent sales).
    var daysLeft: Double? {
        guard dailyAverage > 0 else { return nil }
        return stock / dailyAverage
    }

    var status: TankStatus {
        TankStatus.evaluate(ratio: ratio, daysLeft: daysLeft)
    }

    /// Suggested order to bring the tank to ~85 % (rounded down to 500 gal).
    var suggestedOrder: Double {
        let target = capacity * 0.85 - stock
        guard target > 0 else { return 0 }
        return (target / 500).rounded(.down) * 500
    }
}

struct TankAlert: Identifiable {
    let branchName: String
    let tank: TankLevel

    var id: String { branchName + tank.fuel.rawValue }
}

/// Pure logic for tank levels, daily averages and projected stock.
enum InventoryCalculator {

    static func dailyAverage(of branch: Branch, fuel: FuelType, now: Date = .now) -> Double {
        let calendar = AppCalendar.calendar
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -BusinessRules.averageWindowDays, to: today) else { return 0 }
        let sold = branch.closedCuts
            .filter { $0.day >= start && $0.day < today }
            .reduce(0) { $0 + $1.gallonsSold(fuel) }
        return sold / Double(BusinessRules.averageWindowDays)
    }

    static func levels(for branch: Branch, now: Date = .now) -> [TankLevel] {
        FuelType.allCases.map { fuel in
            TankLevel(
                fuel: fuel,
                stock: branch.stock(for: fuel),
                capacity: branch.capacity(for: fuel),
                dailyAverage: dailyAverage(of: branch, fuel: fuel, now: now)
            )
        }
    }

    static func worstStatus(for branch: Branch) -> TankStatus {
        levels(for: branch).map(\.status).min() ?? .optimal
    }

    /// Non-optimal tanks of the given branches, most urgent first.
    static func alerts(for branches: [Branch]) -> [TankAlert] {
        branches
            .flatMap { branch in
                levels(for: branch)
                    .filter { $0.status != .optimal }
                    .map { TankAlert(branchName: branch.name, tank: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.tank.status != rhs.tank.status { return lhs.tank.status < rhs.tank.status }
                return (lhs.tank.daysLeft ?? .infinity) < (rhs.tank.daysLeft ?? .infinity)
            }
    }

    /// Stock the tank will have when the open cut is closed.
    static func projectedStock(of branch: Branch, fuel: FuelType, including cut: SalesCut?) -> Double {
        guard let cut, !cut.isClosed else { return branch.stock(for: fuel) }
        return branch.stock(for: fuel) + cut.netMovement(fuel)
    }
}
