import Foundation
import SwiftData
import Observation

/// Single access point to the data. ViewModels use it instead of touching ModelContext directly.
///
/// SwiftData holds a local copy of what the logged-in user can see in Supabase: it is downloaded
/// at login, and every `save()` uploads the changes in the background.
@Observable
final class DataStore {
    let context: ModelContext
    /// Connection with Supabase; nil when `Supabase.plist` is missing.
    let sync: RemoteSync?
    /// Increments after every successful save so views can react to changes.
    private(set) var revision = 0

    /// Role of the logged-in user: the general manager saves manager accounts and the catalog,
    /// the branch manager saves the employees of the branch.
    @ObservationIgnored private var sessionRole: UserRole?
    /// Passwords typed in the account forms, waiting for the next save (they are never stored locally).
    @ObservationIgnored private var pendingPasswords: [UUID: String] = [:]

    init(context: ModelContext, sync: RemoteSync? = nil) {
        self.context = context
        self.sync = sync
        // Changes are saved (and uploaded) only through save().
        context.autosaveEnabled = false
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

    /// Saves pending changes locally and queues their upload; if it fails, discards them and rethrows.
    func save() throws {
        // The change lists are emptied by the save, so the uploads are prepared first.
        let operations = pendingOperations()
        pendingPasswords.removeAll()
        do {
            try context.save()
            revision += 1
        } catch {
            context.rollback()
            throw error
        }
        sync?.enqueue(operations)
    }

    /// Removes every record of the local copy (used before downloading the data of a new session).
    func deleteAllData() {
        deleteAll(SaleItem.self)
        deleteAll(Sale.self)
        deleteAll(StockEntry.self)
        deleteAll(WorkShift.self)
        deleteAll(CatalogItem.self)
        deleteAll(FuelLoss.self)
        deleteAll(FuelReception.self)
        deleteAll(PumpSale.self)
        deleteAll(SalesCut.self)
        deleteAll(Pump.self)
        deleteAll(UserAccount.self)
        deleteAll(Branch.self)
        do {
            try context.save()
        } catch {
            context.rollback()
            print("Could not delete data: \(error)")
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        for model in fetchAll(type) {
            context.delete(model)
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

    // MARK: Staff queries

    func employees(of branch: Branch) -> [UserAccount] {
        users()
            .filter { $0.role == .employee && $0.branch?.persistentModelID == branch.persistentModelID }
            .sorted { $0.fullName.localizedCompare($1.fullName) == .orderedAscending }
    }

    func workShifts(of branch: Branch) -> [WorkShift] {
        fetchAll(WorkShift.self).filter { $0.branch?.persistentModelID == branch.persistentModelID }
    }

    func workShifts(of employee: UserAccount) -> [WorkShift] {
        fetchAll(WorkShift.self).filter { $0.employee?.persistentModelID == employee.persistentModelID }
    }

    // MARK: Store queries

    /// Catalog sorted by category and name.
    func catalogItems() -> [CatalogItem] {
        let order = CatalogCategory.allCases
        return fetchAll(CatalogItem.self).sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.category) ?? 0
            let right = order.firstIndex(of: rhs.category) ?? 0
            if left != right { return left < right }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    func isCatalogNameTaken(_ name: String, excluding item: CatalogItem? = nil) -> Bool {
        fetchAll(CatalogItem.self).contains {
            $0.name.caseInsensitiveCompare(name.trimmed) == .orderedSame
                && $0.persistentModelID != item?.persistentModelID
        }
    }

    func stockEntries(of branch: Branch) -> [StockEntry] {
        fetchAll(StockEntry.self).filter { $0.branch?.persistentModelID == branch.persistentModelID }
    }

    /// Store and maintenance sales of the branch, newest first.
    func sales(of branch: Branch) -> [Sale] {
        fetchAll(Sale.self)
            .filter { $0.branch?.persistentModelID == branch.persistentModelID }
            .sorted { $0.soldAt > $1.soldAt }
    }

    func sales(of branches: [Branch]) -> [Sale] {
        let ids = Set(branches.map(\.persistentModelID))
        return fetchAll(Sale.self).filter { sale in
            guard let id = sale.branch?.persistentModelID else { return false }
            return ids.contains(id)
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

    // MARK: Session (Supabase Auth)

    var syncErrorMessage: String? {
        sync?.errorMessage
    }

    /// Signs in, replaces the local copy with the data of the user and returns their account.
    @MainActor
    func signIn(email: String, password: String) async throws -> UserAccount {
        guard let sync else { throw SupabaseError.notConfigured }
        let (userID, snapshot) = try await sync.signIn(email: email, password: password)
        do {
            let user = try replaceAll(with: snapshot, currentUserID: userID)
            sessionRole = user.role
            return user
        } catch {
            sync.signOut()
            throw error
        }
    }

    func signOut() {
        sessionRole = nil
        pendingPasswords.removeAll()
        sync?.signOut()
    }

    func retrySync() {
        sync?.retry()
    }

    /// Password to set for a manager or an employee in the next `save()` (new account or password change).
    func setPassword(_ password: String, for account: UserAccount) {
        pendingPasswords[account.remoteID] = password
    }

    // MARK: Download

    private func replaceAll(with snapshot: RemoteSnapshot, currentUserID: UUID) throws -> UserAccount {
        deleteAllData()

        var branches: [UUID: Branch] = [:]
        for record in snapshot.branches {
            let branch = Branch(record: record)
            context.insert(branch)
            branches[record.id] = branch
        }

        for record in snapshot.pumps {
            guard let branch = branches[record.branchID] else { continue }
            let pump = Pump(number: record.number)
            pump.remoteID = record.id
            context.insert(pump)
            pump.branch = branch
        }

        var currentUser: UserAccount?
        var users: [UUID: UserAccount] = [:]
        for record in snapshot.profiles {
            let user = UserAccount(record: record)
            context.insert(user)
            if let branchID = record.branchID {
                user.branch = branches[branchID]
            }
            users[record.id] = user
            if record.id == currentUserID {
                currentUser = user
            }
        }

        var cuts: [UUID: SalesCut] = [:]
        for record in snapshot.cuts {
            guard let branch = branches[record.branchID], let cut = SalesCut(record: record) else { continue }
            context.insert(cut)
            cut.branch = branch
            cuts[record.id] = cut
        }

        for record in snapshot.pumpSales {
            guard let cut = cuts[record.cutID] else { continue }
            let sale = PumpSale(record: record)
            context.insert(sale)
            sale.cut = cut
        }

        for record in snapshot.receptions {
            guard let cut = cuts[record.cutID] else { continue }
            let reception = FuelReception(record: record)
            context.insert(reception)
            reception.cut = cut
        }

        for record in snapshot.losses {
            guard let cut = cuts[record.cutID] else { continue }
            let loss = FuelLoss(record: record)
            context.insert(loss)
            loss.cut = cut
        }

        for record in snapshot.workShifts {
            guard let branch = branches[record.branchID],
                  let employee = users[record.employeeID],
                  let shift = WorkShift(record: record) else { continue }
            context.insert(shift)
            shift.branch = branch
            shift.employee = employee
        }

        var catalog: [UUID: CatalogItem] = [:]
        for record in snapshot.catalogItems {
            let item = CatalogItem(record: record)
            context.insert(item)
            catalog[record.id] = item
        }

        for record in snapshot.stockEntries {
            guard let branch = branches[record.branchID], let item = catalog[record.itemID] else { continue }
            let entry = StockEntry(record: record)
            context.insert(entry)
            entry.branch = branch
            entry.item = item
        }

        var sales: [UUID: Sale] = [:]
        for record in snapshot.sales {
            guard let branch = branches[record.branchID] else { continue }
            let sale = Sale(record: record)
            context.insert(sale)
            sale.branch = branch
            // The branch manager sees its employees; an employee only sees its own profile.
            sale.seller = record.sellerID.flatMap { users[$0] }
            sales[record.id] = sale
        }

        for record in snapshot.saleItems {
            guard let sale = sales[record.saleID], let item = catalog[record.itemID] else { continue }
            let line = SaleItem(record: record)
            context.insert(line)
            line.sale = sale
            line.item = item
        }

        guard let currentUser else {
            context.rollback()
            throw SupabaseError.profileNotFound
        }
        do {
            try context.save()
            revision += 1
        } catch {
            context.rollback()
            throw error
        }
        return currentUser
    }

    // MARK: Upload

    /// Turns the unsaved changes of the context into writes for Supabase, parents before children.
    private func pendingOperations() -> [SyncOperation] {
        guard sync != nil else { return [] }

        let inserted = context.insertedModelsArray
        let deleted = context.deletedModelsArray
        let excluded = Set((inserted + deleted).map { $0.persistentModelID })
        let changed = context.changedModelsArray.filter { !excluded.contains($0.persistentModelID) }

        var operations: [SyncOperation] = []

        // 1. New rows.
        let newBranches = inserted.compactMap { ($0 as? Branch)?.record }
        if !newBranches.isEmpty {
            operations.append(.insert(newBranches, into: RemoteTable.branches))
        }
        let newPumps = inserted.compactMap { ($0 as? Pump)?.record }
        if !newPumps.isEmpty {
            operations.append(.insert(newPumps, into: RemoteTable.pumps))
        }

        // Accounts are created and edited through database functions: the general manager
        // saves branch managers and the branch manager saves the employees of the branch.
        if sessionRole == .generalManager || sessionRole == .branchManager {
            var accounts = (inserted + changed).compactMap { $0 as? UserAccount }
            let listed = Set(accounts.map(\.remoteID))
            // A password change alone may not mark the account as changed.
            accounts += users().filter { pendingPasswords[$0.remoteID] != nil && !listed.contains($0.remoteID) }
            for account in accounts {
                let password = pendingPasswords[account.remoteID]
                if sessionRole == .generalManager && account.role == .branchManager {
                    operations.append(.saveManager(account.saveParams(password: password)))
                } else if sessionRole == .branchManager && account.role == .employee {
                    operations.append(.saveEmployee(account.saveEmployeeParams(password: password)))
                }
            }
        }

        // Catalog (general manager), work shifts and store inventory (branch manager).
        if sessionRole == .generalManager {
            let newItems = inserted.compactMap { ($0 as? CatalogItem)?.record }
            if !newItems.isEmpty {
                operations.append(.insert(newItems, into: RemoteTable.catalogItems))
            }
            for record in changed.compactMap({ ($0 as? CatalogItem)?.record }) {
                operations.append(.update(record, in: RemoteTable.catalogItems, id: record.id))
            }
        }
        let newShifts = inserted.compactMap { ($0 as? WorkShift)?.record }
        if !newShifts.isEmpty {
            operations.append(.insert(newShifts, into: RemoteTable.workShifts))
        }
        // The employee marks check-in and check-out on the shift assigned by the manager.
        for record in changed.compactMap({ ($0 as? WorkShift)?.record }) {
            operations.append(.update(record, in: RemoteTable.workShifts, id: record.id))
        }
        for shift in deleted.compactMap({ $0 as? WorkShift }) {
            operations.append(.delete(from: RemoteTable.workShifts, id: shift.remoteID))
        }
        let newEntries = inserted.compactMap { ($0 as? StockEntry)?.record }
        if !newEntries.isEmpty {
            operations.append(.insert(newEntries, into: RemoteTable.stockEntries))
        }

        // Store and maintenance sales: the ticket first, then its lines.
        let newStoreSales = inserted.compactMap { ($0 as? Sale)?.record }
        if !newStoreSales.isEmpty {
            operations.append(.insert(newStoreSales, into: RemoteTable.sales))
        }
        let newSaleItems = inserted.compactMap { ($0 as? SaleItem)?.record }
        if !newSaleItems.isEmpty {
            operations.append(.insert(newSaleItems, into: RemoteTable.saleItems))
        }

        let newCuts = inserted.compactMap { ($0 as? SalesCut)?.record }
        if !newCuts.isEmpty {
            operations.append(.insert(newCuts, into: RemoteTable.salesCuts))
        }
        let newSales = inserted.compactMap { ($0 as? PumpSale)?.record }
        if !newSales.isEmpty {
            operations.append(.insert(newSales, into: RemoteTable.pumpSales))
        }
        let newReceptions = inserted.compactMap { ($0 as? FuelReception)?.record }
        if !newReceptions.isEmpty {
            operations.append(.insert(newReceptions, into: RemoteTable.fuelReceptions))
        }
        let newLosses = inserted.compactMap { ($0 as? FuelLoss)?.record }
        if !newLosses.isEmpty {
            operations.append(.insert(newLosses, into: RemoteTable.fuelLosses))
        }

        // 2. Edited and deleted movements, while their cut is still open on the server.
        for record in changed.compactMap({ ($0 as? PumpSale)?.record }) {
            operations.append(.update(record, in: RemoteTable.pumpSales, id: record.id))
        }
        for record in changed.compactMap({ ($0 as? FuelReception)?.record }) {
            operations.append(.update(record, in: RemoteTable.fuelReceptions, id: record.id))
        }
        for record in changed.compactMap({ ($0 as? FuelLoss)?.record }) {
            operations.append(.update(record, in: RemoteTable.fuelLosses, id: record.id))
        }
        for model in deleted {
            if let sale = model as? PumpSale {
                operations.append(.delete(from: RemoteTable.pumpSales, id: sale.remoteID))
            } else if let reception = model as? FuelReception {
                operations.append(.delete(from: RemoteTable.fuelReceptions, id: reception.remoteID))
            } else if let loss = model as? FuelLoss {
                operations.append(.delete(from: RemoteTable.fuelLosses, id: loss.remoteID))
            }
        }

        // 3. Cuts (closing locks them) and finally the tanks of the branch.
        for record in changed.compactMap({ ($0 as? SalesCut)?.record }) {
            operations.append(.update(record, in: RemoteTable.salesCuts, id: record.id))
        }
        // An employee never edits the branch (linking a sale to it may mark it as changed).
        if sessionRole != .employee {
            for record in changed.compactMap({ ($0 as? Branch)?.record }) {
                operations.append(.update(record, in: RemoteTable.branches, id: record.id))
            }
        }

        return operations
    }
}
