import Foundation
import SwiftData

// MARK: - Sales cut

/// One of the two daily cuts of a branch. It groups the three movement categories:
/// sales (one record per pump), fuel receptions and losses.
@Model
final class SalesCut {
    /// Start of the day the cut belongs to.
    var day: Date
    var shiftRaw: Int
    var statusRaw: String
    var openedAt: Date
    var closedAt: Date?

    /// Tank stock when the cut was closed (before applying its movements). Used by the report.
    var openingDiesel: Double
    var openingRegular: Double
    var openingPremium: Double

    var branch: Branch?

    @Relationship(deleteRule: .cascade, inverse: \PumpSale.cut)
    var pumpSales: [PumpSale] = []

    @Relationship(deleteRule: .cascade, inverse: \FuelReception.cut)
    var receptions: [FuelReception] = []

    @Relationship(deleteRule: .cascade, inverse: \FuelLoss.cut)
    var losses: [FuelLoss] = []

    init(day: Date, shift: CutShift, openedAt: Date = .now) {
        self.day = AppCalendar.calendar.startOfDay(for: day)
        self.shiftRaw = shift.rawValue
        self.statusRaw = CutStatus.open.rawValue
        self.openedAt = openedAt
        self.closedAt = nil
        self.openingDiesel = 0
        self.openingRegular = 0
        self.openingPremium = 0
    }

    // MARK: State

    var shift: CutShift {
        CutShift(rawValue: shiftRaw) ?? .morning
    }

    var status: CutStatus {
        CutStatus(rawValue: statusRaw) ?? .open
    }

    var isClosed: Bool {
        status == .closed
    }

    /// Point in time used by charts and period filters.
    var referenceDate: Date {
        AppCalendar.calendar.date(byAdding: .hour, value: shift.referenceHour, to: day) ?? day
    }

    // MARK: Pumps

    func sale(forPump number: Int) -> PumpSale? {
        pumpSales.first { $0.pumpNumber == number }
    }

    var registeredPumpCount: Int {
        Set(pumpSales.map(\.pumpNumber)).count
    }

    /// A cut can be closed only when all 6 pumps have their record.
    var isReadyToClose: Bool {
        registeredPumpCount >= BusinessRules.pumpsPerBranch
    }

    // MARK: Consolidated figures

    func gallonsSold(_ fuel: FuelType) -> Double {
        pumpSales.reduce(0) { $0 + $1.gallons(fuel) }
    }

    func salesAmount(_ fuel: FuelType) -> Double {
        pumpSales.reduce(0) { $0 + $1.amount(fuel) }
    }

    var totalSales: Double {
        pumpSales.reduce(0) { $0 + $1.totalAmount }
    }

    var totalGallons: Double {
        pumpSales.reduce(0) { $0 + $1.totalGallons }
    }

    func gallonsReceived(_ fuel: FuelType) -> Double {
        receptions.filter { $0.fuel == fuel }.reduce(0) { $0 + $1.gallons }
    }

    func purchaseAmount(_ fuel: FuelType) -> Double {
        receptions.filter { $0.fuel == fuel }.reduce(0) { $0 + $1.total }
    }

    var totalPurchases: Double {
        receptions.reduce(0) { $0 + $1.total }
    }

    func gallonsLost(_ fuel: FuelType) -> Double {
        losses.filter { $0.fuel == fuel }.reduce(0) { $0 + $1.gallons }
    }

    func lossAmount(_ fuel: FuelType) -> Double {
        losses.filter { $0.fuel == fuel }.reduce(0) { $0 + $1.estimatedCost }
    }

    var totalLossGallons: Double {
        losses.reduce(0) { $0 + $1.gallons }
    }

    /// Net change the cut applies to a tank: + received − sold − lost.
    func netMovement(_ fuel: FuelType) -> Double {
        gallonsReceived(fuel) - gallonsSold(fuel) - gallonsLost(fuel)
    }

    func openingStock(_ fuel: FuelType) -> Double {
        switch fuel {
        case .diesel: return openingDiesel
        case .regular: return openingRegular
        case .premium: return openingPremium
        }
    }

    func setOpeningStock(_ value: Double, for fuel: FuelType) {
        switch fuel {
        case .diesel: openingDiesel = value
        case .regular: openingRegular = value
        case .premium: openingPremium = value
        }
    }

    var title: String {
        "Corte \(shift.displayName.lowercased())"
    }
}

// MARK: - Pump sale (movement 1: sales)

/// Sales of one pump in one cut, for the three fuels.
@Model
final class PumpSale {
    var pumpNumber: Int
    var isOutOfService: Bool
    var dieselGallons: Double
    var dieselAmount: Double
    var regularGallons: Double
    var regularAmount: Double
    var premiumGallons: Double
    var premiumAmount: Double
    var recordedAt: Date
    var cut: SalesCut?

    init(pumpNumber: Int, recordedAt: Date = .now) {
        self.pumpNumber = pumpNumber
        self.isOutOfService = false
        self.dieselGallons = 0
        self.dieselAmount = 0
        self.regularGallons = 0
        self.regularAmount = 0
        self.premiumGallons = 0
        self.premiumAmount = 0
        self.recordedAt = recordedAt
    }

    func gallons(_ fuel: FuelType) -> Double {
        switch fuel {
        case .diesel: return dieselGallons
        case .regular: return regularGallons
        case .premium: return premiumGallons
        }
    }

    func amount(_ fuel: FuelType) -> Double {
        switch fuel {
        case .diesel: return dieselAmount
        case .regular: return regularAmount
        case .premium: return premiumAmount
        }
    }

    func setValues(gallons: Double, amount: Double, for fuel: FuelType) {
        switch fuel {
        case .diesel:
            dieselGallons = gallons
            dieselAmount = amount
        case .regular:
            regularGallons = gallons
            regularAmount = amount
        case .premium:
            premiumGallons = gallons
            premiumAmount = amount
        }
    }

    var totalAmount: Double {
        FuelType.allCases.reduce(0) { $0 + amount($1) }
    }

    var totalGallons: Double {
        FuelType.allCases.reduce(0) { $0 + gallons($1) }
    }
}

// MARK: - Fuel reception (movement 2: purchases)

@Model
final class FuelReception {
    var fuelRaw: String
    var gallons: Double
    var costPerGallon: Double
    var supplier: String
    var invoiceNumber: String
    var receivedAt: Date
    var cut: SalesCut?

    init(fuel: FuelType, gallons: Double, costPerGallon: Double, supplier: String, invoiceNumber: String, receivedAt: Date = .now) {
        self.fuelRaw = fuel.rawValue
        self.gallons = gallons
        self.costPerGallon = costPerGallon
        self.supplier = supplier
        self.invoiceNumber = invoiceNumber
        self.receivedAt = receivedAt
    }

    var fuel: FuelType {
        FuelType(rawValue: fuelRaw) ?? .regular
    }

    var total: Double {
        gallons * costPerGallon
    }
}

// MARK: - Fuel loss (movement 3: losses or damage)

@Model
final class FuelLoss {
    var typeRaw: String
    var fuelRaw: String
    var gallons: Double
    var costPerGallon: Double
    /// Pump where it happened; nil means the storage tank.
    var pumpNumber: Int?
    var details: String
    var recordedAt: Date
    var cut: SalesCut?

    init(type: LossType, fuel: FuelType, gallons: Double, pumpNumber: Int?, details: String, recordedAt: Date = .now) {
        self.typeRaw = type.rawValue
        self.fuelRaw = fuel.rawValue
        self.gallons = gallons
        self.costPerGallon = fuel.referenceCost
        self.pumpNumber = pumpNumber
        self.details = details
        self.recordedAt = recordedAt
    }

    var type: LossType {
        LossType(rawValue: typeRaw) ?? .shrinkage
    }

    var fuel: FuelType {
        FuelType(rawValue: fuelRaw) ?? .regular
    }

    var estimatedCost: Double {
        gallons * costPerGallon
    }

    var originText: String {
        pumpNumber.map { "Bomba \($0)" } ?? "Tanque \(fuel.displayName)"
    }
}
