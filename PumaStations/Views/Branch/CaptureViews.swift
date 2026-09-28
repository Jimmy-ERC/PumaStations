import SwiftUI

// MARK: - Pump capture (movement 1)

struct PumpSaleView: View {
    @State private var viewModel: PumpSaleViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: DataStore, cut: SalesCut, branch: Branch, pumpNumber: Int) {
        _viewModel = State(initialValue: PumpSaleViewModel(store: store, cut: cut, branch: branch, pumpNumber: pumpNumber))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PumpStepsView(
                        registered: registeredPumps,
                        current: viewModel.pumpNumber,
                        onSelect: { viewModel.select(pump: $0) }
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("\(viewModel.cut.title.capitalizedFirst) · Bomba \(viewModel.pumpNumber) de \(BusinessRules.pumpsPerBranch)")
                        .frame(maxWidth: .infinity)
                }

                Section {
                    Toggle("Fuera de servicio", isOn: $viewModel.isOutOfService)
                } footer: {
                    Text("Actívalo si la bomba no despachó en este corte: se guarda con ventas en 0 y puedes registrar la falla en Pérdidas o daños.")
                }

                if !viewModel.isOutOfService {
                    ForEach(FuelType.allCases) { fuel in
                        Section {
                            NumberField(title: "Galones vendidos", value: gallonsBinding(for: fuel), unit: "gal")
                            NumberField(title: "Monto", value: amountBinding(for: fuel), unit: "USD")
                        } header: {
                            HStack {
                                FuelDot(fuel: fuel)
                                Text(fuel.displayName)
                                Spacer()
                                Text("Ref. \(AppFormat.currency(fuel.referenceSalePrice, decimals: true))/gal")
                                    .textCase(nil)
                            }
                        }
                    }
                }

                Section {
                    LabeledContent("Galones", value: AppFormat.gallons(viewModel.totalGallons))
                    LabeledContent("Total bomba \(viewModel.pumpNumber)") {
                        Text(AppFormat.currency(viewModel.totalAmount, decimals: true))
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                    }
                } footer: {
                    Text("El monto se calcula con el precio de referencia y puedes corregirlo.")
                }

                Section {
                    Button(saveTitle) { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Bomba \(viewModel.pumpNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .errorAlert($viewModel.errorMessage)
        }
    }

    private var registeredPumps: Set<Int> {
        Set((1...BusinessRules.pumpsPerBranch).filter { viewModel.isRegistered($0) })
    }

    private var saveTitle: String {
        if let next = viewModel.nextPendingPump {
            return "Guardar y seguir con bomba \(next)"
        }
        return "Guardar bomba \(viewModel.pumpNumber)"
    }

    private func save() {
        let next = viewModel.nextPendingPump
        guard viewModel.save() else { return }
        if let next {
            viewModel.select(pump: next)
        } else {
            dismiss()
        }
    }

    private func gallonsBinding(for fuel: FuelType) -> Binding<Double> {
        Binding(
            get: { viewModel.gallons[fuel] ?? 0 },
            set: { viewModel.setGallons($0, for: fuel) }
        )
    }

    private func amountBinding(for fuel: FuelType) -> Binding<Double> {
        Binding(
            get: { viewModel.amounts[fuel] ?? 0 },
            set: { viewModel.amounts[fuel] = $0 }
        )
    }
}

// MARK: - Fuel reception (movement 2)

struct ReceptionFormView: View {
    @State private var viewModel: ReceptionViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: DataStore, cut: SalesCut, branch: Branch) {
        _viewModel = State(initialValue: ReceptionViewModel(store: store, cut: cut, branch: branch))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Combustible") {
                    Picker("Combustible", selection: fuelBinding) {
                        ForEach(FuelType.allCases) { fuel in
                            Text(fuel.displayName).tag(fuel)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("Proveedor", text: $viewModel.supplier)
                    TextField("No. de factura", text: $viewModel.invoiceNumber)
                    DatePicker("Hora", selection: $viewModel.receivedAt, displayedComponents: .hourAndMinute)
                }

                Section {
                    NumberField(title: "Galones recibidos", value: $viewModel.gallons, unit: "gal")
                    NumberField(title: "Costo por galón", value: $viewModel.costPerGallon, unit: "USD")
                    LabeledContent("Total compra") {
                        Text(AppFormat.currency(viewModel.total, decimals: true))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.primary)
                    }
                }

                Section {
                    LabeledContent("Antes", value: "\(AppFormat.gallons(viewModel.stockBefore)) · \(AppFormat.percent(viewModel.stockBefore / max(viewModel.capacity, 1)))")
                    LabeledContent("Después") {
                        Text("\(AppFormat.gallons(viewModel.stockAfter)) · \(AppFormat.percent(viewModel.stockAfter / max(viewModel.capacity, 1)))")
                            .fontWeight(.semibold)
                            .foregroundStyle(viewModel.exceedsCapacity ? Color.brandRed : Color.primary)
                    }
                    ProgressBar(ratio: viewModel.stockAfter / max(viewModel.capacity, 1), color: viewModel.exceedsCapacity ? .brandRed : viewModel.statusAfter.color, height: 12)
                        .padding(.vertical, 4)
                } header: {
                    HStack {
                        Text("Tanque \(viewModel.fuel.displayName)")
                        Spacer()
                        if !viewModel.exceedsCapacity && viewModel.gallons > 0 {
                            TankStatusPill(status: viewModel.statusAfter)
                                .textCase(nil)
                        }
                    }
                } footer: {
                    Text("Capacidad \(AppFormat.gallons(viewModel.capacity)) · espacio libre \(AppFormat.gallons(viewModel.freeSpace)). No se permite recibir más de lo que cabe en el tanque.")
                }

                Section {
                    Button("Guardar recepción") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Recepción")
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

    private var fuelBinding: Binding<FuelType> {
        Binding(
            get: { viewModel.fuel },
            set: { viewModel.selectFuel($0) }
        )
    }

    private func save() {
        if viewModel.save() {
            dismiss()
        }
    }
}

// MARK: - Loss or damage (movement 3)

struct LossFormView: View {
    @State private var viewModel: LossViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: DataStore, cut: SalesCut, branch: Branch) {
        _viewModel = State(initialValue: LossViewModel(store: store, cut: cut, branch: branch))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tipo") {
                    Picker("Tipo", selection: $viewModel.type) {
                        ForEach(LossType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Combustible") {
                    Picker("Combustible", selection: $viewModel.fuel) {
                        ForEach(FuelType.allCases) { fuel in
                            Text(fuel.displayName).tag(fuel)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Origen", selection: $viewModel.pumpNumber) {
                        Text("Tanque").tag(Int?.none)
                        ForEach(viewModel.pumpNumbers, id: \.self) { number in
                            Text("Bomba \(number)").tag(Optional(number))
                        }
                    }
                    NumberField(title: "Galones perdidos", value: $viewModel.gallons, unit: "gal")
                    LabeledContent("Costo estimado", value: AppFormat.currency(viewModel.estimatedCost, decimals: true))
                    TextField("Descripción de lo ocurrido", text: $viewModel.details, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("El origen puede ser el tanque o una de las \(BusinessRules.pumpsPerBranch) bombas. Los galones se descuentan del tanque y aparecen en el reporte del corte.")
                }

                Section {
                    Button("Registrar pérdida") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Pérdida o daño")
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
