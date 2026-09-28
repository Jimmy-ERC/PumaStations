import Foundation
import SwiftData
import Observation

/// Single access point to SwiftData. ViewModels use it instead of touching ModelContext directly.
@Observable
final class DataStore {
    let context: ModelContext
    /// Increments after every successful save so views can react to changes.
    private(set) var revision = 0

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Generic operations

    func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        do {
            return try context.fetch(FetchDescriptor<T>())
        } catch {
            print("Fetch failed for \(T.self): \(error)")
            return []
        }
    }

    func insert<T: PersistentModel>(_ model: T) {
        context.insert(model)
    }

    func delete<T: PersistentModel>(_ model: T) {
        context.delete(model)
    }

    /// Saves pending changes; if it fails, discards them and rethrows.
    func save() throws {
        do {
            try context.save()
            revision += 1
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Removes every stored record (used before loading the demo data).
    func deleteAllData() {
        do {
            try context.delete(model: FuelLoss.self)
            try context.delete(model: FuelReception.self)
            try context.delete(model: PumpSale.self)
            try context.delete(model: SalesCut.self)
            try context.delete(model: Pump.self)
            try context.delete(model: UserAccount.self)
            try context.delete(model: Branch.self)
            try context.save()
        } catch {
            print("Could not delete data: \(error)")
        }
    }

    // MARK: Queries

    func users() -> [UserAccount] {
        fetchAll(UserAccount.self)
    }

    func branches() -> [Branch] {
        fetchAll(Branch.self).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func branchManagers() -> [UserAccount] {
        users()
            .filter { $0.role == .branchManager }
            .sorted { $0.fullName.localizedCompare($1.fullName) == .orderedAscending }
    }

    func manager(of branch: Branch) -> UserAccount? {
        branchManagers().first { $0.branch?.persistentModelID == branch.persistentModelID }
    }

    func isEmailTaken(_ email: String, excluding user: UserAccount? = nil) -> Bool {
        let normalized = email.trimmed.lowercased()
        return users().contains {
            $0.email == normalized && $0.persistentModelID != user?.persistentModelID
        }
    }

    // MARK: Branch creation

    /// Creates a branch with its 6 pumps (fixed by the business rules).
    @discardableResult
    func createBranch(
        name: String,
        code: String,
        address: String,
        municipality: String,
        phone: String,
        capacities: [FuelType: Double]
    ) -> Branch {
        let branch = Branch(
            name: name,
            code: code,
            address: address,
            municipality: municipality,
            phone: phone,
            dieselCapacity: capacities[.diesel] ?? 0,
            regularCapacity: capacities[.regular] ?? 0,
            premiumCapacity: capacities[.premium] ?? 0
        )
        insert(branch)
        for number in 1...BusinessRules.pumpsPerBranch {
            let pump = Pump(number: number)
            insert(pump)
            pump.branch = branch
        }
        return branch
    }
}
