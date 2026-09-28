import Foundation
import Observation
import SwiftData

/// Tank levels of one branch, for the "tanks by branch" matrix.
struct BranchTanks: Identifiable {
    let id: PersistentIdentifier
    let name: String
    let levels: [TankLevel]
}

@Observable
final class GeneralDashboardViewModel {
    var branches: [Branch] = []
    var selectedBranch: Branch?
    var period: PeriodFilter = .month
    var fuelFilter: FuelFilter = .all
    var customStart: Date
    var customEnd: Date = .now
    private(set) var metrics: DashboardMetrics = .empty
    private(set) var alerts: [TankAlert] = []
    private(set) var tankMatrix: [BranchTanks] = []

    private let store: DataStore

    init(store: DataStore) {
        self.store = store
        customStart = AppCalendar.calendar.date(byAdding: .day, value: -30, to: .now) ?? .now
    }

    var scopeLabel: String {
        selectedBranch?.name ?? "Todo el país"
    }

    var periodLabel: String {
        switch period {
        case .today: return "Hoy"
        case .week: return "Esta semana"
        case .month: return AppFormat.date(.now, format: "MMMM yyyy").capitalized
        case .year: return AppFormat.date(.now, format: "yyyy")
        case .custom:
            return "\(AppFormat.date(customStart, format: "d MMM")) – \(AppFormat.date(customEnd, format: "d MMM"))"
        }
    }

    var isConsolidated: Bool {
        selectedBranch == nil
    }

    var criticalCount: Int {
        alerts.filter { $0.tank.status == .critical }.count
    }

    func load() {
        branches = store.branches()
        if let selected = selectedBranch,
           !branches.contains(where: { $0.persistentModelID == selected.persistentModelID }) {
            selectedBranch = nil
        }
        // Branches without a manager have no operation yet.
        let operating = branches.filter { !$0.cuts.isEmpty }
        let scope = selectedBranch.map { [$0] } ?? operating
        let range = period.range(customStart: customStart, customEnd: customEnd)

        metrics = DashboardCalculator.compute(branches: scope, range: range, fuels: fuelFilter.fuels)
        alerts = InventoryCalculator.alerts(for: scope)
        tankMatrix = scope.map {
            BranchTanks(id: $0.persistentModelID, name: $0.name, levels: InventoryCalculator.levels(for: $0))
        }
    }

    func resetFilters() {
        selectedBranch = nil
        period = .month
        fuelFilter = .all
    }
}
