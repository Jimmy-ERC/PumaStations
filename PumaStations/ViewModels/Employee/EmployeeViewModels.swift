import Foundation
import Observation
import SwiftData

// MARK: - Point of sale (store ticket or maintenance order)

/// One catalog item offered in the point of sale, with what is left in the store.
struct SaleOption: Identifiable {
    let item: CatalogItem
    /// nil for services, which have no inventory.
    let available: Int?

    var id: UUID { item.remoteID }
}

@Observable
final class SaleViewModel {
    var searchText = ""
    var payment: PaymentMethod = .cash
    var vehiclePlate = ""
    var errorMessage: String?
    private(set) var options: [SaleOption] = []
    private(set) var quantities: [UUID: Int] = [:]
    private(set) var activeShift: WorkShift?
    /// Last registered sale, shown as confirmation.
    var lastSale: Sale?

    let kind: SaleKind
    let branch: Branch
    let seller: UserAccount
    private let store: DataStore

    init(store: DataStore, kind: SaleKind, branch: Branch, seller: UserAccount) {
        self.store = store
        self.kind = kind
        self.branch = branch
        self.seller = seller
    }

    var title: String {
        kind == .store ? "Tienda" : "Mantenimiento"
    }

    var canSell: Bool {
        activeShift != nil
    }

    func options(in category: CatalogCategory) -> [SaleOption] {
        let query = searchText.trimmed
        return options.filter { option in
            option.item.category == category
                && (query.isEmpty || option.item.name.localizedCaseInsensitiveContains(query))
        }
    }

    func quantity(of option: SaleOption) -> Int {
        quantities[option.id] ?? 0
    }

    /// Products cannot exceed the stock of the store.
    func canAdd(_ option: SaleOption) -> Bool {
        guard canSell else { return false }
        guard let available = option.available else { return quantity(of: option) < 1 }
        return quantity(of: option) < available
    }

    func add(_ option: SaleOption) {
        guard canAdd(option) else { return }
        quantities[option.id, default: 0] += 1
    }

    func remove(_ option: SaleOption) {
        let current = quantity(of: option)
        quantities[option.id] = current > 1 ? current - 1 : nil
    }

    var cartLines: [CartLine] {
        options.compactMap { option in
            let quantity = quantity(of: option)
            return quantity > 0 ? CartLine(item: option.item, quantity: quantity) : nil
        }
    }

    var unitCount: Int {
        quantities.values.reduce(0, +)
    }

    var total: Double {
        cartLines.reduce(0) { $0 + Double($1.quantity) * $1.item.price }
    }

    var canCharge: Bool {
        canSell && unitCount > 0
    }

    func load() {
        activeShift = ShiftService.activeShift(of: seller, store: store)
        let items = store.catalogItems().filter { $0.isActive && kind.categories.contains($0.category) }
        let levels = StoreCalculator.stockLevels(
            items: items,
            entries: store.stockEntries(of: branch),
            sales: store.sales(of: branch)
        )
        options = items.map { item in
            SaleOption(item: item, available: levels.first { $0.id == item.remoteID }?.available)
        }
        // Drop from the cart what is no longer offered.
        let offered = Set(options.map(\.id))
        quantities = quantities.filter { offered.contains($0.key) }
    }

    func clear() {
        quantities = [:]
        vehiclePlate = ""
        payment = .cash
    }

    /// Registers the sale and empties the cart.
    func charge() {
        do {
            let sale = try SaleService.register(
                kind: kind,
                lines: cartLines,
                payment: payment,
                vehiclePlate: vehiclePlate,
                seller: seller,
                branch: branch,
                store: store
            )
            clear()
            load()
            lastSale = sale
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - My shift (attendance and own sales)

@Observable
final class MyShiftViewModel {
    private(set) var todayShifts: [WorkShift] = []
    private(set) var upcoming: [WorkShift] = []
    private(set) var history: [WorkShift] = []
    private(set) var todaySales: [Sale] = []
    private(set) var weekHours: Double = 0
    var errorMessage: String?

    let employee: UserAccount
    let branch: Branch
    private let store: DataStore

    init(store: DataStore, employee: UserAccount, branch: Branch) {
        self.store = store
        self.employee = employee
        self.branch = branch
    }

    var activeShift: WorkShift? {
        todayShifts.first { $0.isInProgress }
    }

    var todayTotal: Double {
        todaySales.reduce(0) { $0 + $1.total }
    }

    func load() {
        let today = AppCalendar.calendar.startOfDay(for: .now)
        let shifts = store.workShifts(of: employee)
        todayShifts = shifts.filter { $0.isToday }.sorted { $0.shiftRaw < $1.shiftRaw }
        upcoming = Array(
            shifts.filter { $0.day > today }
                .sorted { ($0.day, $0.shiftRaw) < ($1.day, $1.shiftRaw) }
                .prefix(7)
        )
        history = Array(
            shifts.filter { $0.day < today }
                .sorted { ($0.day, $0.shiftRaw) > ($1.day, $1.shiftRaw) }
                .prefix(7)
        )
        let week = PeriodFilter.week.range()
        weekHours = shifts.filter { week.contains($0.day) }.reduce(0) { $0 + $1.workedHours }

        let todayRange = PeriodFilter.today.range()
        todaySales = store.sales(of: branch).filter {
            $0.seller?.persistentModelID == employee.persistentModelID && todayRange.contains($0.soldAt)
        }
    }

    func checkIn(_ shift: WorkShift) {
        do {
            try ShiftService.checkIn(shift, store: store)
        } catch {
            errorMessage = error.localizedDescription
        }
        load()
    }

    func checkOut(_ shift: WorkShift) {
        do {
            try ShiftService.checkOut(shift, store: store)
        } catch {
            errorMessage = error.localizedDescription
        }
        load()
    }
}
