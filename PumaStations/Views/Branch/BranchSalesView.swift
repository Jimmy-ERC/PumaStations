import SwiftUI

// MARK: - Sales of the branch

/// Everything the branch sold in a period: fuel (closed cuts), store and maintenance.
struct BranchSalesView: View {
    @State private var viewModel: BranchSalesViewModel
    private let store: DataStore

    init(store: DataStore, branch: Branch) {
        self.store = store
        _viewModel = State(initialValue: BranchSalesViewModel(store: store, branch: branch))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Periodo", selection: $viewModel.period) {
                    ForEach(PeriodFilter.simpleOptions) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                totalCard

                SalesChartCard(buckets: viewModel.fuelMetrics.buckets)

                FuelSalesTableCard(metrics: viewModel.fuelMetrics)

                StoreSalesCard(metrics: viewModel.storeMetrics)

                inventoryLink

                topItemsCard

                sellersCard

                recentSalesCard
            }
            .padding(16)
        }
        .background(Color.screenBackground)
        .navigationTitle("Ventas")
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Ventas")
                        .font(.subheadline.weight(.semibold))
                    Text(viewModel.branch.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.period) { viewModel.load() }
        .onAppear { viewModel.load() }
        .refreshable { viewModel.load() }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ventas de la sucursal · \(viewModel.periodLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(AppFormat.currency(viewModel.totalSales))
                .font(.system(size: 34, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let change = viewModel.totalChange {
                HStack(spacing: 6) {
                    Pill(
                        text: (change >= 0 ? "▲ " : "▼ ") + AppFormat.percent(abs(change)),
                        color: change >= 0 ? Color.brandGreen : Color.brandRed
                    )
                    Text("vs. periodo anterior")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .padding(.vertical, 10)

            HStack(spacing: 12) {
                totalColumn(title: "Combustible", value: viewModel.fuelMetrics.totalSales)
                Divider()
                totalColumn(title: "Tienda", value: viewModel.storeMetrics.storeTotal)
                Divider()
                totalColumn(title: "Mantenimiento", value: viewModel.storeMetrics.serviceTotal)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private func totalColumn(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(AppFormat.currency(value))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inventoryLink: some View {
        NavigationLink {
            StoreInventoryView(store: store, branch: viewModel.branch)
        } label: {
            HStack(spacing: 12) {
                IconSquare(
                    systemImage: "shippingbox",
                    color: viewModel.stockAlerts.isEmpty ? .brandGreen : .warningAmber
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inventario de tienda")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text(inventorySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    private var inventorySubtitle: String {
        let count = viewModel.stockAlerts.count
        if count == 0 { return "Todos los productos con existencia suficiente" }
        return count == 1 ? "1 producto por reabastecer" : "\(count) productos por reabastecer"
    }

    private var topItemsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Más vendidos", trailing: "Tienda y mantenimiento")
            if viewModel.storeMetrics.topItems.isEmpty {
                Text("Sin ventas en este periodo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.storeMetrics.topItems.prefix(5)) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.category.systemImage)
                        .font(.footnote)
                        .foregroundStyle(row.category.color)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(row.units == 1 ? "1 unidad" : "\(row.units) unidades")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(AppFormat.currency(row.amount, decimals: true))
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .cardStyle()
    }

    private var sellersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Ventas por empleado")
            if viewModel.storeMetrics.sellers.isEmpty {
                Text("Sin ventas en este periodo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.storeMetrics.sellers) { row in
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.subheadline)
                        Text(row.tickets == 1 ? "1 venta" : "\(row.tickets) ventas")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(AppFormat.currency(row.amount, decimals: true))
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .cardStyle()
    }

    private var recentSalesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Últimas ventas", trailing: "Tienda y mantenimiento")
            if viewModel.recentSales.isEmpty {
                Text("Sin ventas en este periodo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.recentSales) { sale in
                NavigationLink {
                    SaleDetailView(sale: sale)
                } label: {
                    SaleRow(sale: sale)
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Store inventory

struct StoreInventoryView: View {
    @State private var viewModel: StoreInventoryViewModel
    @State private var restocking: StockLevel?
    private let store: DataStore
    private let canRestock: Bool

    /// `canRestock` is false for the general manager, who only consults the inventory.
    init(store: DataStore, branch: Branch, canRestock: Bool = true) {
        self.store = store
        self.canRestock = canRestock
        _viewModel = State(initialValue: StoreInventoryViewModel(store: store, branch: branch))
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    StatTile(
                        systemImage: "shippingbox",
                        title: "Unidades",
                        value: "\(viewModel.totalUnits)",
                        subtitle: "\(AppFormat.currency(viewModel.stockValue)) a precio de venta"
                    )
                    StatTile(
                        systemImage: "exclamationmark.triangle",
                        title: "Por reabastecer",
                        value: "\(viewModel.alertCount)",
                        subtitle: "Agotados o bajo mínimo",
                        valueColor: viewModel.alertCount > 0 ? .brandRed : .primary
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Picker("Categoría", selection: $viewModel.category) {
                    ForEach(CatalogCategory.products) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                if viewModel.filteredLevels.isEmpty {
                    Text("No hay productos para mostrar.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.filteredLevels) { level in
                    Button {
                        if canRestock { restocking = level }
                    } label: {
                        StockRow(level: level, showsChevron: canRestock)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(canRestock
                     ? "Toca un producto para registrar una entrada. Existencia = entradas − unidades vendidas. El catálogo y los precios los define la gerencia general."
                     : "Existencia = entradas − unidades vendidas. El gerente de la sucursal registra las entradas.")
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Buscar producto")
        .navigationTitle("Inventario de tienda")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $restocking, onDismiss: { viewModel.load() }) { level in
            StockEntryFormView(store: store, branch: viewModel.branch, level: level)
        }
        .onAppear { viewModel.load() }
    }
}

private struct StockRow: View {
    let level: StockLevel
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(systemImage: level.item.category.systemImage, color: level.status.color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(level.item.name)
                    .font(.subheadline.weight(.medium))
                Text("\(AppFormat.currency(level.item.price, decimals: true)) · mínimo \(level.item.minStock) · vendidas \(level.sold)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            StockStatusPill(level: level)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

// MARK: - Stock entry

struct StockEntryFormView: View {
    @State private var viewModel: StockEntryViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: DataStore, branch: Branch, level: StockLevel) {
        _viewModel = State(initialValue: StockEntryViewModel(store: store, branch: branch, level: level))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Producto") {
                    LabeledContent("Nombre", value: viewModel.level.item.name)
                    LabeledContent("Categoría", value: viewModel.level.item.category.displayName)
                    LabeledContent("Precio de venta", value: AppFormat.currency(viewModel.level.item.price, decimals: true))
                }

                Section("Entrada") {
                    Stepper(value: $viewModel.quantity, in: 1...500, step: 1) {
                        LabeledContent("Unidades", value: "\(viewModel.units)")
                    }
                    NumberField(title: "Costo por unidad", value: $viewModel.unitCost, unit: "USD")
                    LabeledContent("Costo total", value: AppFormat.currency(viewModel.total, decimals: true))
                    TextField("Nota (proveedor, factura…)", text: $viewModel.note)
                }

                Section {
                    LabeledContent("Antes", value: "\(viewModel.level.available) uds.")
                    LabeledContent("Después") {
                        Text("\(viewModel.stockAfter) uds.")
                            .fontWeight(.semibold)
                            .foregroundStyle(viewModel.statusAfter.color)
                    }
                } header: {
                    Text("Existencia")
                } footer: {
                    Text("Mínimo recomendado: \(viewModel.level.item.minStock) unidades.")
                }

                Section {
                    Button("Registrar entrada") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Entrada de inventario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
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
