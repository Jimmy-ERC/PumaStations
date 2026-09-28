import Foundation
import SwiftData

// MARK: - User

@Model
final class UserAccount {
    var firstName: String
    var lastName: String
    var email: String
    var passwordHash: String
    var roleRaw: String
    var dui: String
    var phone: String
    var isActive: Bool
    var createdAt: Date
    /// Only used by branch managers: the branch they are linked to.
    @Relationship(deleteRule: .nullify)
    var branch: Branch?

    init(
        firstName: String,
        lastName: String,
        email: String,
        passwordHash: String,
        role: UserRole,
        dui: String = "",
        phone: String = "",
        isActive: Bool = true,
        createdAt: Date = .now
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.passwordHash = passwordHash
        self.roleRaw = role.rawValue
        self.dui = dui
        self.phone = phone
        self.isActive = isActive
        self.createdAt = createdAt
    }

    var role: UserRole {
        UserRole(rawValue: roleRaw) ?? .branchManager
    }

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    var initials: String {
        let first = firstName.first.map { String($0) } ?? ""
        let last = lastName.first.map { String($0) } ?? ""
        return (first + last).uppercased()
    }
}

// MARK: - Branch (service station)

@Model
final class Branch {
    var name: String
    var code: String
    var address: String
    var municipality: String
    var phone: String
    var createdAt: Date

    var dieselCapacity: Double
    var regularCapacity: Double
    var premiumCapacity: Double
    var dieselStock: Double
    var regularStock: Double
    var premiumStock: Double

    @Relationship(deleteRule: .cascade, inverse: \Pump.branch)
    var pumps: [Pump] = []

    @Relationship(deleteRule: .cascade, inverse: \SalesCut.branch)
    var cuts: [SalesCut] = []

    init(
        name: String,
        code: String,
        address: String,
        municipality: String,
        phone: String = "",
        dieselCapacity: Double,
        regularCapacity: Double,
        premiumCapacity: Double,
        createdAt: Date = .now
    ) {
        self.name = name
        self.code = code
        self.address = address
        self.municipality = municipality
        self.phone = phone
        self.createdAt = createdAt
        self.dieselCapacity = dieselCapacity
        self.regularCapacity = regularCapacity
        self.premiumCapacity = premiumCapacity
        self.dieselStock = 0
        self.regularStock = 0
        self.premiumStock = 0
    }

    func capacity(for fuel: FuelType) -> Double {
        switch fuel {
        case .diesel: return dieselCapacity
        case .regular: return regularCapacity
        case .premium: return premiumCapacity
        }
    }

    func stock(for fuel: FuelType) -> Double {
        switch fuel {
        case .diesel: return dieselStock
        case .regular: return regularStock
        case .premium: return premiumStock
        }
    }

    func setStock(_ value: Double, for fuel: FuelType) {
        switch fuel {
        case .diesel: dieselStock = value
        case .regular: regularStock = value
        case .premium: premiumStock = value
        }
    }

    var sortedPumps: [Pump] {
        pumps.sorted { $0.number < $1.number }
    }

    var closedCuts: [SalesCut] {
        cuts.filter { $0.isClosed }
    }

    /// Cut of a given day and shift, if it was already started.
    func cut(on day: Date, shift: CutShift) -> SalesCut? {
        let calendar = AppCalendar.calendar
        return cuts.first { $0.shift == shift && calendar.isDate($0.day, inSameDayAs: day) }
    }
}

// MARK: - Pump

/// Multi-product dispenser: each pump dispenses Diésel, Regular and Súper.
@Model
final class Pump {
    var number: Int
    var branch: Branch?

    init(number: Int) {
        self.number = number
    }

    var displayName: String {
        "Bomba \(number)"
    }
}
