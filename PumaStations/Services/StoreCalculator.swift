import Foundation

// MARK: - Results

/// Units of one product in the store of a branch.
struct StockLevel: Identifiable {
    let item: CatalogItem
    let received: Int
    let sold: Int

    var id: UUID { item.remoteID }

    /// Stock = entries − units sold.
    var available: Int { received - sold }

    var status: StockStatus {
        StockStatus.evaluate(available: available, minimum: item.minStock)
    }
}

struct CategorySalesRow: Identifiable {
    let category: CatalogCategory
    var units = 0
    var amount: Double = 0

    var id: String { category.rawValue }
}

struct ItemSalesRow: Identifiable {
    let id: UUID
    let name: String
    let category: CatalogCategory
    var units = 0
    var amount: Double = 0
}

struct SellerSalesRow: Identifiable {
    let id: UUID
    let name: String
    var tickets = 0
    var amount: Double = 0
}

/// Store and maintenance sales of a period.
struct StoreMetrics {
    var tickets = 0
    var categories: [CategorySalesRow] = CatalogCategory.allCases.map { CategorySalesRow(category: $0) }
    var topItems: [ItemSalesRow] = []
    var sellers: [SellerSalesRow] = []
    var previousTotal: Double = 0

    func amount(_ category: CatalogCategory) -> Double {
        categories.first { $0.category == category }?.amount ?? 0
    }

    /// Convenience products + lubricants.
    var storeTotal: Double {
        CatalogCategory.products.reduce(0) { $0 + amount($1) }
    }

    var serviceTotal: Double {
        amount(.service)
    }

    var total: Double {
        categories.reduce(0) { $0 + $1.amount }
    }

    var averageTicket: Double {
        tickets > 0 ? total / Double(tickets) : 0
    }

    /// Relative change of sales against the previous period (nil when not comparable).
    var change: Double? {
        guard previousTotal > 0 else { return nil }
        return (total - previousTotal) / previousTotal
    }

    static let empty = StoreMetrics()
}

// MARK: - Calculator

/// Pure business logic of the store: inventory per product and sales metrics.
enum StoreCalculator {

    /// Stock of every active product of the catalog in one branch.
    static func stockLevels(items: [CatalogItem], entries: [StockEntry], sales: [Sale]) -> [StockLevel] {
        var received: [UUID: Int] = [:]
        for entry in entries {
            guard let item = entry.item else { continue }
            received[item.remoteID, default: 0] += entry.quantity
        }
        var sold: [UUID: Int] = [:]
        for line in sales.flatMap(\.items) {
            guard let item = line.item else { continue }
            sold[item.remoteID, default: 0] += line.quantity
        }
        return items
            .filter { $0.tracksStock && ($0.isActive || (received[$0.remoteID] ?? 0) > 0) }
            .map { StockLevel(item: $0, received: received[$0.remoteID] ?? 0, sold: sold[$0.remoteID] ?? 0) }
    }

    /// Products that need restocking, the most urgent first.
    static func alerts(in levels: [StockLevel]) -> [StockLevel] {
        levels
            .filter { $0.status != .available && $0.item.isActive }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status < rhs.status }
                return lhs.available < rhs.available
            }
    }

    static func compute(sales: [Sale], range: DateRange) -> StoreMetrics {
        var metrics = StoreMetrics()
        var items: [UUID: ItemSalesRow] = [:]
        var sellers: [UUID: SellerSalesRow] = [:]

        for sale in sales where range.contains(sale.soldAt) {
            metrics.tickets += 1
            if let seller = sale.seller {
                var row = sellers[seller.remoteID] ?? SellerSalesRow(id: seller.remoteID, name: seller.fullName)
                row.tickets += 1
                row.amount += sale.total
                sellers[seller.remoteID] = row
            }
            for line in sale.items {
                guard let item = line.item else { continue }
                if let index = metrics.categories.firstIndex(where: { $0.category == item.category }) {
                    metrics.categories[index].units += line.quantity
                    metrics.categories[index].amount += line.total
                }
                var row = items[item.remoteID] ?? ItemSalesRow(id: item.remoteID, name: item.name, category: item.category)
                row.units += line.quantity
                row.amount += line.total
                items[item.remoteID] = row
            }
        }

        metrics.topItems = items.values.sorted { $0.amount > $1.amount }
        metrics.sellers = sellers.values.sorted { $0.amount > $1.amount }
        metrics.previousTotal = total(of: sales, in: range.previous)
        return metrics
    }

    static func total(of sales: [Sale], in range: DateRange) -> Double {
        sales.filter { range.contains($0.soldAt) }.reduce(0) { $0 + $1.total }
    }
}
