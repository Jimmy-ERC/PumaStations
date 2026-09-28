import SwiftUI
import SwiftData

@main
struct PumaStationsApp: App {
    private let container: ModelContainer
    @State private var store: DataStore
    @State private var session = SessionStore()

    init() {
        let schema = Schema([
            UserAccount.self,
            Branch.self,
            Pump.self,
            SalesCut.self,
            PumpSale.self,
            FuelReception.self,
            FuelLoss.self
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

        let dataStore = DataStore(context: modelContainer.mainContext)
        // Loads demo data only the first time the app runs.
        SeedDataService.seedIfNeeded(store: dataStore)

        container = modelContainer
        _store = State(initialValue: dataStore)
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
