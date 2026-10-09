import Foundation
import Observation
import SwiftData

// MARK: - Franchise catalog (products and services)

@Observable
final class CatalogListViewModel {
    var searchText = ""
    var category: CatalogCategory = .convenience
    private(set) var items: [CatalogItem] = []

    private let store: DataStore

    init(store: DataStore) {
        self.store = store
    }

    var filteredItems: [CatalogItem] {
        let query = searchText.trimmed
        return items.filter { item in
            item.category == category
                && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        }
    }

    func count(of category: CatalogCategory) -> Int {
        items.filter { $0.category == category && $0.isActive }.count
    }

    func load() {
        items = store.catalogItems()
    }
}

// MARK: - Catalog item form (create or edit)

@Observable
final class CatalogItemFormViewModel {
    var name = ""
    var category: CatalogCategory
    var detail = ""
    var price: Double = 0
    var minStock: Double = 6
    var isActive = true
    var errorMessage: String?

    let editingItem: CatalogItem?
    private let store: DataStore

    init(store: DataStore, category: CatalogCategory = .convenience, item: CatalogItem? = nil) {
        self.store = store
        self.category = category
        self.editingItem = item
        if let item {
            name = item.name
            self.category = item.category
            detail = item.detail
            price = item.price
            minStock = Double(item.minStock)
            isActive = item.isActive
        }
    }

    var isEditing: Bool { editingItem != nil }

    var title: String {
        if isEditing { return category == .service ? "Editar servicio" : "Editar producto" }
        return category == .service ? "Nuevo servicio" : "Nuevo producto"
    }

    var canSave: Bool {
        !name.trimmed.isEmpty && price > 0
    }

    func save() -> Bool {
        guard !name.trimmed.isEmpty else {
            errorMessage = "Ingresa el nombre."
            return false
        }
        guard price > 0 else {
            errorMessage = "El precio debe ser mayor que 0."
            return false
        }
        guard minStock >= 0 else {
            errorMessage = "La existencia mínima no puede ser negativa."
            return false
        }
        guard !store.isCatalogNameTaken(name, excluding: editingItem) else {
            errorMessage = "Ya existe un artículo con ese nombre."
            return false
        }

        let minimum = category.tracksStock ? Int(minStock.rounded()) : 0
        if let editingItem {
            // The category is fixed after creation: past sales and inventory depend on it.
            editingItem.name = name.trimmed
            editingItem.detail = detail.trimmed
            editingItem.price = price.rounded(toPlaces: 2)
            editingItem.minStock = minimum
            editingItem.isActive = isActive
        } else {
            let item = CatalogItem(
                name: name.trimmed,
                category: category,
                detail: detail.trimmed,
                price: price.rounded(toPlaces: 2),
                minStock: minimum
            )
            store.insert(item)
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
