import Foundation

/// Table names of the Supabase database (see `supabase/schema.sql`).
enum RemoteTable {
    static let profiles = "profiles"
    static let branches = "branches"
    static let pumps = "pumps"
    static let salesCuts = "sales_cuts"
    static let pumpSales = "pump_sales"
    static let fuelReceptions = "fuel_receptions"
    static let fuelLosses = "fuel_losses"
    static let workShifts = "work_shifts"
    static let catalogItems = "catalog_items"
    static let stockEntries = "stock_entries"
    static let sales = "sales"
    static let saleItems = "sale_items"
}

// MARK: - Rows (one struct per table)

struct ProfileRecord: Codable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let email: String
    let role: String
    let dui: String
    let phone: String
    let isActive: Bool
    let createdAt: Date
    let branchID: UUID?
    let jobTitle: String

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case role
        case dui
        case phone
        case isActive = "is_active"
        case createdAt = "created_at"
        case branchID = "branch_id"
        case jobTitle = "job_title"
    }
}

struct BranchRecord: Codable, Sendable {
    let id: UUID
    let name: String
    let code: String
    let address: String
    let municipality: String
    let phone: String
    let createdAt: Date
    let dieselCapacity: Double
    let regularCapacity: Double
    let premiumCapacity: Double
    let dieselStock: Double
    let regularStock: Double
    let premiumStock: Double

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case code
        case address
        case municipality
        case phone
        case createdAt = "created_at"
        case dieselCapacity = "diesel_capacity"
        case regularCapacity = "regular_capacity"
        case premiumCapacity = "premium_capacity"
        case dieselStock = "diesel_stock"
        case regularStock = "regular_stock"
        case premiumStock = "premium_stock"
    }
}

struct PumpRecord: Codable, Sendable {
    let id: UUID
    let branchID: UUID
    let number: Int

    enum CodingKeys: String, CodingKey {
        case id
        case branchID = "branch_id"
        case number
    }
}

struct SalesCutRecord: Codable, Sendable {
    let id: UUID
    let branchID: UUID
    /// Calendar day as `yyyy-MM-dd`.
    let day: String
    let shift: Int
    let status: String
    let openedAt: Date
    let closedAt: Date?
    let openingDiesel: Double
    let openingRegular: Double
    let openingPremium: Double

    enum CodingKeys: String, CodingKey {
        case id
        case branchID = "branch_id"
        case day
        case shift
        case status
        case openedAt = "opened_at"
        case closedAt = "closed_at"
        case openingDiesel = "opening_diesel"
        case openingRegular = "opening_regular"
        case openingPremium = "opening_premium"
    }

    /// `closed_at` is always sent (as null when missing) so every row of a bulk insert has the same keys.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(branchID, forKey: .branchID)
        try container.encode(day, forKey: .day)
        try container.encode(shift, forKey: .shift)
        try container.encode(status, forKey: .status)
        try container.encode(openedAt, forKey: .openedAt)
        try container.encode(closedAt, forKey: .closedAt)
        try container.encode(openingDiesel, forKey: .openingDiesel)
        try container.encode(openingRegular, forKey: .openingRegular)
        try container.encode(openingPremium, forKey: .openingPremium)
    }
}

struct PumpSaleRecord: Codable, Sendable {
    let id: UUID
    let cutID: UUID
    let pumpNumber: Int
    let isOutOfService: Bool
    let dieselGallons: Double
    let dieselAmount: Double
    let regularGallons: Double
    let regularAmount: Double
    let premiumGallons: Double
    let premiumAmount: Double
    let recordedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case cutID = "cut_id"
        case pumpNumber = "pump_number"
        case isOutOfService = "is_out_of_service"
        case dieselGallons = "diesel_gallons"
        case dieselAmount = "diesel_amount"
        case regularGallons = "regular_gallons"
        case regularAmount = "regular_amount"
        case premiumGallons = "premium_gallons"
        case premiumAmount = "premium_amount"
        case recordedAt = "recorded_at"
    }
}

struct FuelReceptionRecord: Codable, Sendable {
    let id: UUID
    let cutID: UUID
    let fuel: String
    let gallons: Double
    let costPerGallon: Double
    let supplier: String
    let invoiceNumber: String
    let receivedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case cutID = "cut_id"
        case fuel
        case gallons
        case costPerGallon = "cost_per_gallon"
        case supplier
        case invoiceNumber = "invoice_number"
        case receivedAt = "received_at"
    }
}

struct FuelLossRecord: Codable, Sendable {
    let id: UUID
    let cutID: UUID
    let type: String
    let fuel: String
    let gallons: Double
    let costPerGallon: Double
    let pumpNumber: Int?
    let details: String
    let recordedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case cutID = "cut_id"
        case type
        case fuel
        case gallons
        case costPerGallon = "cost_per_gallon"
        case pumpNumber = "pump_number"
        case details
        case recordedAt = "recorded_at"
    }

    /// `pump_number` is always sent (as null for the storage tank) so every row of a bulk insert has the same keys.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(cutID, forKey: .cutID)
        try container.encode(type, forKey: .type)
        try container.encode(fuel, forKey: .fuel)
        try container.encode(gallons, forKey: .gallons)
        try container.encode(costPerGallon, forKey: .costPerGallon)
        try container.encode(pumpNumber, forKey: .pumpNumber)
        try container.encode(details, forKey: .details)
        try container.encode(recordedAt, forKey: .recordedAt)
    }
}

struct WorkShiftRecord: Codable, Sendable {
    let id: UUID
    let branchID: UUID
    let employeeID: UUID
    /// Calendar day as `yyyy-MM-dd`.
    let day: String
    let shift: Int
    let checkInAt: Date?
    let checkOutAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case branchID = "branch_id"
        case employeeID = "employee_id"
        case day
        case shift
        case checkInAt = "check_in_at"
        case checkOutAt = "check_out_at"
    }

    /// The marks are always sent (as null when missing) so every row of a bulk insert has the same keys.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(branchID, forKey: .branchID)
        try container.encode(employeeID, forKey: .employeeID)
        try container.encode(day, forKey: .day)
        try container.encode(shift, forKey: .shift)
        try container.encode(checkInAt, forKey: .checkInAt)
        try container.encode(checkOutAt, forKey: .checkOutAt)
    }
}

struct CatalogItemRecord: Codable, Sendable {
    let id: UUID
    let name: String
    let category: String
    let detail: String
    let price: Double
    let minStock: Int
    let isActive: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case detail
        case price
        case minStock = "min_stock"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

struct StockEntryRecord: Codable, Sendable {
    let id: UUID
    let branchID: UUID
    let itemID: UUID
    let quantity: Int
    let unitCost: Double
    let note: String
    let receivedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case branchID = "branch_id"
        case itemID = "item_id"
        case quantity
        case unitCost = "unit_cost"
        case note
        case receivedAt = "received_at"
    }
}

struct SaleRecord: Codable, Sendable {
    let id: UUID
    let branchID: UUID
    /// nil when the account of the seller was deleted.
    let sellerID: UUID?
    let kind: String
    let paymentMethod: String
    let vehiclePlate: String
    let soldAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case branchID = "branch_id"
        case sellerID = "seller_id"
        case kind
        case paymentMethod = "payment_method"
        case vehiclePlate = "vehicle_plate"
        case soldAt = "sold_at"
    }

    /// `seller_id` is always sent so every row of a bulk insert has the same keys.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(branchID, forKey: .branchID)
        try container.encode(sellerID, forKey: .sellerID)
        try container.encode(kind, forKey: .kind)
        try container.encode(paymentMethod, forKey: .paymentMethod)
        try container.encode(vehiclePlate, forKey: .vehiclePlate)
        try container.encode(soldAt, forKey: .soldAt)
    }
}

struct SaleItemRecord: Codable, Sendable {
    let id: UUID
    let saleID: UUID
    let itemID: UUID
    let quantity: Int
    let unitPrice: Double

    enum CodingKeys: String, CodingKey {
        case id
        case saleID = "sale_id"
        case itemID = "item_id"
        case quantity
        case unitPrice = "unit_price"
    }
}

// MARK: - Function parameters

/// Arguments of the `save_manager` database function: creates or updates a branch manager.
struct SaveManagerParams: Encodable, Sendable {
    let id: UUID
    let email: String
    /// nil keeps the current password (only valid when the manager already exists).
    let password: String?
    let firstName: String
    let lastName: String
    let dui: String
    let phone: String
    let isActive: Bool
    let branchID: UUID?

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case email = "p_email"
        case password = "p_password"
        case firstName = "p_first_name"
        case lastName = "p_last_name"
        case dui = "p_dui"
        case phone = "p_phone"
        case isActive = "p_is_active"
        case branchID = "p_branch_id"
    }

    /// Every argument must be present in the request, so nil values are sent as null.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(email, forKey: .email)
        try container.encode(password, forKey: .password)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try container.encode(dui, forKey: .dui)
        try container.encode(phone, forKey: .phone)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(branchID, forKey: .branchID)
    }
}

/// Arguments of the `save_employee` database function: creates or updates an employee
/// of the branch of the manager who calls it.
struct SaveEmployeeParams: Encodable, Sendable {
    let id: UUID
    let email: String
    /// nil keeps the current password (only valid when the employee already exists).
    let password: String?
    let firstName: String
    let lastName: String
    let dui: String
    let phone: String
    let jobTitle: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case email = "p_email"
        case password = "p_password"
        case firstName = "p_first_name"
        case lastName = "p_last_name"
        case dui = "p_dui"
        case phone = "p_phone"
        case jobTitle = "p_job_title"
        case isActive = "p_is_active"
    }

    /// Every argument must be present in the request, so nil values are sent as null.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(email, forKey: .email)
        try container.encode(password, forKey: .password)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try container.encode(dui, forKey: .dui)
        try container.encode(phone, forKey: .phone)
        try container.encode(jobTitle, forKey: .jobTitle)
        try container.encode(isActive, forKey: .isActive)
    }
}

// MARK: - Snapshot

/// Everything the logged-in user is allowed to see, as returned by the server.
struct RemoteSnapshot: Sendable {
    var profiles: [ProfileRecord] = []
    var branches: [BranchRecord] = []
    var pumps: [PumpRecord] = []
    var cuts: [SalesCutRecord] = []
    var pumpSales: [PumpSaleRecord] = []
    var receptions: [FuelReceptionRecord] = []
    var losses: [FuelLossRecord] = []
    var workShifts: [WorkShiftRecord] = []
    var catalogItems: [CatalogItemRecord] = []
    var stockEntries: [StockEntryRecord] = []
    var sales: [SaleRecord] = []
    var saleItems: [SaleItemRecord] = []
}
