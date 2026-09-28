import SwiftUI

struct GeneralTabView: View {
    @Environment(DataStore.self) private var store

    var body: some View {
        TabView {
            NavigationStack {
                GeneralDashboardView(store: store)
            }
            .tabItem { Label("Dashboard", systemImage: "chart.bar.xaxis") }

            NavigationStack {
                BranchListView(store: store)
            }
            .tabItem { Label("Sucursales", systemImage: "building.2") }

            NavigationStack {
                ManagerListView(store: store)
            }
            .tabItem { Label("Gerentes", systemImage: "person.2") }

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
        }
    }
}

// MARK: - Consolidated dashboard

struct GeneralDashboardView: View {
    @State private var viewModel: GeneralDashboardViewModel
    @State private var isShowingFilters = false

    init(store: DataStore) {
        _viewModel = State(initialValue: GeneralDashboardViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                filterChips

                SalesKPICard(
                    title: viewModel.isConsolidated ? "Ventas totales" : "Ventas · \(viewModel.scopeLabel)",
                    metrics: viewModel.metrics
                )

                alertsCard

                if viewModel.isConsolidated {
                    TankMatrixCard(rows: viewModel.tankMatrix)
                } else if let tanks = viewModel.tankMatrix.first?.levels {
                    TankLevelsCard(tanks: tanks)
                }

                SalesChartCard(buckets: viewModel.metrics.buckets, fuels: viewModel.fuelFilter.fuels)

                FuelSalesTableCard(metrics: viewModel.metrics, fuels: viewModel.fuelFilter.fuels)

                if viewModel.isConsolidated {
                    BranchSalesTableCard(rows: viewModel.metrics.rows)
                }

                HStack(spacing: 12) {
                    StatTile(
                        systemImage: "truck.box",
                        title: "Compras recibidas",
                        value: AppFormat.currency(viewModel.metrics.purchases),
                        subtitle: "Combustible"
                    )
                    StatTile(
                        systemImage: "exclamationmark.triangle",
                        title: "Pérdidas",
                        value: AppFormat.gallons(viewModel.metrics.lossGallons.rounded()),
                        subtitle: "\(AppFormat.currency(viewModel.metrics.lossAmount)) estimado",
                        valueColor: .brandRed
                    )
                }
            }
            .padding(16)
        }
        .background(Color.screenBackground)
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingFilters = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filtros")
            }
        }
        .sheet(isPresented: $isShowingFilters, onDismiss: { viewModel.load() }) {
            DashboardFilterSheet(viewModel: viewModel)
        }
        .onAppear { viewModel.load() }
        .refreshable { viewModel.load() }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    isShowingFilters = true
                } label: {
                    FilterChip(systemImage: "building.2", text: viewModel.scopeLabel, isHighlighted: true)
                }
                Button {
                    isShowingFilters = true
                } label: {
                    FilterChip(systemImage: "calendar", text: viewModel.periodLabel)
                }
                if viewModel.fuelFilter != .all {
                    Button {
                        isShowingFilters = true
                    } label: {
                        FilterChip(systemImage: "fuelpump", text: viewModel.fuelFilter.title)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Alertas de reabastecimiento")
                    .font(.headline)
                Spacer()
                if viewModel.criticalCount > 0 {
                    Pill(text: viewModel.criticalCount == 1 ? "1 crítica" : "\(viewModel.criticalCount) críticas", color: .brandRed)
                }
            }
            if viewModel.alerts.isEmpty {
                Label("Todos los tanques en nivel óptimo", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.brandGreen)
            }
            ForEach(viewModel.alerts) { alert in
                HStack(spacing: 12) {
                    IconSquare(systemImage: "exclamationmark.triangle", color: alert.tank.status.color, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(alert.branchName) · \(alert.tank.fuel.displayName)")
                            .font(.subheadline.weight(.medium))
                        Text(alertDetail(alert.tank))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    TankStatusPill(status: alert.tank.status)
                }
            }
        }
        .cardStyle()
    }

    private func alertDetail(_ tank: TankLevel) -> String {
        var text = AppFormat.gallons(tank.stock)
        if let days = tank.daysLeft {
            text += " · ≈ \(AppFormat.number(days.rounded(toPlaces: 1))) días de venta"
        }
        return text
    }
}

// MARK: - Filters

struct DashboardFilterSheet: View {
    @Bindable var viewModel: GeneralDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Alcance") {
                    Picker("Alcance", selection: $viewModel.selectedBranch) {
                        Text("Todo el país (consolidado)").tag(Branch?.none)
                        ForEach(viewModel.branches) { branch in
                            Text(branch.name).tag(Optional(branch))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Periodo") {
                    Picker("Periodo", selection: $viewModel.period) {
                        ForEach(PeriodFilter.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.period == .custom {
                        DatePicker("Desde", selection: $viewModel.customStart, displayedComponents: .date)
                        DatePicker("Hasta", selection: $viewModel.customEnd, in: viewModel.customStart..., displayedComponents: .date)
                    }
                }

                Section("Combustible") {
                    Picker("Combustible", selection: $viewModel.fuelFilter) {
                        ForEach(FuelFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Limpiar") { viewModel.resetFilters() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
