import Foundation
import SwiftData

enum SaleError: LocalizedError {
    case emptyCart
    case noActiveShift
    case missingPlate
    case inactiveItem(String)
    case insufficientStock(name: String, available: Int)

    var errorDescription: String? {
        switch self {
        case .emptyCart:
            return "Agrega al menos un artículo."
        case .noActiveShift:
            return "Para vender debes marcar la entrada de tu turno de hoy."
        case .missingPlate:
            return "Ingresa la placa del vehículo."
        case .inactiveItem(let name):
            return "\(name) ya no está disponible en el catálogo."
        case .insufficientStock(let name, let available):
            return available > 0
                ? "Solo quedan \(available) unidades de \(name)."
                : "\(name) está agotado."
        }
    }
}

/// One line of the cart before the sale is registered.
struct CartLine {
    let item: CatalogItem
    let quantity: Int
}

/// Rules for store sales and maintenance orders.
enum SaleService {

    /// Registers the sale with the catalog prices of the moment. Products are discounted from the
    /// store inventory of the branch (stock = entries − units sold); services have no inventory.
    @discardableResult
    static func register(
        kind: SaleKind,
        lines: [CartLine],
        payment: PaymentMethod,
        vehiclePlate: String = "",
        seller: UserAccount,
        branch: Branch,
        store: DataStore,
        at date: Date = .now
    ) throws -> Sale {
        let lines = lines.filter { $0.quantity > 0 }
        guard !lines.isEmpty else { throw SaleError.emptyCart }
        guard ShiftService.activeShift(of: seller, store: store) != nil else { throw SaleError.noActiveShift }
        if kind == .service && vehiclePlate.trimmed.isEmpty { throw SaleError.missingPlate }

        let levels = StoreCalculator.stockLevels(
            items: lines.map(\.item),
            entries: store.stockEntries(of: branch),
            sales: store.sales(of: branch)
        )
        for line in lines {
            guard line.item.isActive else { throw SaleError.inactiveItem(line.item.name) }
            guard line.item.tracksStock else { continue }
            let available = levels.first { $0.id == line.item.remoteID }?.available ?? 0
            guard line.quantity <= available else {
                throw SaleError.insufficientStock(name: line.item.name, available: available)
            }
        }

        let sale = Sale(kind: kind, payment: payment, vehiclePlate: vehiclePlate.trimmed.uppercased(), soldAt: date)
        store.insert(sale)
        sale.branch = branch
        sale.seller = seller
        for line in lines {
            let saleItem = SaleItem(quantity: line.quantity, unitPrice: line.item.price)
            store.insert(saleItem)
            saleItem.sale = sale
            saleItem.item = line.item
        }
        try store.save()
        return sale
    }
}
