import SwiftUI
import SwiftData

// MARK: - Manager list

struct ManagerListView: View {
    @Environment(DataStore.self) private var store
    @State private var viewModel: ManagerListViewModel
    @State private var isShowingNewForm = false
    @State private var editingManager: UserAccount?

    init(store: DataStore) {
        _viewModel = State(initialValue: ManagerListViewModel(store: store))
    }

    var body: some View {
        List {
            Section {
                Picker("Filtro", selection: $viewModel.filter) {
                    ForEach(ManagerFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                if viewModel.filteredManagers.isEmpty {
                    Text("No hay gerentes para mostrar.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.filteredManagers) { manager in
                    Button {
                        editingManager = manager
                    } label: {
                        ManagerRow(manager: manager)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Cada sucursal tiene un solo gerente. Un gerente solo ve y registra información de su sucursal.")
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Buscar gerente")
        .navigationTitle("Gerentes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingNewForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nuevo gerente")
            }
        }
        .sheet(isPresented: $isShowingNewForm, onDismiss: { viewModel.load() }) {
            ManagerFormView(store: store)
        }
        .sheet(item: $editingManager, onDismiss: { viewModel.load() }) { manager in
            ManagerFormView(store: store, manager: manager)
        }
        .onAppear { viewModel.load() }
    }
}

private struct ManagerRow: View {
    let manager: UserAccount

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(initials: manager.initials)
            VStack(alignment: .leading, spacing: 3) {
                Text(manager.fullName)
                    .font(.body.weight(.medium))
                Text(manager.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let branch = manager.branch {
                        Pill(text: branch.name, color: .brandGreen)
                    } else {
                        Pill(text: "Sin sucursal", color: .secondary)
                    }
                    if !manager.isActive {
                        Pill(text: "Inactivo", color: .brandRed)
                    }
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

// MARK: - Manager form (create/edit + link branch)

struct ManagerFormView: View {
    @State private var viewModel: ManagerFormViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: DataStore, manager: UserAccount? = nil) {
        _viewModel = State(initialValue: ManagerFormViewModel(store: store, manager: manager))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos del gerente") {
                    TextField("Nombre", text: $viewModel.firstName)
                    TextField("Apellidos", text: $viewModel.lastName)
                    TextField("DUI (00000000-0)", text: $viewModel.dui)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Teléfono", text: $viewModel.phone)
                        .keyboardType(.phonePad)
                }

                Section {
                    TextField("Correo", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(viewModel.isEditing ? "Nueva contraseña (opcional)" : "Contraseña temporal", text: $viewModel.password)
                    LabeledContent("Rol", value: UserRole.branchManager.displayName)
                    if viewModel.isEditing {
                        Toggle("Cuenta activa", isOn: $viewModel.isActive)
                    }
                } header: {
                    Text("Acceso")
                } footer: {
                    Text("Mínimo 6 caracteres. El gerente solo verá y registrará datos de la sucursal vinculada.")
                }

                Section("Vincular sucursal") {
                    branchOption(nil)
                    ForEach(viewModel.branchOptions) { branch in
                        branchOption(branch)
                    }
                }

                Section {
                    Button(viewModel.isEditing ? "Guardar cambios" : "Crear y vincular") { save() }
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
            .onAppear { viewModel.load() }
        }
    }

    @ViewBuilder
    private func branchOption(_ branch: Branch?) -> some View {
        let isSelected = viewModel.selectedBranch?.persistentModelID == branch?.persistentModelID
        let isAvailable = branch.map { viewModel.isAvailable($0) } ?? true

        Button {
            viewModel.selectedBranch = branch
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(branch?.name ?? "Sin sucursal")
                        .foregroundStyle(Color.primary)
                    if let branch {
                        Text(viewModel.linkedManagerName(for: branch).map { "Vinculada a \($0)" } ?? "Disponible")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.brandGreen)
                }
            }
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.45)
    }

    private func save() {
        if viewModel.save() {
            dismiss()
        }
    }
}
