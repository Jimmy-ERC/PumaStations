import SwiftUI

// MARK: - Branch list

struct BranchListView: View {
    @Environment(DataStore.self) private var store
    @State private var viewModel: BranchListViewModel
    @State private var isShowingForm = false

    init(store: DataStore) {
        _viewModel = State(initialValue: BranchListViewModel(store: store))
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    StatTile(systemImage: "building.2", title: "Estaciones", value: "\(viewModel.items.count)", subtitle: "\(viewModel.totalPumps) bombas")
                    StatTile(
                        systemImage: "exclamationmark.triangle",
                        title: "Con alerta crítica",
                        value: "\(viewModel.criticalCount)",
                        subtitle: "Reabastecer hoy",
                        valueColor: viewModel.criticalCount > 0 ? .brandRed : .primary
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(viewModel.filteredItems) { item in
                    NavigationLink {
                        StationDetailView(store: store, branch: item.branch)
                    } label: {
                        BranchRow(item: item)
                    }
                }
            } footer: {
                Text("El estado muestra el tanque más comprometido de cada estación. Ventas del mes en curso.")
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Buscar sucursal")
        .navigationTitle("Sucursales")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nueva sucursal")
            }
        }
        .sheet(isPresented: $isShowingForm, onDismiss: { viewModel.load() }) {
            BranchFormView(store: store)
        }
        .onAppear { viewModel.load() }
    }
}

private struct BranchRow: View {
    let item: BranchListItem

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(systemImage: "fuelpump", color: item.hasOperation ? .brandGreen : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.branch.name)
                    .font(.body.weight(.medium))
                Text(item.branch.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(item.manager?.fullName ?? "Sin gerente") · \(item.branch.pumps.count) bombas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if item.manager == nil {
                    Pill(text: "Sin gerente vinculado", color: .warningAmber)
                } else if item.hasOperation {
                    TankStatusPill(status: item.worstStatus)
                }
            }
            Spacer()
            if item.hasOperation {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(AppFormat.currency(item.monthSales))
                        .font(.subheadline.weight(.semibold))
                    Text("ventas")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - New branch

struct BranchFormView: View {
    @State private var viewModel: BranchFormViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: DataStore) {
        _viewModel = State(initialValue: BranchFormViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos generales") {
                    TextField("Nombre (ej. Puma Merliot)", text: $viewModel.name)
                    LabeledContent("Código") {
                        TextField("SUC-000", text: $viewModel.code)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Dirección", text: $viewModel.address)
                    TextField("Municipio", text: $viewModel.municipality)
                    TextField("Teléfono", text: $viewModel.phone)
                        .keyboardType(.phonePad)
                }

                Section {
                    ForEach(FuelType.allCases) { fuel in
                        NumberField(title: fuel.displayName, value: capacityBinding(for: fuel), unit: "gal")
                    }
                } header: {
                    Text("Capacidad de tanques")
                } footer: {
                    Text("La existencia inicial es 0 gal. Sube con cada recepción y baja con las ventas y pérdidas de cada corte.")
                }

                Section {
                    LabeledContent("Bombas", value: "\(BusinessRules.pumpsPerBranch) (fijo)")
                } footer: {
                    Text("Se crean automáticamente las bombas 1 a \(BusinessRules.pumpsPerBranch). Cada una despacha Diésel, Regular y Súper.")
                }

                Section {
                    Picker("Gerente", selection: $viewModel.selectedManager) {
                        Text("Sin vincular").tag(UserAccount?.none)
                        ForEach(viewModel.availableManagers) { manager in
                            Text(manager.fullName).tag(Optional(manager))
                        }
                    }
                } header: {
                    Text("Gerente de sucursal")
                } footer: {
                    Text("Solo aparecen gerentes sin sucursal. También puedes vincularlo después desde Gerentes.")
                }

                Section {
                    Button("Crear sucursal") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .disabled(!viewModel.canSave)
                }
            }
            .navigationTitle("Nueva sucursal")
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
            .onAppear { viewModel.load() }
        }
    }

    private func capacityBinding(for fuel: FuelType) -> Binding<Double> {
        Binding(
            get: { viewModel.capacities[fuel] ?? 0 },
            set: { viewModel.capacities[fuel] = $0 }
        )
    }

    private func save() {
        if viewModel.save() {
            dismiss()
        }
    }
}

// MARK: - Station detail (general manager, read only)

struct StationDetailView: View {
    @Environment(DataStore.self) private var storeForReports
    @State private var viewModel: StationDetailViewModel

    init(store: DataStore, branch: Branch) {
        _viewModel = State(initialValue: StationDetailViewModel(store: store, branch: branch))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(viewModel.branch.code) · \(viewModel.manager.map { "Gerente: \($0.fullName)" } ?? "Sin gerente vinculado")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label("\(viewModel.branch.address), \(viewModel.branch.municipality)", systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.hasOperation {
                    operationContent
                } else {
                    ContentUnavailableView(
                        "Sin operación",
                        systemImage: "fuelpump.slash",
                        description: Text("Esta estación aún no registra cortes. Vincula un gerente para que empiece a operar.")
                    )
                }
            }
            .padding(16)
        }
        .background(Color.screenBackground)
        .navigationTitle(viewModel.branch.name)
        .onChange(of: viewModel.period) { viewModel.load() }
        .onAppear { viewModel.load() }
    }

    @ViewBuilder
    private var operationContent: some View {
        Picker("Periodo", selection: $viewModel.period) {
            ForEach(PeriodFilter.simpleOptions) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)

        if let alert = viewModel.mainAlert {
            RestockBanner(tank: alert)
        }

        TankLevelsCard(title: "Tanques", tanks: viewModel.tanks)

        SalesKPICard(title: "Ventas del periodo", metrics: viewModel.metrics)

        FuelVolumeCard(gallons: viewModel.metrics.gallonsByFuel)

        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Cortes de hoy")
            ForEach(CutShift.allCases) { shift in
                CutStatusRow(shift: shift, cut: viewModel.todayCuts[shift])
            }
        }
        .cardStyle()

        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Últimas pérdidas", trailing: AppFormat.gallons(viewModel.metrics.lossGallons.rounded()))
            if viewModel.recentLosses.isEmpty {
                Text("Sin pérdidas registradas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.recentLosses) { loss in
                LossRow(loss: loss)
            }
        }
        .cardStyle()

        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Historial de cortes")
            ForEach(viewModel.recentCuts) { cut in
                NavigationLink {
                    CutReportView(store: storeForReports, cut: cut, branch: viewModel.branch)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(AppFormat.date(cut.day, format: "EEE d MMM").capitalized) · \(cut.shift.displayName)")
                                .font(.subheadline.weight(.medium))
                            Text("\(cut.registeredPumpCount)/\(BusinessRules.pumpsPerBranch) bombas · \(AppFormat.gallons(cut.totalGallons.rounded()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(AppFormat.currency(cut.totalSales, decimals: true))
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(Color.primary)
                }
            }
        }
        .cardStyle()
    }
}

/// Row used to show a loss or damage record.
struct LossRow: View {
    let loss: FuelLoss

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(systemImage: loss.pumpNumber == nil ? "cylinder" : "fuelpump", color: .brandRed, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(loss.type.displayName) · \(loss.originText)")
                    .font(.subheadline.weight(.medium))
                Text("\(loss.fuel.displayName) · \(AppFormat.date(loss.recordedAt, format: "d MMM")) · \(loss.details)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text("−\(AppFormat.gallons(loss.gallons))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandRed)
        }
    }
}
