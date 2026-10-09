import Foundation
import SwiftData

// MARK: - Catalog item

/// A product (convenience or lubricant) or a maintenance service of the franchise catalog.
/// The general manager defines it once; every branch sells it at the same price.
@Model
final class CatalogItem {
    /// Id of the row in Supabase.
    var remoteID: UUID = UUID()
    var name: String
    var categoryRaw: String
    /// Presentation of a product or what a service includes.
    var detail: String
    var price: Double
    /// Units a branch should keep before the low stock alert (not used by services).
    var minStock: Int
    var isActive: Bool
    var createdAt: Date

    init(
        name: String,
        category: CatalogCategory,
        detail: String = "",
        price: Double,
        minStock: Int = 0,
        isActive: Bool = true,
        createdAt: Date = .now
    ) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.detail = detail
        self.price = price
        self.minStock = minStock
        self.isActive = isActive
        self.createdAt = createdAt
    }

    var category: CatalogCategory {
        CatalogCategory(rawValue: categoryRaw) ?? .convenience
    }

    var tracksStock: Bool {
        category.tracksStock
    }
}

// MARK: - Stock entry

/// Units of a product received by a branch store. Stock = entries − units sold.
@Model
final class StockEntry {
    /// Id of the row in Supabase.
    var remoteID: UUID = UUID()
    var quantity: Int
    var unitCost: Double
    var note: String
    var receivedAt: Date

    @Relationship(deleteRule: .nullify)
    var branch: Branch?
    @Relationship(deleteRule: .nullify)
    var item: CatalogItem?

    init(quantity: Int, unitCost: Double, note: String = "", receivedAt: Date = .now) {
        self.quantity = quantity
        self.unitCost = unitCost
        self.note = note
        self.receivedAt = receivedAt
    }

    var total: Double {
        Double(quantity) * unitCost
    }
}

// MARK: - Sale

/// A store ticket or a maintenance order registered by an employee.
@Model
final class Sale {
    /// Id of the row in Supabase.
    var remoteID: UUID = UUID()
    var kindRaw: String
    var paymentRaw: String
    /// Only used by maintenance orders.
    var vehiclePlate: String
    var soldAt: Date

    @Relationship(deleteRule: .nullify)
    var branch: Branch?
    @Relationship(deleteRule: .nullify)
    var seller: UserAccount?

    @Relationship(deleteRule: .cascade, inverse: \SaleItem.sale)
    var items: [SaleItem] = []

    init(kind: SaleKind, payment: PaymentMethod, vehiclePlate: String = "", soldAt: Date = .now) {
        self.kindRaw = kind.rawValue
        self.paymentRaw = payment.rawValue
        self.vehiclePlate = vehiclePlate
        self.soldAt = soldAt
    }

    var kind: SaleKind {
        SaleKind(rawValue: kindRaw) ?? .store
    }

    var payment: PaymentMethod {
        PaymentMethod(rawValue: paymentRaw) ?? .cash
    }

    var total: Double {
        items.reduce(0) { $0 + $1.total }
    }

    var unitCount: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    /// Names of the items sold, for list rows.
    var summary: String {
        let names = items
            .sorted { $0.total > $1.total }
            .map { line in
                let name = line.item?.name ?? "Artículo"
                return line.quantity > 1 ? "\(line.quantity) × \(name)" : name
            }
        return names.isEmpty ? "Sin artículos" : names.joined(separator: ", ")
    }
}

/// One line of a sale. The price is copied so later catalog changes do not alter past sales.
@Model
final class SaleItem {
    /// Id of the row in Supabase.
    var remoteID: UUID = UUID()
    var quantity: Int
    var unitPrice: Double
    var sale: Sale?

    @Relationship(deleteRule: .nullify)
    var item: CatalogItem?

    init(quantity: Int, unitPrice: Double) {
        self.quantity = quantity
        self.unitPrice = unitPrice
    }

    var total: Double {
        Double(quantity) * unitPrice
    }
}
