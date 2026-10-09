import Foundation
import Observation
import SwiftData

// MARK: - Sales of the branch (fuel + store + maintenance)

@Observable
final class BranchSalesViewModel {
    var period: PeriodFilter = .month
    private(set) var fuelMetrics: DashboardMetrics = .empty
    private(set) var storeMetrics: StoreMetrics = .empty
    private(set) var recentSales: [Sale] = []
    private(set) var stockAlerts: [StockLevel] = []

    let branch: Branch
    private let store: DataStore

    init(store: DataStore, branch: Branch) {
        self.store = store
        self.branch = branch
    }

    /// Fuel (closed cuts) + store + maintenance.
    var totalSales: Double {
        fuelMetrics.totalSales + storeMetrics.total
    }

    /// Relative change of the total against the previous period (nil when not comparable).
    var totalChange: Double? {
        let previous = fuelMetrics.previousSales + storeMetrics.previousTotal
        guard previous > 0 else { return nil }
        return (totalSales - previous) / previous
    }

    var periodLabel: String {
        switch period {
        case .today: return "Hoy"
        case .week: return "Esta semana"
        case .month: return AppFormat.date(.now, format: "MMMM yyyy").capitalized
        case .year: return AppFormat.date(.now, format: "yyyy")
        case .custom: return period.title
        }
    }

    func load() {
        let range = period.range()
        let sales = store.sales(of: branch)
        fuelMetrics = DashboardCalculator.compute(branches: [branch], range: range)
        storeMetrics = StoreCalculator.compute(sales: sales, range: range)
        recentSales = Array(sales.filter { range.contains($0.soldAt) }.prefix(8))
        let levels = StoreCalculator.stockLevels(
            items: store.catalogItems(),
            entries: store.stockEntries(of: branch),
            sales: sales
        )
        stockAlerts = StoreCalculator.alerts(in: levels)
    }
}

// MARK: - Store inventory of the branch

@Observable
final class StoreInventoryViewModel {
    var searchText = ""
    var category: CatalogCategory = .convenience
    private(set) var levels: [StockLevel] = []
    private(set) var entries: [StockEntry] = []

    let branch: Branch
    private let store: DataStore

    init(store: DataStore, branch: Branch) {
        self.store = store
        self.branch = branch
    }

    var filteredLevels: [StockLevel] {
        let query = searchText.trimmed
        return levels.filter { level in
            level.item.category == category
                && (query.isEmpty || level.item.name.localizedCaseInsensitiveContains(query))
        }
    }

    var alertCount: Int {
        StoreCalculator.alerts(in: levels).count
    }

    var totalUnits: Int {
        levels.reduce(0) { $0 + max($1.available, 0) }
    }

    /// Value of the stock at sale price.
    var stockValue: Double {
        levels.reduce(0) { $0 + Double(max($1.available, 0)) * $1.item.price }
    }

    func recentEntries(of item: CatalogItem) -> [StockEntry] {
        entries.filter { $0.item?.persistentModelID == item.persistentModelID }
    }

    func load() {
        entries = store.stockEntries(of: branch).sorted { $0.receivedAt > $1.receivedAt }
        levels = StoreCalculator.stockLevels(
            items: store.catalogItems(),
            entries: entries,
            sales: store.sales(of: branch)
        )
    }
}

// MARK: - Stock entry (restocking a product)

@Observable
final class StockEntryViewModel {
    var quantity: Double = 12
    var unitCost: Double
    var note = ""
    var errorMessage: String?

    let level: StockLevel
    let branch: Branch
    private let store: DataStore

    init(store: DataStore, branch: Branch, level: StockLevel) {
        self.store = store
        self.branch = branch
        self.level = level
        unitCost = (level.item.price * 0.7).rounded(toPlaces: 2)
    }

    var units: Int {
        Int(quantity.rounded())
    }

    var stockAfter: Int {
        level.available + max(units, 0)
    }

    var statusAfter: StockStatus {
        StockStatus.evaluate(available: stockAfter, minimum: level.item.minStock)
    }

    var total: Double {
        Double(max(units, 0)) * unitCost
    }

    func save() -> Bool {
        guard units > 0 else {
            errorMessage = "Ingresa las unidades recibidas."
            return false
        }
        guard unitCost >= 0 else {
            errorMessage = "El costo no puede ser negativo."
            return false
        }
        let entry = StockEntry(quantity: units, unitCost: unitCost, note: note.trimmed)
        store.insert(entry)
        entry.branch = branch
        entry.item = level.item

        do {
            try store.save()
            return true
        } catch {
            errorMessage = "Ocurrió un error al guardar: \(error.localizedDescription)"
            return false
        }
    }
}
