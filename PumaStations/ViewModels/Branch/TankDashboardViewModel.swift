import Foundation
import Observation
import SwiftData

/// Gallons received, sold and lost for one fuel in a period.
struct FuelMovement: Identifiable {
    let fuel: FuelType
    let received: Double
    let sold: Double
    let lost: Double

    var id: String { fuel.rawValue }
}

@Observable
final class TankDashboardViewModel {
    var period: PeriodFilter = .month
    private(set) var tanks: [TankLevel] = []
    private(set) var todayCuts: [CutShift: SalesCut] = [:]
    private(set) var metrics: DashboardMetrics = .empty
    private(set) var movements: [FuelMovement] = []

    let branch: Branch
    let manager: UserAccount
    private let store: DataStore

    init(store: DataStore, branch: Branch, manager: UserAccount) {
        self.store = store
        self.branch = branch
        self.manager = manager
    }

    /// Most urgent non-optimal tank, used for the restocking banner.
    var mainAlert: TankLevel? {
        tanks.filter { $0.status != .optimal }.min { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status < rhs.status }
            return (lhs.daysLeft ?? .infinity) < (rhs.daysLeft ?? .infinity)
        }
    }

    var lastClosedCutText: String {
        guard let last = branch.closedCuts.max(by: { $0.referenceDate < $1.referenceDate }) else {
            return "Sin cortes cerrados"
        }
        return "Tras \(last.title)"
    }

    func load() {
        tanks = InventoryCalculator.levels(for: branch)
        var cuts: [CutShift: SalesCut] = [:]
        for shift in CutShift.allCases {
            cuts[shift] = branch.cut(on: .now, shift: shift)
        }
        todayCuts = cuts

        let range = period.range()
        metrics = DashboardCalculator.compute(branches: [branch], range: range)
        let periodCuts = branch.closedCuts.filter { range.contains($0.referenceDate) }
        movements = FuelType.allCases.map { fuel in
            FuelMovement(
                fuel: fuel,
                received: periodCuts.reduce(0) { $0 + $1.gallonsReceived(fuel) },
                sold: periodCuts.reduce(0) { $0 + $1.gallonsSold(fuel) },
                lost: periodCuts.reduce(0) { $0 + $1.gallonsLost(fuel) }
            )
        }
    }
}
