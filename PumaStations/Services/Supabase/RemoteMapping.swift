import Foundation
import SwiftData

/// Conversion between the calendar day of a cut and the `date` column (`yyyy-MM-dd`).
enum RemoteDay {
    static func string(from date: Date) -> String {
        let parts = AppCalendar.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return AppCalendar.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

// MARK: - SwiftData models <-> Supabase rows

extension UserAccount {
    convenience init(record: ProfileRecord) {
        self.init(
            firstName: record.firstName,
            lastName: record.lastName,
            email: record.email,
            role: UserRole(rawValue: record.role) ?? .branchManager,
            dui: record.dui,
            phone: record.phone,
            isActive: record.isActive,
            createdAt: record.createdAt
        )
        remoteID = record.id
    }

    func saveParams(password: String?) -> SaveManagerParams {
        SaveManagerParams(
            id: remoteID,
            email: email,
            password: password,
            firstName: firstName,
            lastName: lastName,
            dui: dui,
            phone: phone,
            isActive: isActive,
            branchID: branch?.remoteID
        )
    }
}

extension Branch {
    convenience init(record: BranchRecord) {
        self.init(
            name: record.name,
            code: record.code,
            address: record.address,
            municipality: record.municipality,
            phone: record.phone,
            dieselCapacity: record.dieselCapacity,
            regularCapacity: record.regularCapacity,
            premiumCapacity: record.premiumCapacity,
            createdAt: record.createdAt
        )
        remoteID = record.id
        dieselStock = record.dieselStock
        regularStock = record.regularStock
        premiumStock = record.premiumStock
    }

    var record: BranchRecord {
        BranchRecord(
            id: remoteID,
            name: name,
            code: code,
            address: address,
            municipality: municipality,
            phone: phone,
            createdAt: createdAt,
            dieselCapacity: dieselCapacity,
            regularCapacity: regularCapacity,
            premiumCapacity: premiumCapacity,
            dieselStock: dieselStock,
            regularStock: regularStock,
            premiumStock: premiumStock
        )
    }
}

extension Pump {
    /// nil while the pump is not linked to a branch.
    var record: PumpRecord? {
        guard let branch else { return nil }
        return PumpRecord(id: remoteID, branchID: branch.remoteID, number: number)
    }
}

extension SalesCut {
    convenience init?(record: SalesCutRecord) {
        guard let day = RemoteDay.date(from: record.day),
              let shift = CutShift(rawValue: record.shift) else { return nil }
        self.init(day: day, shift: shift, openedAt: record.openedAt)
        remoteID = record.id
        statusRaw = record.status
        closedAt = record.closedAt
        openingDiesel = record.openingDiesel
        openingRegular = record.openingRegular
        openingPremium = record.openingPremium
    }

    var record: SalesCutRecord? {
        guard let branch else { return nil }
        return SalesCutRecord(
            id: remoteID,
            branchID: branch.remoteID,
            day: RemoteDay.string(from: day),
            shift: shiftRaw,
            status: statusRaw,
            openedAt: openedAt,
            closedAt: closedAt,
            openingDiesel: openingDiesel,
            openingRegular: openingRegular,
            openingPremium: openingPremium
        )
    }
}

extension PumpSale {
    convenience init(record: PumpSaleRecord) {
        self.init(pumpNumber: record.pumpNumber, recordedAt: record.recordedAt)
        remoteID = record.id
        isOutOfService = record.isOutOfService
        dieselGallons = record.dieselGallons
        dieselAmount = record.dieselAmount
        regularGallons = record.regularGallons
        regularAmount = record.regularAmount
        premiumGallons = record.premiumGallons
        premiumAmount = record.premiumAmount
    }

    var record: PumpSaleRecord? {
        guard let cut else { return nil }
        return PumpSaleRecord(
            id: remoteID,
            cutID: cut.remoteID,
            pumpNumber: pumpNumber,
            isOutOfService: isOutOfService,
            dieselGallons: dieselGallons,
            dieselAmount: dieselAmount,
            regularGallons: regularGallons,
            regularAmount: regularAmount,
            premiumGallons: premiumGallons,
            premiumAmount: premiumAmount,
            recordedAt: recordedAt
        )
    }
}

extension FuelReception {
    convenience init(record: FuelReceptionRecord) {
        self.init(
            fuel: FuelType(rawValue: record.fuel) ?? .regular,
            gallons: record.gallons,
            costPerGallon: record.costPerGallon,
            supplier: record.supplier,
            invoiceNumber: record.invoiceNumber,
            receivedAt: record.receivedAt
        )
        remoteID = record.id
    }

    var record: FuelReceptionRecord? {
        guard let cut else { return nil }
        return FuelReceptionRecord(
            id: remoteID,
            cutID: cut.remoteID,
            fuel: fuelRaw,
            gallons: gallons,
            costPerGallon: costPerGallon,
            supplier: supplier,
            invoiceNumber: invoiceNumber,
            receivedAt: receivedAt
        )
    }
}

extension FuelLoss {
    convenience init(record: FuelLossRecord) {
        self.init(
            type: LossType(rawValue: record.type) ?? .shrinkage,
            fuel: FuelType(rawValue: record.fuel) ?? .regular,
            gallons: record.gallons,
            pumpNumber: record.pumpNumber,
            details: record.details,
            recordedAt: record.recordedAt
        )
        remoteID = record.id
        costPerGallon = record.costPerGallon
    }

    var record: FuelLossRecord? {
        guard let cut else { return nil }
        return FuelLossRecord(
            id: remoteID,
            cutID: cut.remoteID,
            type: typeRaw,
            fuel: fuelRaw,
            gallons: gallons,
            costPerGallon: costPerGallon,
            pumpNumber: pumpNumber,
            details: details,
            recordedAt: recordedAt
        )
    }
}
