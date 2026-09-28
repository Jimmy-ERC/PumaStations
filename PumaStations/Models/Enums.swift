import SwiftUI

/// Business rules fixed by the project specification.
enum BusinessRules {
    /// Every branch has exactly 6 fuel pumps.
    static let pumpsPerBranch = 6
    /// Two sales cuts per day (morning and evening).
    static let cutsPerDay = 2
    /// Days used to compute the average daily sales of a tank.
    static let averageWindowDays = 7
}

// MARK: - Fuel

/// The three fuels sold in El Salvador: Súper, Regular and Diésel.
enum FuelType: String, CaseIterable, Identifiable, Codable {
    case diesel
    case regular
    /// Sold in El Salvador as "Súper" (`super` is a reserved word in Swift).
    case premium

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .diesel: return "Diésel"
        case .regular: return "Regular"
        case .premium: return "Súper"
        }
    }

    var shortName: String {
        switch self {
        case .diesel: return "D"
        case .regular: return "R"
        case .premium: return "S"
        }
    }

    var color: Color {
        switch self {
        case .diesel: return .dieselGray
        case .regular: return .brandGreen
        case .premium: return .brandRed
        }
    }

    /// Reference sale price per gallon (pre-fills the amount of a pump sale).
    var referenceSalePrice: Double {
        switch self {
        case .diesel: return 3.84
        case .regular: return 3.88
        case .premium: return 4.19
        }
    }

    /// Reference purchase cost per gallon (pre-fills receptions and values losses).
    var referenceCost: Double {
        switch self {
        case .diesel: return 3.10
        case .regular: return 2.95
        case .premium: return 3.31
        }
    }
}

// MARK: - Roles

enum UserRole: String, Codable {
    case generalManager
    case branchManager

    var displayName: String {
        switch self {
        case .generalManager: return "Gerente general"
        case .branchManager: return "Gerente de sucursal"
        }
    }
}

// MARK: - Cuts

enum CutShift: Int, CaseIterable, Identifiable, Codable {
    case morning = 1
    case evening = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .morning: return "Matutino"
        case .evening: return "Vespertino"
        }
    }

    var title: String {
        "Corte \(rawValue) · \(displayName)"
    }

    var hoursText: String {
        switch self {
        case .morning: return "6:00 a. m. – 2:00 p. m."
        case .evening: return "2:00 p. m. – 10:00 p. m."
        }
    }

    /// Hour used to place the cut on a timeline (for charts and period filters).
    var referenceHour: Int {
        switch self {
        case .morning: return 10
        case .evening: return 18
        }
    }
}

enum CutStatus: String, Codable {
    case open
    case closed

    var displayName: String {
        switch self {
        case .open: return "En proceso"
        case .closed: return "Cerrado"
        }
    }
}

// MARK: - Losses

enum LossType: String, CaseIterable, Identifiable, Codable {
    case shrinkage
    case leak
    case technicalFailure
    case spill

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shrinkage: return "Merma"
        case .leak: return "Fuga"
        case .technicalFailure: return "Falla técnica"
        case .spill: return "Derrame"
        }
    }
}

// MARK: - Tank status (business intelligence alert)

enum TankStatus: Int, Comparable {
    case critical = 0
    case medium = 1
    case optimal = 2

    static func < (lhs: TankStatus, rhs: TankStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Critical: < 20 % or < 1.5 days of sales. Medium: < 40 % or < 3 days. Optimal: otherwise.
    static func evaluate(ratio: Double, daysLeft: Double?) -> TankStatus {
        let days = daysLeft ?? .infinity
        if ratio < 0.20 || days < 1.5 { return .critical }
        if ratio < 0.40 || days < 3 { return .medium }
        return .optimal
    }

    var displayName: String {
        switch self {
        case .critical: return "Crítico"
        case .medium: return "Medio"
        case .optimal: return "Óptimo"
        }
    }

    var color: Color {
        switch self {
        case .critical: return .brandRed
        case .medium: return .warningAmber
        case .optimal: return .brandGreen
        }
    }

    var systemImage: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .medium: return "clock.fill"
        case .optimal: return "checkmark"
        }
    }

    static let legend = "Crítico: < 20 % o < 1.5 días de venta · Medio: < 40 % o < 3 días · Óptimo: el resto. Los días se estiman con el promedio de venta de los últimos 7 días."
}
