import Foundation
import Observation
import SwiftData

enum ManagerFilter: String, CaseIterable, Identifiable {
    case all
    case linked
    case unlinked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todos"
        case .linked: return "Vinculados"
        case .unlinked: return "Sin sucursal"
        }
    }
}

@Observable
final class ManagerListViewModel {
    var searchText = ""
    var filter: ManagerFilter = .all
    private(set) var managers: [UserAccount] = []

    private let store: DataStore

    init(store: DataStore) {
        self.store = store
    }

    var filteredManagers: [UserAccount] {
        let query = searchText.trimmed
        return managers.filter { manager in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .linked: matchesFilter = manager.branch != nil
            case .unlinked: matchesFilter = manager.branch == nil
            }
            let matchesSearch = query.isEmpty
                || manager.fullName.localizedCaseInsensitiveContains(query)
                || manager.email.localizedCaseInsensitiveContains(query)
            return matchesFilter && matchesSearch
        }
    }

    func load() {
        managers = store.branchManagers()
    }
}

// MARK: - Manager form (create or edit + link branch)

@Observable
final class ManagerFormViewModel {
    var firstName = ""
    var lastName = ""
    var dui = ""
    var phone = ""
    var email = ""
    var password = ""
    var isActive = true
    var selectedBranch: Branch?
    var errorMessage: String?
    private(set) var branchOptions: [Branch] = []
    private(set) var linkedNames: [PersistentIdentifier: String] = [:]

    let editingManager: UserAccount?
    private let store: DataStore

    init(store: DataStore, manager: UserAccount? = nil) {
        self.store = store
        self.editingManager = manager
        if let manager {
            firstName = manager.firstName
            lastName = manager.lastName
            dui = manager.dui
            phone = manager.phone
            email = manager.email
            isActive = manager.isActive
            selectedBranch = manager.branch
        }
    }

    var isEditing: Bool { editingManager != nil }
    var title: String { isEditing ? "Editar gerente" : "Nuevo gerente" }

    func load() {
        branchOptions = store.branches()
        var names: [PersistentIdentifier: String] = [:]
        for manager in store.branchManagers() {
            guard let branch = manager.branch,
                  manager.persistentModelID != editingManager?.persistentModelID else { continue }
            names[branch.persistentModelID] = manager.fullName
        }
        linkedNames = names
    }

    /// A branch can be picked only if no other manager is linked to it.
    func isAvailable(_ branch: Branch) -> Bool {
        linkedNames[branch.persistentModelID] == nil
    }

    func linkedManagerName(for branch: Branch) -> String? {
        linkedNames[branch.persistentModelID]
    }

    func save() -> Bool {
        let normalizedEmail = email.trimmed.lowercased()
        guard !firstName.trimmed.isEmpty, !lastName.trimmed.isEmpty else {
            errorMessage = "Ingresa nombre y apellidos."
            return false
        }
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            errorMessage = "Ingresa un correo válido."
            return false
        }
        guard !store.isEmailTaken(normalizedEmail, excluding: editingManager) else {
            errorMessage = "Ese correo ya está registrado."
            return false
        }
        if !isEditing || !password.isEmpty {
            guard password.count >= 6 else {
                errorMessage = "La contraseña debe tener al menos 6 caracteres."
                return false
            }
        }
        if let branch = selectedBranch, !isAvailable(branch) {
            errorMessage = "Esa sucursal ya tiene un gerente vinculado."
            return false
        }

        let manager: UserAccount
        if let editingManager {
            manager = editingManager
            manager.firstName = firstName.trimmed
            manager.lastName = lastName.trimmed
            manager.email = normalizedEmail
            if !password.isEmpty {
                manager.passwordHash = PasswordHasher.hash(password)
            }
        } else {
            manager = UserAccount(
                firstName: firstName.trimmed,
                lastName: lastName.trimmed,
                email: normalizedEmail,
                passwordHash: PasswordHasher.hash(password),
                role: .branchManager
            )
            store.insert(manager)
        }
        manager.dui = dui.trimmed
        manager.phone = phone.trimmed
        manager.isActive = isActive
        manager.branch = selectedBranch

        do {
            try store.save()
            return true
        } catch {
            errorMessage = "Ocurrió un error al guardar: \(error.localizedDescription)"
            return false
        }
    }
}
