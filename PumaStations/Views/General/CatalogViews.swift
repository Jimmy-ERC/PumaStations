import SwiftUI

// MARK: - Franchise catalog

/// Products (convenience and lubricants) and maintenance services sold by every branch.
struct CatalogListView: View {
    @Environment(DataStore.self) private var store
    @State private var viewModel: CatalogListViewModel
    @State private var isShowingNewForm = false
    @State private var editingItem: CatalogItem?

    init(store: DataStore) {
        _viewModel = State(initialValue: CatalogListViewModel(store: store))
    }

    var body: some View {
        List {
            Section {
                Picker("Categoría", selection: $viewModel.category) {
                    ForEach(CatalogCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                if viewModel.filteredItems.isEmpty {
                    Text("No hay artículos en esta categoría.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.filteredItems) { item in
                    Button {
                        editingItem = item
                    } label: {
                        CatalogRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(viewModel.count(of: viewModel.category) == 1 ? "1 activo" : "\(viewModel.count(of: viewModel.category)) activos")
            } footer: {
                Text(viewModel.category == .service
                     ? "Los servicios de mantenimiento no llevan inventario. El precio aplica a todas las sucursales."
                     : "El precio aplica a todas las sucursales. Cada sucursal lleva su propia existencia y recibe un aviso al llegar al mínimo.")
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Buscar en el catálogo")
        .navigationTitle("Catálogo")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingNewForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nuevo artículo")
            }
        }
        .sheet(isPresented: $isShowingNewForm, onDismiss: { viewModel.load() }) {
            CatalogItemFormView(store: store, category: viewModel.category)
        }
        .sheet(item: $editingItem, onDismiss: { viewModel.load() }) { item in
            CatalogItemFormView(store: store, item: item)
        }
        .onAppear { viewModel.load() }
    }
}

private struct CatalogRow: View {
    let item: CatalogItem

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(
                systemImage: item.category.systemImage,
                color: item.isActive ? item.category.color : .secondary
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body.weight(.medium))
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !item.isActive {
                    Pill(text: "Inactivo", color: .brandRed)
                }
            }
            Spacer()
            Text(AppFormat.currency(item.price, decimals: true))
                .font(.subheadline.weight(.semibold))
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

// MARK: - Catalog item form (create/edit)

struct CatalogItemFormView: View {
    @State private var viewModel: CatalogItemFormViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: DataStore, category: CatalogCategory = .convenience, item: CatalogItem? = nil) {
        _viewModel = State(initialValue: CatalogItemFormViewModel(store: store, category: category, item: item))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if viewModel.isEditing {
                        LabeledContent("Categoría", value: viewModel.category.displayName)
                    } else {
                        Picker("Categoría", selection: $viewModel.category) {
                            ForEach(CatalogCategory.allCases) { category in
                                Text(category.displayName).tag(category)
                            }
                        }
                    }
                    TextField("Nombre", text: $viewModel.name)
                    TextField(viewModel.category == .service ? "Qué incluye" : "Presentación (ej. Botella 1 L)", text: $viewModel.detail)
                } header: {
                    Text("Artículo")
                } footer: {
                    Text("La categoría no se puede cambiar después de crear el artículo.")
                }

                Section {
                    NumberField(title: "Precio", value: $viewModel.price, unit: "USD")
                    if viewModel.category.tracksStock {
                        Stepper(value: $viewModel.minStock, in: 0...200, step: 1) {
                            LabeledContent("Existencia mínima", value: "\(Int(viewModel.minStock)) uds.")
                        }
                    }
                } header: {
                    Text("Precio e inventario")
                } footer: {
                    Text(viewModel.category.tracksStock
                         ? "Una sucursal recibe el aviso de reabastecer cuando su existencia llega al mínimo."
                         : "Los servicios no llevan inventario.")
                }

                if viewModel.isEditing {
                    Section {
                        Toggle("Disponible para la venta", isOn: $viewModel.isActive)
                    } footer: {
                        Text("Un artículo inactivo deja de aparecer en el punto de venta, pero conserva su historial.")
                    }
                }

                Section {
                    Button(viewModel.isEditing ? "Guardar cambios" : "Agregar al catálogo") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .disabled(!viewModel.canSave)
                }
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!viewModel.canSave)
                }
            }
            .errorAlert($viewModel.errorMessage)
        }
    }

    private func save() {
        if viewModel.save() {
            dismiss()
        }
    }
}
