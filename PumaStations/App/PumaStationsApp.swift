import SwiftUI
import SwiftData

@main
struct PumaStationsApp: App {
    private let container: ModelContainer
    @State private var store: DataStore
    @State private var session: SessionStore

    init() {
        let schema = Schema([
            UserAccount.self,
            Branch.self,
            Pump.self,
            SalesCut.self,
            PumpSale.self,
            FuelReception.self,
            FuelLoss.self,
            WorkShift.self,
            CatalogItem.self,
            StockEntry.self,
            Sale.self,
            SaleItem.self
        ])

        let configuration = ModelConfiguration(schema: schema)
        let modelContainer: ModelContainer
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // An older version of the app left an incompatible store: delete it and start fresh.
            print("Resetting local store: \(error)")
            let storeURL = configuration.url
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create the SwiftData container: \(error)")
            }
        }

        // The data lives in Supabase; SwiftData keeps the local copy of the current session.
        let sync = SupabaseConfig.load().map { RemoteSync(client: SupabaseClient(config: $0)) }
        let dataStore = DataStore(context: modelContainer.mainContext, sync: sync)

        container = modelContainer
        _store = State(initialValue: dataStore)
        _session = State(initialValue: SessionStore(store: dataStore))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(session)
                .environment(\.locale, AppFormat.spanishLocale)
                .tint(.brandGreen)
        }
        .modelContainer(container)
    }
}
