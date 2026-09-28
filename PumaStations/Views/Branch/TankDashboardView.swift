import SwiftUI

struct BranchTabView: View {
    @Environment(DataStore.self) private var store
    let user: UserAccount

    var body: some View {
        if let branch = user.branch {
            TabView {
                NavigationStack {
                    TankDashboardView(store: store, branch: branch, manager: user)
                }
                .tabItem { Label("Tanques", systemImage: "cylinder.split.1x2") }

                NavigationStack {
                    CutsHubView(store: store, branch: branch)
                }
                .tabItem { Label("Cortes", systemImage: "fuelpump") }

                NavigationStack {
                    ProfileView()
                }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
            }
        } else {
            NoBranchAssignedView()
        }
    }
}

/// Shown when a branch manager logs in before being linked to a branch.
struct NoBranchAssignedView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2.crop.circle")
                .font(.system(size: 56))
                .foregroundStyle(Color.warningAmber)
            Text("Aún no tienes sucursal")
                .font(.title2.bold())
            Text("El gerente general debe vincularte a una sucursal para que puedas registrar los cortes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Cerrar sesión") { session.logout() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
        }
        .padding(32)
    }
}

// MARK: - Tank dashboard

struct TankDashboardView: View {
    @State private var viewModel: TankDashboardViewModel

    init(store: DataStore, branch: Branch, manager: UserAccount) {
        _viewModel = State(initialValue: TankDashboardViewModel(store: store, branch: branch, manager: manager))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let alert = viewModel.mainAlert {
                    RestockBanner(tank: alert)
                }

                TankLevelsCard(
                    title: "Nivel de tanques",
                    subtitle: viewModel.lastClosedCutText,
                    tanks: viewModel.tanks,
                    showsLegend: true
                )

                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Cortes de hoy", trailing: AppFormat.date(.now, format: "EEE d MMM").capitalized)
                    ForEach(CutShift.allCases) { shift in
                        CutStatusRow(shift: shift, cut: viewModel.todayCuts[shift])
                    }
                }
                .cardStyle()

                Picker("Periodo", selection: $viewModel.period) {
                    ForEach(PeriodFilter.simpleOptions) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    StatTile(systemImage: "dollarsign.circle", title: "Ventas", value: AppFormat.currency(viewModel.metrics.totalSales))
                    StatTile(systemImage: "drop", title: "Volumen", value: AppFormat.number(viewModel.metrics.totalGallons.rounded()), subtitle: "galones")
                }

                FuelVolumeCard(gallons: viewModel.metrics.gallonsByFuel)

                movementsCard
            }
            .padding(16)
        }
        .background(Color.screenBackground)
        .navigationTitle("Tanques")
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(viewModel.branch.name)
                        .font(.subheadline.weight(.semibold))
                    Text(viewModel.manager.fullName)
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

    private var movementsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Movimientos", trailing: "galones")
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Combustible").gridColumnAlignment(.leading)
                    Text("Recibido")
                    Text("Vendido")
                    Text("Pérdida")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                ForEach(viewModel.movements) { movement in
                    GridRow {
                        HStack(spacing: 6) {
                            FuelDot(fuel: movement.fuel)
                            Text(movement.fuel.displayName)
                        }
                        Text(AppFormat.number(movement.received.rounded()))
                        Text(AppFormat.number(movement.sold.rounded()))
                        Text(AppFormat.number(movement.lost.rounded(toPlaces: 1)))
                            .foregroundStyle(movement.lost > 0 ? Color.brandRed : Color.primary)
                    }
                    .font(.subheadline)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .cardStyle()
    }
}
