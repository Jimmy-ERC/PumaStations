import Foundation

/// Deterministic random generator so the demo data is the same on every install.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Creates demo data the first time the app runs (only when there are no users).
enum SeedDataService {

    static let demoPassword = "Puma2026"
    private static let historyDays = 45
    private static let supplier = "Puma Energy El Salvador"

    private struct BranchSeed {
        let name: String
        let code: String
        let address: String
        let municipality: String
        let capacities: [FuelType: Double]
        /// Stock left at the end of the demo, chosen to show every alert level.
        let currentStock: [FuelType: Double]
        let volumeFactor: Double
        let manager: (first: String, last: String, email: String, dui: String)
        /// Pumps already registered today in the evening cut (nil = evening cut not started).
        let eveningPumpsToday: Int?
    }

    /// Bump this number when the demo data changes: the local data is wiped and seeded again.
    private static let seedVersion = 2
    private static let seedVersionKey = "seedVersion"

    static func seedIfNeeded(store: DataStore) {
        let defaults = UserDefaults.standard
        let isCurrentVersion = defaults.integer(forKey: seedVersionKey) == seedVersion
        guard !isCurrentVersion || store.users().isEmpty else { return }

        store.deleteAllData()
        seed(store: store)
        defaults.set(seedVersion, forKey: seedVersionKey)
    }

    private static func seed(store: DataStore) {

        var rng = SeededGenerator(seed: 2026)
        let calendar = AppCalendar.calendar
        let today = calendar.startOfDay(for: .now)
        let passwordHash = PasswordHasher.hash(demoPassword)
        var invoiceCounter = 88_000

        store.insert(UserAccount(
            firstName: "Elena",
            lastName: "Guevara",
            email: "gerente@puma.sv",
            passwordHash: passwordHash,
            role: .generalManager,
            dui: "01234567-8",
            phone: "7000-0001"
        ))

        for seed in branchSeeds {
            let branch = store.createBranch(
                name: seed.name,
                code: seed.code,
                address: seed.address,
                municipality: seed.municipality,
                phone: "2200-0000",
                capacities: seed.capacities
            )
            branch.createdAt = calendar.date(byAdding: .day, value: -historyDays - 10, to: today) ?? today
            for fuel in FuelType.allCases {
                branch.setStock((seed.capacities[fuel] ?? 0) * 0.75, for: fuel)
            }

            let manager = UserAccount(
                firstName: seed.manager.first,
                lastName: seed.manager.last,
                email: seed.manager.email,
                passwordHash: passwordHash,
                role: .branchManager,
                dui: seed.manager.dui,
                phone: "7100-0000"
            )
            store.insert(manager)
            manager.branch = branch

            // Closed history: every day, both cuts, all 6 pumps.
            for dayOffset in stride(from: historyDays, through: 0, by: -1) {
                guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }

                for shift in CutShift.allCases {
                    let isToday = dayOffset == 0
                    var pumpsToRegister = BusinessRules.pumpsPerBranch
                    if isToday && shift == .evening {
                        guard let partial = seed.eveningPumpsToday else { continue }
                        pumpsToRegister = partial
                    }

                    let cut = SalesCut(day: day, shift: shift, openedAt: calendar.date(byAdding: .hour, value: shift == .morning ? 6 : 14, to: day) ?? day)
                    store.insert(cut)
                    cut.branch = branch

                    // 1. Sales per pump.
                    for number in 1...pumpsToRegister {
                        let sale = PumpSale(pumpNumber: number, recordedAt: cut.referenceDate)
                        for fuel in FuelType.allCases {
                            let base: Double
                            switch fuel {
                            case .diesel: base = 110
                            case .regular: base = 150
                            case .premium: base = 70
                            }
                            let gallons = (base * seed.volumeFactor * Double.random(in: 0.8...1.2, using: &rng)).rounded(toPlaces: 2)
                            sale.setValues(gallons: gallons, amount: (gallons * fuel.referenceSalePrice).rounded(toPlaces: 2), for: fuel)
                        }
                        store.insert(sale)
                        sale.cut = cut
                    }

                    // 2. Receptions: in the morning cut, restock tanks below 45 %.
                    if shift == .morning && !isToday {
                        for fuel in FuelType.allCases {
                            let capacity = branch.capacity(for: fuel)
                            let stock = branch.stock(for: fuel)
                            guard stock < capacity * 0.45 else { continue }
                            let gallons = ((capacity * 0.9 - stock) / 1_000).rounded(.down) * 1_000
                            guard gallons > 0 else { continue }
                            invoiceCounter += 1
                            let reception = FuelReception(
                                fuel: fuel,
                                gallons: gallons,
                                costPerGallon: fuel.referenceCost,
                                supplier: supplier,
                                invoiceNumber: "F-\(invoiceCounter)",
                                receivedAt: calendar.date(byAdding: .hour, value: 8, to: day) ?? day
                            )
                            store.insert(reception)
                            reception.cut = cut
                        }
                    }

                    // 3. Losses: small shrinkage every 9 days, plus one leak in Soyapango.
                    if shift == .evening && dayOffset % 9 == 4 {
                        let fuel = FuelType.allCases[Int.random(in: 0..<3, using: &rng)]
                        addLoss(to: cut, store: store, type: .shrinkage, fuel: fuel,
                                gallons: Double.random(in: 8...20, using: &rng).rounded(toPlaces: 1),
                                pump: nil, details: "Evaporación registrada en la medición del tanque.")
                    }
                    if seed.code == "SUC-003" && dayOffset == 2 && shift == .morning {
                        addLoss(to: cut, store: store, type: .leak, fuel: .premium, gallons: 310, pump: 4,
                                details: "Manguera de Súper dañada; se aisló y se reportó a mantenimiento.")
                    }
                    if seed.code == "SUC-001" && isToday && shift == .evening {
                        addLoss(to: cut, store: store, type: .shrinkage, fuel: .regular, gallons: 12, pump: nil,
                                details: "Evaporación en tanque Regular.")
                    }

                    // Close every cut except today's evening cut.
                    if !(isToday && shift == .evening) {
                        for fuel in FuelType.allCases {
                            let opening = branch.stock(for: fuel)
                            cut.setOpeningStock(opening, for: fuel)
                            branch.setStock(max(opening + cut.netMovement(fuel), 0), for: fuel)
                        }
                        cut.statusRaw = CutStatus.closed.rawValue
                        cut.closedAt = calendar.date(byAdding: .hour, value: shift == .morning ? 14 : 22, to: day)
                    }
                }
            }

            // Current stock tuned to show critical, medium and optimal tanks.
            for fuel in FuelType.allCases {
                branch.setStock(seed.currentStock[fuel] ?? 0, for: fuel)
            }
        }

        // A branch without manager and a manager without branch, to show the linking flow.
        store.createBranch(
            name: "Puma Merliot",
            code: "SUC-004",
            address: "Calle Chiltiupán",
            municipality: "Antiguo Cuscatlán",
            phone: "2200-0004",
            capacities: [.diesel: 10_000, .regular: 12_000, .premium: 8_000]
        )
        store.insert(UserAccount(
            firstName: "Gabriela",
            lastName: "Flores",
            email: "gflores@puma.sv",
            passwordHash: passwordHash,
            role: .branchManager,
            dui: "04567891-2",
            phone: "7012-3456"
        ))

        do {
            try store.save()
        } catch {
            print("Seeding failed: \(error)")
        }
    }

    private static func addLoss(to cut: SalesCut, store: DataStore, type: LossType, fuel: FuelType, gallons: Double, pump: Int?, details: String) {
        let loss = FuelLoss(type: type, fuel: fuel, gallons: gallons, pumpNumber: pump, details: details, recordedAt: cut.referenceDate)
        store.insert(loss)
        loss.cut = cut
    }

    private static let branchSeeds: [BranchSeed] = [
        BranchSeed(
            name: "Puma Escalón",
            code: "SUC-001",
            address: "Paseo General Escalón",
            municipality: "San Salvador",
            capacities: [.diesel: 10_000, .regular: 12_000, .premium: 8_000],
            currentStock: [.diesel: 3_500, .regular: 2_150, .premium: 5_480],
            volumeFactor: 1.0,
            manager: ("Roberto", "Martínez", "rmartinez@puma.sv", "03456789-1"),
            eveningPumpsToday: 4
        ),
        BranchSeed(
            name: "Puma Santa Tecla",
            code: "SUC-002",
            address: "Carretera Panamericana km 12",
            municipality: "Santa Tecla",
            capacities: [.diesel: 10_000, .regular: 12_000, .premium: 8_000],
            currentStock: [.diesel: 6_200, .regular: 3_840, .premium: 5_680],
            volumeFactor: 0.85,
            manager: ("Andrea", "López", "alopez@puma.sv", "02345678-9"),
            eveningPumpsToday: nil
        ),
        BranchSeed(
            name: "Puma Soyapango",
            code: "SUC-003",
            address: "Bulevar del Ejército",
            municipality: "Soyapango",
            capacities: [.diesel: 8_000, .regular: 10_000, .premium: 6_000],
            currentStock: [.diesel: 5_100, .regular: 6_300, .premium: 820],
            volumeFactor: 0.7,
            manager: ("Carlos", "Hernández", "chernandez@puma.sv", "05678912-3"),
            eveningPumpsToday: 2
        )
    ]
}
