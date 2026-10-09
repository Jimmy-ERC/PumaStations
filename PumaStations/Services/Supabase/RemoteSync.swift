import Foundation
import Observation

/// One pending write against the server. Operations run in order, one at a time.
struct SyncOperation: Sendable {
    let run: @Sendable (SupabaseClient) async throws -> Void

    static func insert<T: Encodable & Sendable>(_ rows: [T], into table: String) -> SyncOperation {
        SyncOperation { try await $0.insert(rows, into: table) }
    }

    static func update<T: Encodable & Sendable>(_ row: T, in table: String, id: UUID) -> SyncOperation {
        SyncOperation { try await $0.update(row, in: table, id: id) }
    }

    static func delete(from table: String, id: UUID) -> SyncOperation {
        SyncOperation { try await $0.delete(from: table, id: id) }
    }

    static func saveManager(_ params: SaveManagerParams) -> SyncOperation {
        SyncOperation { try await $0.rpc("save_manager", params: params) }
    }
}

/// Talks to Supabase: downloads the data after login and uploads local changes in the background.
/// The app keeps working on the local SwiftData copy; this class keeps the server up to date.
@Observable
final class RemoteSync {
    /// Set when an upload fails. The queue stops until `retry()` or `signOut()`.
    private(set) var errorMessage: String?
    private(set) var pendingCount = 0

    @ObservationIgnored private let client: SupabaseClient
    @ObservationIgnored private var queue: [SyncOperation] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var signOutTask: Task<Void, Never>?

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: Download

    /// Signs in and downloads everything the user is allowed to see.
    @MainActor
    func signIn(email: String, password: String) async throws -> (userID: UUID, snapshot: RemoteSnapshot) {
        // A previous logout may still be uploading its last changes.
        await signOutTask?.value
        let userID = try await client.signIn(email: email, password: password)
        do {
            var snapshot = RemoteSnapshot()
            snapshot.profiles = try await client.selectAll(ProfileRecord.self, from: RemoteTable.profiles)
            guard let profile = snapshot.profiles.first(where: { $0.id == userID }) else {
                throw SupabaseError.profileNotFound
            }
            guard profile.isActive else {
                throw SupabaseError.inactiveAccount
            }
            snapshot.branches = try await client.selectAll(BranchRecord.self, from: RemoteTable.branches)
            snapshot.pumps = try await client.selectAll(PumpRecord.self, from: RemoteTable.pumps)
            snapshot.cuts = try await client.selectAll(SalesCutRecord.self, from: RemoteTable.salesCuts)
            snapshot.pumpSales = try await client.selectAll(PumpSaleRecord.self, from: RemoteTable.pumpSales)
            snapshot.receptions = try await client.selectAll(FuelReceptionRecord.self, from: RemoteTable.fuelReceptions)
            snapshot.losses = try await client.selectAll(FuelLossRecord.self, from: RemoteTable.fuelLosses)
            return (userID, snapshot)
        } catch {
            await client.signOut()
            throw error
        }
    }

    // MARK: Upload

    /// Adds writes to the queue and starts uploading them. Call it from the main thread.
    func enqueue(_ operations: [SyncOperation]) {
        guard !operations.isEmpty else { return }
        queue.append(contentsOf: operations)
        pendingCount = queue.count
        startWorkerIfNeeded()
    }

    func retry() {
        errorMessage = nil
        startWorkerIfNeeded()
    }

    /// Waits for the pending uploads (unless they are stuck on an error) and closes the session.
    func signOut() {
        let pendingWork = errorMessage == nil ? worker : nil
        if errorMessage != nil {
            queue.removeAll()
            pendingCount = 0
            errorMessage = nil
        }
        let client = client
        signOutTask = Task {
            await pendingWork?.value
            await client.signOut()
        }
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, errorMessage == nil, !queue.isEmpty else { return }
        worker = Task { @MainActor in
            await self.drain()
        }
    }

    @MainActor
    private func drain() async {
        while let operation = queue.first {
            do {
                try await operation.run(client)
                queue.removeFirst()
                pendingCount = queue.count
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
        worker = nil
    }
}
