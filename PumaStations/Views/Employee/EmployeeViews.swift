import SwiftUI

/// Experience of an employee: attendance, store sales and maintenance orders of the branch.
struct EmployeeTabView: View {
    @Environment(DataStore.self) private var store
    let user: UserAccount

    var body: some View {
        if let branch = user.branch {
            TabView {
                NavigationStack {
                    MyShiftView(store: store, employee: user, branch: branch)
                }
                .tabItem { Label("Mi turno", systemImage: "clock") }

                NavigationStack {
                    SaleView(store: store, kind: .store, branch: branch, seller: user)
                }
                .tabItem { Label("Tienda", systemImage: "cart") }

                NavigationStack {
                    SaleView(store: store, kind: .service, branch: branch, seller: user)
                }
                .tabItem { Label("Mantenimiento", systemImage: "wrench.and.screwdriver") }

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

// MARK: - My shift

struct MyShiftView: View {
    @State private var viewModel: MyShiftViewModel

    init(store: DataStore, employee: UserAccount, branch: Branch) {
        _viewModel = State(initialValue: MyShiftViewModel(store: store, employee: employee, branch: branch))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                todayCard

                HStack(spacing: 12) {
                    StatTile(
                        systemImage: "dollarsign.circle",
                        title: "Mis ventas de hoy",
                        value: AppFormat.currency(viewModel.todayTotal, decimals: true),
                        subtitle: viewModel.todaySales.count == 1 ? "1 venta" : "\(viewModel.todaySales.count) ventas"
                    )
                    StatTile(
                        systemImage: "clock",
                        title: "Horas esta semana",
                        value: AppFormat.number(viewModel.weekHours.rounded(toPlaces: 1)),
                        subtitle: "Turnos completados"
                    )
                }

                shiftListCard(title: "Próximos turnos", shifts: viewModel.upcoming, emptyText: "No tienes turnos programados.")

                salesCard

                shiftListCard(title: "Turnos anteriores", shifts: viewModel.history, emptyText: "Aún no hay turnos anteriores.")
            }
            .padding(16)
        }
        .background(Color.screenBackground)
        .navigationTitle("Mi turno")
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(viewModel.branch.name)
                        .font(.subheadline.weight(.semibold))
                    Text(viewModel.employee.jobTitle.isEmpty ? viewModel.employee.fullName : "\(viewModel.employee.fullName) · \(viewModel.employee.jobTitle)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert($viewModel.errorMessage, title: "No se pudo marcar la asistencia")
        .onAppear { viewModel.load() }
        .refreshable { viewModel.load() }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Hoy", trailing: AppFormat.date(.now, format: "EEE d MMM").capitalized)
            if viewModel.todayShifts.isEmpty {
                Label("No tienes turno asignado hoy", systemImage: "calendar.badge.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("El gerente de la sucursal asigna los turnos. Sin un turno con entrada marcada no se pueden registrar ventas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.todayShifts) { shift in
                TodayShiftRow(
                    workShift: shift,
                    onCheckIn: { viewModel.checkIn(shift) },
                    onCheckOut: { viewModel.checkOut(shift) }
                )
            }
        }
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.brandGreen, lineWidth: viewModel.activeShift != nil ? 2 : 0)
        )
    }

    private func shiftListCard(title: String, shifts: [WorkShift], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title)
            if shifts.isEmpty {
                Text(emptyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(shifts) { shift in
                WorkShiftRow(workShift: shift)
            }
        }
        .cardStyle()
    }

    private var salesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Mis ventas de hoy", trailing: AppFormat.currency(viewModel.todayTotal, decimals: true))
            if viewModel.todaySales.isEmpty {
                Text("Aún no registras ventas hoy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.todaySales) { sale in
                NavigationLink {
                    SaleDetailView(sale: sale)
                } label: {
                    SaleRow(sale: sale, showsSeller: false)
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .cardStyle()
    }
}

/// Today's shift with the button to mark check-in or check-out.
private struct TodayShiftRow: View {
    let workShift: WorkShift
    let onCheckIn: () -> Void
    let onCheckOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkShiftRow(workShift: workShift, showsDate: false)
            if workShift.checkInAt == nil {
                Button("Marcar entrada", action: onCheckIn)
                    .buttonStyle(PrimaryButtonStyle())
            } else if workShift.checkOutAt == nil {
                Button("Marcar salida", action: onCheckOut)
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Text("Turno completado · \(AppFormat.number(workShift.workedHours.rounded(toPlaces: 1))) horas")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Point of sale

/// Store ticket (products) or maintenance order (services), depending on `kind`.
struct SaleView: View {
    @State private var viewModel: SaleViewModel

    init(store: DataStore, kind: SaleKind, branch: Branch, seller: UserAccount) {
        _viewModel = State(initialValue: SaleViewModel(store: store, kind: kind, branch: branch, seller: seller))
    }

    var body: some View {
        List {
            if !viewModel.canSell {
                Section {
                    Label("Marca la entrada de tu turno en «Mi turno» para poder vender.", systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(Color.warningAmber)
                }
            }

            if viewModel.kind == .service {
                Section {
                    TextField("Placa (ej. P123-456)", text: $viewModel.vehiclePlate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Vehículo")
                } footer: {
                    Text("Cada servicio se cobra una vez por vehículo.")
                }
            }

            ForEach(viewModel.kind.categories) { category in
                Section(category == .service ? "Servicios" : category.displayName) {
                    let options = viewModel.options(in: category)
                    if options.isEmpty {
                        Text("No hay artículos para mostrar.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(options) { option in
                        SaleOptionRow(
                            option: option,
                            quantity: viewModel.quantity(of: option),
                            canAdd: viewModel.canAdd(option),
                            onAdd: { viewModel.add(option) },
                            onRemove: { viewModel.remove(option) }
                        )
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: viewModel.kind == .store ? "Buscar producto" : "Buscar servicio")
        .navigationTitle(viewModel.title)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            checkoutBar
        }
        .sheet(item: $viewModel.lastSale) { sale in
            SaleConfirmationView(sale: sale)
        }
        .errorAlert($viewModel.errorMessage, title: "No se pudo registrar la venta")
        .onAppear { viewModel.load() }
    }

    private var checkoutBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text(viewModel.unitCount == 1 ? "1 artículo" : "\(viewModel.unitCount) artículos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(AppFormat.currency(viewModel.total, decimals: true))
                    .font(.title3.bold())
            }
            Picker("Pago", selection: $viewModel.payment) {
                ForEach(PaymentMethod.allCases) { method in
                    Text(method.displayName).tag(method)
                }
            }
            .pickerStyle(.segmented)
            Button(viewModel.kind == .store ? "Cobrar" : "Registrar orden") {
                viewModel.charge()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!viewModel.canCharge)
        }
        .padding(16)
        .background(.bar)
    }
}

private struct SaleOptionRow: View {
    let option: SaleOption
    let quantity: Int
    let canAdd: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.item.name)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isOut ? Color.brandRed : Color.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if quantity > 0 {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .font(.title3)
                }
                .accessibilityLabel("Quitar uno")
                Text("\(quantity)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 20)
            }
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .disabled(!canAdd)
            .accessibilityLabel("Agregar uno")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }

    private var isOut: Bool {
        (option.available ?? 1) <= 0
    }

    private var subtitle: String {
        let price = AppFormat.currency(option.item.price, decimals: true)
        guard let available = option.available else {
            return option.item.detail.isEmpty ? price : "\(price) · \(option.item.detail)"
        }
        return available > 0 ? "\(price) · quedan \(available)" : "\(price) · agotado"
    }
}

/// Confirmation shown after a sale is registered.
private struct SaleConfirmationView: View {
    let sale: Sale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SaleDetailView(sale: sale)
                .safeAreaInset(edge: .top, spacing: 0) {
                    Label(sale.kind == .store ? "Venta registrada" : "Orden registrada", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Color.brandGreen)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.screenBackground)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
