import SwiftUI

/// Staff of the branch: the employees and their weekly schedule.
struct StaffHubView: View {
    private enum StaffSection: String, CaseIterable, Identifiable {
        case employees
        case schedule

        var id: String { rawValue }

        var title: String {
            switch self {
            case .employees: return "Empleados"
            case .schedule: return "Turnos"
            }
        }
    }

    @State private var section: StaffSection = .employees
    private let store: DataStore
    private let branch: Branch

    init(store: DataStore, branch: Branch) {
        self.store = store
        self.branch = branch
    }

    var body: some View {
        Group {
            switch section {
            case .employees:
                EmployeeListView(store: store, branch: branch)
            case .schedule:
                ScheduleView(store: store, branch: branch)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Sección", selection: $section) {
                ForEach(StaffSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.screenBackground)
        }
        .navigationTitle("Personal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Employee list

struct EmployeeListView: View {
    @State private var viewModel: EmployeeListViewModel
    @State private var isShowingNewForm = false
    @State private var editingEmployee: UserAccount?
    private let store: DataStore

    init(store: DataStore, branch: Branch) {
        self.store = store
        _viewModel = State(initialValue: EmployeeListViewModel(store: store, branch: branch))
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    StatTile(
                        systemImage: "person.2",
                        title: "Empleados",
                        value: "\(viewModel.items.count)",
                        subtitle: "\(viewModel.activeCount) activos"
                    )
                    StatTile(
                        systemImage: "clock",
                        title: "En turno ahora",
                        value: "\(viewModel.onShiftCount)",
                        subtitle: "Con entrada marcada"
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                if viewModel.filteredItems.isEmpty {
                    Text("No hay empleados para mostrar.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.filteredItems) { item in
                    Button {
                        editingEmployee = item.employee
                    } label: {
                        EmployeeRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Los empleados venden productos de tienda y servicios de mantenimiento durante su turno. Solo ven datos de esta sucursal.")
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Buscar empleado")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingNewForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nuevo empleado")
            }
        }
        .sheet(isPresented: $isShowingNewForm, onDismiss: { viewModel.load() }) {
            EmployeeFormView(store: store, branch: viewModel.branch)
        }
        .sheet(item: $editingEmployee, onDismiss: { viewModel.load() }) { employee in
            EmployeeFormView(store: store, branch: viewModel.branch, employee: employee)
        }
        .onAppear { viewModel.load() }
    }
}

private struct EmployeeRow: View {
    let item: EmployeeListItem

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(initials: item.employee.initials)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.employee.fullName)
                    .font(.body.weight(.medium))
                Text(item.employee.jobTitle.isEmpty ? item.employee.email : item.employee.jobTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if !item.employee.isActive {
                        Pill(text: "Inactivo", color: .brandRed)
                    } else if let shift = item.todayShift {
                        Pill(text: "Hoy · \(shift.shift.displayName)", color: shift.status().color)
                    } else {
                        Pill(text: "Sin turno hoy", color: .secondary)
                    }
                    Text(item.weekShiftCount == 1 ? "1 turno esta semana" : "\(item.weekShiftCount) turnos esta semana")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

// MARK: - Employee form (create/edit)

struct EmployeeFormView: View {
    @State private var viewModel: EmployeeFormViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: DataStore, branch: Branch, employee: UserAccount? = nil) {
        _viewModel = State(initialValue: EmployeeFormViewModel(store: store, branch: branch, employee: employee))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos del empleado") {
                    TextField("Nombre", text: $viewModel.firstName)
                    TextField("Apellidos", text: $viewModel.lastName)
                    TextField("DUI (00000000-0)", text: $viewModel.dui)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Teléfono", text: $viewModel.phone)
                        .keyboardType(.phonePad)
                }

                Section {
                    TextField("Puesto", text: $viewModel.jobTitle)
                    Menu("Elegir un puesto sugerido") {
                        ForEach(EmployeeFormViewModel.suggestedJobTitles, id: \.self) { jobTitle in
                            Button(jobTitle) { viewModel.jobTitle = jobTitle }
                        }
                    }
                    LabeledContent("Sucursal", value: viewModel.branch.name)
                } header: {
                    Text("Puesto")
                } footer: {
                    Text("El empleado queda asignado a tu sucursal.")
                }

                Section {
                    TextField("Correo", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(viewModel.isEditing ? "Nueva contraseña (opcional)" : "Contraseña temporal", text: $viewModel.password)
                    LabeledContent("Rol", value: UserRole.employee.displayName)
                    if viewModel.isEditing {
                        Toggle("Cuenta activa", isOn: $viewModel.isActive)
                    }
                } header: {
                    Text("Acceso")
                } footer: {
                    Text("Mínimo 6 caracteres. Con esta cuenta el empleado inicia sesión, marca su turno y registra ventas.")
                }

                Section {
                    Button(viewModel.isEditing ? "Guardar cambios" : "Crear empleado") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
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

// MARK: - Weekly schedule

struct ScheduleView: View {
    @State private var viewModel: ScheduleViewModel

    init(store: DataStore, branch: Branch) {
        _viewModel = State(initialValue: ScheduleViewModel(store: store, branch: branch))
    }

    var body: some View {
        List {
            Section {
                weekNavigator
                HStack(spacing: 12) {
                    StatTile(
                        systemImage: "calendar",
                        title: "Turnos asignados",
                        value: "\(viewModel.assignedCount)",
                        subtitle: "\(AppFormat.number(viewModel.workedHours.rounded(toPlaces: 1))) h trabajadas"
                    )
                    StatTile(
                        systemImage: "exclamationmark.triangle",
                        title: "Sin cubrir",
                        value: "\(viewModel.uncoveredCount)",
                        subtitle: "Turnos por asignar",
                        valueColor: viewModel.uncoveredCount > 0 ? .warningAmber : .primary
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            ForEach(viewModel.days) { day in
                Section {
                    ForEach(CutShift.allCases) { shift in
                        ShiftSlotView(
                            shift: shift,
                            assigned: day.assigned(shift),
                            available: day.isPast ? [] : viewModel.availableEmployees(for: shift, on: day),
                            isPast: day.isPast,
                            onAssign: { employee in viewModel.assign(employee, to: shift, on: day.date) },
                            onRemove: { workShift in viewModel.remove(workShift) }
                        )
                    }
                } header: {
                    HStack {
                        Text(AppFormat.date(day.date, format: "EEEE d 'de' MMMM"))
                        if day.isToday {
                            Pill(text: "Hoy", color: .brandGreen)
                                .textCase(nil)
                        }
                    }
                }
            }

            Section {
            } footer: {
                Text("Cada día tiene los mismos dos turnos que los cortes: matutino (\(CutShift.morning.hoursText)) y vespertino (\(CutShift.evening.hoursText)). Un turno con asistencia marcada ya no se puede quitar.")
            }
        }
        .errorAlert($viewModel.errorMessage, title: "No se pudo actualizar el turno")
        .onAppear { viewModel.load() }
    }

    private var weekNavigator: some View {
        HStack {
            Button {
                viewModel.moveWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Semana anterior")
            Spacer()
            VStack(spacing: 2) {
                Text(viewModel.weekLabel)
                    .font(.subheadline.weight(.semibold))
                if viewModel.isCurrentWeek {
                    Text("Semana actual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Ir a la semana actual") { viewModel.goToCurrentWeek() }
                        .font(.caption)
                }
            }
            Spacer()
            Button {
                viewModel.moveWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Semana siguiente")
        }
        .buttonStyle(.borderless)
    }
}

/// One shift of one day: who is assigned, their attendance and the menu to assign someone else.
private struct ShiftSlotView: View {
    let shift: CutShift
    let assigned: [WorkShift]
    let available: [UserAccount]
    let isPast: Bool
    let onAssign: (UserAccount) -> Void
    let onRemove: (WorkShift) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: shift == .morning ? "sun.max" : "moon")
                    .foregroundStyle(Color.brandGreen)
                VStack(alignment: .leading, spacing: 1) {
                    Text(shift.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(shift.hoursText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !isPast {
                    Menu {
                        if available.isEmpty {
                            Text("No hay empleados disponibles")
                        }
                        ForEach(available) { employee in
                            Button(employee.fullName) { onAssign(employee) }
                        }
                    } label: {
                        Label("Asignar", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                }
            }

            if assigned.isEmpty {
                Text(isPast ? "Nadie fue asignado." : "Sin cubrir")
                    .font(.footnote)
                    .foregroundStyle(isPast ? Color.secondary : Color.warningAmber)
            }
            ForEach(assigned) { workShift in
                HStack(spacing: 10) {
                    InitialsAvatar(initials: workShift.employee?.initials ?? "?", size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(workShift.employee?.fullName ?? "Empleado")
                            .font(.subheadline)
                        Text(workShift.checkInAt == nil ? (workShift.employee?.jobTitle ?? "") : workShift.attendanceText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AttendancePill(status: workShift.status())
                    if workShift.checkInAt == nil && !isPast {
                        Button {
                            onRemove(workShift)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Color.brandRed)
                        }
                        .accessibilityLabel("Quitar turno")
                    }
                }
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }
}
