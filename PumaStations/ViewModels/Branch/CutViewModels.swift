import Foundation
import Observation
import SwiftData

// MARK: - Cuts of the day + history

@Observable
final class CutsHubViewModel {
    private(set) var todayCuts: [CutShift: SalesCut] = [:]
    private(set) var history: [SalesCut] = []
    var errorMessage: String?

    let branch: Branch
    private let store: DataStore

    init(store: DataStore, branch: Branch) {
        self.store = store
        self.branch = branch
    }

    func load() {
        var cuts: [CutShift: SalesCut] = [:]
        for shift in CutShift.allCases {
            cuts[shift] = branch.cut(on: .now, shift: shift)
        }
        todayCuts = cuts

        let today = AppCalendar.calendar.startOfDay(for: .now)
        history = Array(
            branch.cuts
                .filter { $0.day < today }
                .sorted { $0.referenceDate > $1.referenceDate }
                .prefix(20)
        )
    }

    func canStart(_ shift: CutShift) -> Bool {
        CutService.canStart(shift, in: branch)
    }

    /// Starts today's cut for the shift and returns it.
    func start(_ shift: CutShift) -> SalesCut? {
        do {
            let cut = try CutService.start(shift, in: branch, store: store)
            load()
            return cut
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

// MARK: - One cut: 6 pumps + receptions + losses

struct PumpSlot: Identifiable {
    let number: Int
    let sale: PumpSale?

    var id: Int { number }
    var isRegistered: Bool { sale != nil }
}

@Observable
final class CutDetailViewModel {
    private(set) var slots: [PumpSlot] = []
    var errorMessage: String?

    let cut: SalesCut
    let branch: Branch
    private let store: DataStore

    init(store: DataStore, cut: SalesCut, branch: Branch) {
        self.store = store
        self.cut = cut
        self.branch = branch
    }

    var isEditable: Bool {
        !cut.isClosed
    }

    var registeredCount: Int {
        cut.registeredPumpCount
    }

    var missingCount: Int {
        max(BusinessRules.pumpsPerBranch - registeredCount, 0)
    }

    var progress: Double {
        Double(registeredCount) / Double(BusinessRules.pumpsPerBranch)
    }

    var receptions: [FuelReception] {
        cut.receptions.sorted { $0.receivedAt < $1.receivedAt }
    }

    var losses: [FuelLoss] {
        cut.losses.sorted { $0.recordedAt < $1.recordedAt }
    }

    /// First pump without a record (where "continue" should go).
    var nextPendingPump: Int? {
        slots.first { !$0.isRegistered }?.number
    }

    func load() {
        slots = (1...BusinessRules.pumpsPerBranch).map { PumpSlot(number: $0, sale: cut.sale(forPump: $0)) }
    }

    func delete(_ reception: FuelReception) {
        guard isEditable else { return }
        store.delete(reception)
        saveChanges()
    }

    func delete(_ loss: FuelLoss) {
        guard isEditable else { return }
        store.delete(loss)
        saveChanges()
    }

    private func saveChanges() {
        do {
            try store.save()
        } catch {
            errorMessage = "No se pudo eliminar: \(error.localizedDescription)"
        }
        load()
    }
}

// MARK: - Pump capture (movement 1: sales)

@Observable
final class PumpSaleViewModel {
    private(set) var pumpNumber: Int
    var gallons: [FuelType: Double] = [:]
    var amounts: [FuelType: Double] = [:]
    var isOutOfService = false
    var errorMessage: String?

    let cut: SalesCut
    let branch: Branch
    private let store: DataStore

    init(store: DataStore, cut: SalesCut, branch: Branch, pumpNumber: Int) {
        self.store = store
        self.cut = cut
        self.branch = branch
        self.pumpNumber = pumpNumber
        loadValues()
    }

    var isEditable: Bool {
        !cut.isClosed
    }

    var existingSale: PumpSale? {
        cut.sale(forPump: pumpNumber)
    }

    func isRegistered(_ number: Int) -> Bool {
        cut.sale(forPump: number) != nil
    }

    /// Next pump without a record after the current one (wrapping around).
    var nextPendingPump: Int? {
        let numbers = Array(1...BusinessRules.pumpsPerBranch)
        let ordered = numbers.filter { $0 > pumpNumber } + numbers.filter { $0 < pumpNumber }
        return ordered.first { !isRegistered($0) }
    }

    var totalAmount: Double {
        FuelType.allCases.reduce(0) { $0 + (amounts[$1] ?? 0) }
    }

    var totalGallons: Double {
        FuelType.allCases.reduce(0) { $0 + (gallons[$1] ?? 0) }
    }

    /// Setting gallons pre-fills the amount with the reference price (it can be edited afterwards).
    func setGallons(_ value: Double, for fuel: FuelType) {
        gallons[fuel] = value
        amounts[fuel] = (value * fuel.referenceSalePrice).rounded(toPlaces: 2)
    }

    func select(pump number: Int) {
        pumpNumber = number
        loadValues()
    }

    private func loadValues() {
        errorMessage = nil
        var newGallons: [FuelType: Double] = [:]
        var newAmounts: [FuelType: Double] = [:]
        if let sale = cut.sale(forPump: pumpNumber) {
            for fuel in FuelType.allCases {
                newGallons[fuel] = sale.gallons(fuel)
                newAmounts[fuel] = sale.amount(fuel)
            }
            isOutOfService = sale.isOutOfService
        } else {
            isOutOfService = false
        }
        gallons = newGallons
        amounts = newAmounts
    }

    /// Saves the record of the current pump.
    func save() -> Bool {
        guard isEditable else {
            errorMessage = CutError.alreadyClosed.localizedDescription
            return false
        }

        if !isOutOfService {
            guard totalGallons > 0 else {
                errorMessage = "Ingresa los galones vendidos o marca la bomba como fuera de servicio."
                return false
            }
            for fuel in FuelType.allCases {
                let fuelGallons = gallons[fuel] ?? 0
                let fuelAmount = amounts[fuel] ?? 0
                if fuelGallons < 0 || fuelAmount < 0 {
                    errorMessage = "Los valores no pueden ser negativos."
                    return false
                }
                if fuelGallons > 0 && fuelAmount == 0 {
                    errorMessage = "Ingresa el monto vendido de \(fuel.displayName)."
                    return false
                }
                // Stock after closing the cut, replacing this pump's previous values.
                let previous = existingSale?.gallons(fuel) ?? 0
                let projected = InventoryCalculator.projectedStock(of: branch, fuel: fuel, including: cut) + previous - fuelGallons
                if projected < 0 {
                    errorMessage = "\(fuel.displayName): la venta supera la existencia del tanque."
                    return false
                }
            }
        }

        let sale: PumpSale
        if let existingSale {
            sale = existingSale
        } else {
            sale = PumpSale(pumpNumber: pumpNumber)
            store.insert(sale)
            sale.cut = cut
        }
        sale.isOutOfService = isOutOfService
        sale.recordedAt = .now
        for fuel in FuelType.allCases {
            sale.setValues(
                gallons: isOutOfService ? 0 : (gallons[fuel] ?? 0),
                amount: isOutOfService ? 0 : (amounts[fuel] ?? 0),
                for: fuel
            )
        }

        do {
            try store.save()
            return true
        } catch {
            errorMessage = "Ocurrió un error al guardar: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - Fuel reception (movement 2)

@Observable
final class ReceptionViewModel {
    var fuel: FuelType = .regular
    var supplier = "Puma Energy El Salvador"
    var invoiceNumber = ""
    var receivedAt: Date = .now
    var gallons: Double = 0
    var costPerGallon: Double = FuelType.regular.referenceCost
    var errorMessage: String?

    let cut: SalesCut
    let branch: Branch
    private let store: DataStore

    init(store: DataStore, cut: SalesCut, branch: Branch) {
        self.store = store
        self.cut = cut
        self.branch = branch
        // Start with the most urgent tank.
        if let urgent = InventoryCalculator.levels(for: branch).min(by: { $0.ratio < $1.ratio }) {
            fuel = urgent.fuel
            costPerGallon = urgent.fuel.referenceCost
        }
    }

    func selectFuel(_ newFuel: FuelType) {
        fuel = newFuel
        costPerGallon = newFuel.referenceCost
    }

    var total: Double {
        gallons * costPerGallon
    }

    var capacity: Double {
        branch.capacity(for: fuel)
    }

    /// Current stock plus what was already received in this cut.
    var stockBefore: Double {
        branch.stock(for: fuel) + cut.gallonsReceived(fuel)
    }

    var stockAfter: Double {
        stockBefore + gallons
    }

    var freeSpace: Double {
        max(capacity - stockBefore, 0)
    }

    var exceedsCapacity: Bool {
        stockAfter > capacity
    }

    var statusAfter: TankStatus {
        let average = InventoryCalculator.dailyAverage(of: branch, fuel: fuel)
        let ratio = capacity > 0 ? stockAfter / capacity : 0
        return TankStatus.evaluate(ratio: ratio, daysLeft: average > 0 ? stockAfter / average : nil)
    }

    func save() -> Bool {
        guard !cut.isClosed else {
            errorMessage = CutError.alreadyClosed.localizedDescription
            return false
        }
        guard !supplier.trimmed.isEmpty, !invoiceNumber.trimmed.isEmpty else {
            errorMessage = "Ingresa el proveedor y el número de factura."
            return false
        }
        guard gallons > 0 else {
            errorMessage = "Los galones recibidos deben ser mayores que 0."
            return false
        }
        guard costPerGallon > 0 else {
            errorMessage = "Ingresa el costo por galón."
            return false
        }
        guard !exceedsCapacity else {
            errorMessage = "La recepción supera el espacio libre del tanque (\(AppFormat.gallons(freeSpace)))."
            return false
        }

        let reception = FuelReception(
            fuel: fuel,
            gallons: gallons,
            costPerGallon: costPerGallon,
            supplier: supplier.trimmed,
            invoiceNumber: invoiceNumber.trimmed,
            receivedAt: receivedAt
        )
        store.insert(reception)
        reception.cut = cut

        do {
            try store.save()
            return true
        } catch {
            errorMessage = "Ocurrió un error al guardar: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - Loss or damage (movement 3)

@Observable
final class LossViewModel {
    var type: LossType = .shrinkage
    var fuel: FuelType = .regular
    /// nil = storage tank; 1...6 = pump.
    var pumpNumber: Int?
    var gallons: Double = 0
    var details = ""
    var errorMessage: String?

    let cut: SalesCut
    let branch: Branch
    private let store: DataStore

    init(store: DataStore, cut: SalesCut, branch: Branch) {
        self.store = store
        self.cut = cut
        self.branch = branch
    }

    var estimatedCost: Double {
        gallons * fuel.referenceCost
    }

    var pumpNumbers: [Int] {
        Array(1...BusinessRules.pumpsPerBranch)
    }

    func save() -> Bool {
        guard !cut.isClosed else {
            errorMessage = CutError.alreadyClosed.localizedDescription
            return false
        }
        guard gallons > 0 else {
            errorMessage = "Los galones perdidos deben ser mayores que 0."
            return false
        }
        guard !details.trimmed.isEmpty else {
            errorMessage = "Describe lo ocurrido."
            return false
        }
        let projected = InventoryCalculator.projectedStock(of: branch, fuel: fuel, including: cut)
        guard gallons <= projected else {
            errorMessage = "La pérdida supera la existencia del tanque (\(AppFormat.gallons(max(projected, 0))))."
            return false
        }

        let loss = FuelLoss(type: type, fuel: fuel, gallons: gallons, pumpNumber: pumpNumber, details: details.trimmed)
        store.insert(loss)
        loss.cut = cut

        do {
            try store.save()
            return true
        } catch {
            errorMessage = "Ocurrió un error al guardar: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - Consolidated report / close cut

struct InventoryRow: Identifiable {
    let fuel: FuelType
    let opening: Double
    let received: Double
    let sold: Double
    let lost: Double

    var id: String { fuel.rawValue }
    var closing: Double { opening + received - sold - lost }
}

@Observable
final class CutReportViewModel {
    private(set) var inventory: [InventoryRow] = []
    private(set) var sales: [PumpSale] = []
    var errorMessage: String?

    let cut: SalesCut
    let branch: Branch
    private let store: DataStore

    init(store: DataStore, cut: SalesCut, branch: Branch) {
        self.store = store
        self.cut = cut
        self.branch = branch
    }

    var canClose: Bool {
        !cut.isClosed && cut.isReadyToClose
    }

    func load() {
        sales = cut.pumpSales.sorted { $0.pumpNumber < $1.pumpNumber }
        inventory = FuelType.allCases.map { fuel in
            // Closed cuts use the stored opening stock; open cuts start from the current stock.
            let opening = cut.isClosed ? cut.openingStock(fuel) : branch.stock(for: fuel)
            return InventoryRow(
                fuel: fuel,
                opening: opening,
                received: cut.gallonsReceived(fuel),
                sold: cut.gallonsSold(fuel),
                lost: cut.gallonsLost(fuel)
            )
        }
    }

    func close() -> Bool {
        do {
            try CutService.close(cut, in: branch, store: store)
            load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
