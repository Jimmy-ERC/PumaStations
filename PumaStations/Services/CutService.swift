import Foundation
import SwiftData

enum CutError: LocalizedError {
    case alreadyStarted
    case previousCutOpen
    case missingPumps(Int)
    case alreadyClosed
    case negativeStock(FuelType)
    case overCapacity(FuelType)

    var errorDescription: String? {
        switch self {
        case .alreadyStarted:
            return "Este corte ya fue iniciado."
        case .previousCutOpen:
            return "Primero cierra el corte matutino."
        case .missingPumps(let missing):
            return missing == 1 ? "Falta registrar 1 bomba." : "Faltan registrar \(missing) bombas."
        case .alreadyClosed:
            return "El corte ya está cerrado."
        case .negativeStock(let fuel):
            return "La existencia de \(fuel.displayName) quedaría negativa. Revisa ventas, recepciones y pérdidas."
        case .overCapacity(let fuel):
            return "La existencia de \(fuel.displayName) superaría la capacidad del tanque."
        }
    }
}

/// Rules for the 2 daily cuts and the 6 pumps.
enum CutService {

    /// The evening cut can start only after the morning cut of the same day is closed.
    static func canStart(_ shift: CutShift, in branch: Branch, on day: Date = .now) -> Bool {
        guard branch.cut(on: day, shift: shift) == nil else { return false }
        switch shift {
        case .morning:
            return true
        case .evening:
            return branch.cut(on: day, shift: .morning)?.isClosed == true
        }
    }

    static func start(_ shift: CutShift, in branch: Branch, on day: Date = .now, store: DataStore) throws -> SalesCut {
        guard branch.cut(on: day, shift: shift) == nil else { throw CutError.alreadyStarted }
        guard canStart(shift, in: branch, on: day) else { throw CutError.previousCutOpen }
        let cut = SalesCut(day: day, shift: shift)
        store.insert(cut)
        cut.branch = branch
        try store.save()
        return cut
    }

    /// Validates the cut and returns the stock each tank will have after closing it.
    static func closingStock(of cut: SalesCut, in branch: Branch) throws -> [FuelType: Double] {
        guard !cut.isClosed else { throw CutError.alreadyClosed }
        guard cut.isReadyToClose else {
            throw CutError.missingPumps(BusinessRules.pumpsPerBranch - cut.registeredPumpCount)
        }
        var result: [FuelType: Double] = [:]
        for fuel in FuelType.allCases {
            let final = branch.stock(for: fuel) + cut.netMovement(fuel)
            if final < -0.001 { throw CutError.negativeStock(fuel) }
            if final > branch.capacity(for: fuel) + 0.001 { throw CutError.overCapacity(fuel) }
            result[fuel] = max(final, 0)
        }
        return result
    }

    /// Consolidates the 6 pump records: stores the opening stock, updates the tanks and locks the cut.
    static func close(_ cut: SalesCut, in branch: Branch, store: DataStore, at date: Date = .now) throws {
        let finalStock = try closingStock(of: cut, in: branch)
        for fuel in FuelType.allCases {
            cut.setOpeningStock(branch.stock(for: fuel), for: fuel)
            branch.setStock(finalStock[fuel] ?? 0, for: fuel)
        }
        cut.statusRaw = CutStatus.closed.rawValue
        cut.closedAt = date
        try store.save()
    }
}
