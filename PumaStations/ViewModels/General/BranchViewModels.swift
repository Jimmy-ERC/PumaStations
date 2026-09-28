import Foundation
import Observation
import SwiftData

// MARK: - Branch list

struct BranchListItem: Identifiable {
    let branch: Branch
    let manager: UserAccount?
    let monthSales: Double
    let worstStatus: TankStatus
    let hasOperation: Bool

    var id: PersistentIdentifier { branch.persistentModelID }
}

@Observable
final class BranchListViewModel {
    var searchText = ""
    private(set) var items: [BranchListItem] = []

    private let store: DataStore

    init(store: DataStore) {
        self.store = store
    }

    var filteredItems: [BranchListItem] {
        let query = searchText.trimmed
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.branch.name.localizedCaseInsensitiveContains(query)
                || $0.branch.municipality.localizedCaseInsensitiveContains(query)
        }
    }

    var totalPumps: Int {
        items.reduce(0) { $0 + $1.branch.pumps.count }
    }

    var criticalCount: Int {
        items.filter { $0.hasOperation && $0.worstStatus == .critical }.count
    }

    func load() {
        let monthRange = PeriodFilter.month.range()
        items = store.branches().map { branch in
            BranchListItem(
                branch: branch,
                manager: store.manager(of: branch),
                monthSales: DashboardCalculator.totalSales(of: [branch], in: monthRange),
                worstStatus: InventoryCalculator.worstStatus(for: branch),
                hasOperation: !branch.cuts.isEmpty
            )
        }
    }
}

// MARK: - New branch

@Observable
final class BranchFormViewModel {
    var name = ""
    var code = ""
    var address = ""
    var municipality = ""
    var phone = ""
    var capacities: [FuelType: Double] = [.diesel: 10_000, .regular: 12_000, .premium: 8_000]
    var selectedManager: UserAccount?
    var errorMessage: String?
    private(set) var availableManagers: [UserAccount] = []

    private let store: DataStore

    init(store: DataStore) {
        self.store = store
    }

    func load() {
        availableManagers = store.branchManagers().filter { $0.branch == nil && $0.isActive }
        if code.isEmpty {
            code = String(format: "SUC-%03d", store.branches().count + 1)
        }
    }

    var canSave: Bool {
        !name.trimmed.isEmpty && !address.trimmed.isEmpty
    }

    func save() -> Bool {
        guard !name.trimmed.isEmpty else {
            errorMessage = "Ingresa el nombre de la sucursal."
            return false
        }
        guard !address.trimmed.isEmpty, !municipality.trimmed.isEmpty else {
            errorMessage = "Ingresa la dirección y el municipio."
            return false
        }
        guard FuelType.allCases.allSatisfy({ (capacities[$0] ?? 0) > 0 }) else {
            errorMessage = "La capacidad de cada tanque debe ser mayor que 0."
            return false
        }
        let nameTaken = store.branches().contains { $0.name.caseInsensitiveCompare(name.trimmed) == .orderedSame }
        guard !nameTaken else {
            errorMessage = "Ya existe una sucursal con ese nombre."
            return false
        }

        let branch = store.createBranch(
            name: name.trimmed,
            code: code.trimmed,
            address: address.trimmed,
            municipality: municipality.trimmed,
            phone: phone.trimmed,
            capacities: capacities
        )
        selectedManager?.branch = branch

        do {
            try store.save()
            return true
        } catch {
            errorMessage = "Ocurrió un error al guardar: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - Station detail (read only, general manager)

@Observable
final class StationDetailViewModel {
    var period: PeriodFilter = .month
    private(set) var manager: UserAccount?
    private(set) var metrics: DashboardMetrics = .empty
    private(set) var tanks: [TankLevel] = []
    private(set) var todayCuts: [CutShift: SalesCut] = [:]
    private(set) var recentLosses: [FuelLoss] = []
    private(set) var recentCuts: [SalesCut] = []

    let branch: Branch
    private let store: DataStore

    init(store: DataStore, branch: Branch) {
        self.store = store
        self.branch = branch
    }

    /// Most urgent non-optimal tank, used for the banner.
    var mainAlert: TankLevel? {
        tanks.filter { $0.status != .optimal }.min { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status < rhs.status }
            return (lhs.daysLeft ?? .infinity) < (rhs.daysLeft ?? .infinity)
        }
    }

    var hasOperation: Bool {
        !branch.cuts.isEmpty
    }

    func load() {
        manager = store.manager(of: branch)
        metrics = DashboardCalculator.compute(branches: [branch], range: period.range())
        tanks = InventoryCalculator.levels(for: branch)
        var cuts: [CutShift: SalesCut] = [:]
        for shift in CutShift.allCases {
            cuts[shift] = branch.cut(on: .now, shift: shift)
        }
        todayCuts = cuts
        recentLosses = Array(branch.cuts.flatMap(\.losses).sorted { $0.recordedAt > $1.recordedAt }.prefix(5))
        recentCuts = Array(branch.closedCuts.sorted { $0.referenceDate > $1.referenceDate }.prefix(6))
    }
}
