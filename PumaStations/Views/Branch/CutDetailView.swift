import SwiftUI

/// Pump selected to capture its sales (used to present the capture sheet).
struct PumpSelection: Identifiable {
    let number: Int
    var id: Int { number }
}

/// One cut: the 6 pumps (sales), fuel receptions and losses.
struct CutDetailView: View {
    @State private var viewModel: CutDetailViewModel
    @State private var selectedPump: PumpSelection?
    @State private var isShowingReception = false
    @State private var isShowingLoss = false
    private let store: DataStore

    init(store: DataStore, cut: SalesCut, branch: Branch) {
        self.store = store
        _viewModel = State(initialValue: CutDetailViewModel(store: store, cut: cut, branch: branch))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(AppFormat.date(viewModel.cut.day, format: "EEE d MMM").capitalized) · \(viewModel.cut.shift.hoursText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if viewModel.cut.isClosed {
                            Pill(text: "Cerrado", color: .brandGreen, systemImage: "lock.fill")
                        } else {
                            Pill(text: "\(viewModel.registeredCount) de \(BusinessRules.pumpsPerBranch) bombas", color: .warningAmber)
                        }
                    }
                    ProgressBar(ratio: viewModel.progress, color: .brandGreen, height: 10)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(viewModel.slots) { slot in
                    Button {
                        selectedPump = PumpSelection(number: slot.number)
                    } label: {
                        PumpSlotRow(slot: slot)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.isEditable)
                }
            } header: {
                Text("1 · Ventas por bomba (obligatorio)")
            }

            Section {
                ForEach(viewModel.receptions) { reception in
                    ReceptionRow(reception: reception)
                        .swipeActions {
                            if viewModel.isEditable {
                                Button("Eliminar", role: .destructive) { viewModel.delete(reception) }
                            }
                        }
                }
                if viewModel.isEditable {
                    Button {
                        isShowingReception = true
                    } label: {
                        Label(viewModel.receptions.isEmpty ? "Registrar recepción · sin recepciones en este corte" : "Registrar recepción", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("2 · Compras / recepción de combustible")
            }

            Section {
                ForEach(viewModel.losses) { loss in
                    LossRow(loss: loss)
                        .swipeActions {
                            if viewModel.isEditable {
                                Button("Eliminar", role: .destructive) { viewModel.delete(loss) }
                            }
                        }
                }
                if viewModel.isEditable {
                    Button {
                        isShowingLoss = true
                    } label: {
                        Label("Registrar pérdida o daño", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("3 · Pérdidas o daños")
            } footer: {
                Text("Merma, fuga, falla técnica o derrame. Se descuentan del inventario al cerrar el corte.")
            }

            Section {
                LabeledContent("Ventas registradas") {
                    Text(AppFormat.currency(viewModel.cut.totalSales, decimals: true))
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                }
                NavigationLink {
                    CutReportView(store: store, cut: viewModel.cut, branch: viewModel.branch)
                } label: {
                    Label(closeLabel, systemImage: viewModel.cut.isClosed ? "doc.text" : "lock")
                        .fontWeight(.semibold)
                }
                .disabled(!viewModel.cut.isClosed && viewModel.missingCount > 0)
            }
        }
        .navigationTitle(viewModel.cut.title.capitalizedFirst)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.isEditable, let next = viewModel.nextPendingPump {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bomba \(next)") {
                        selectedPump = PumpSelection(number: next)
                    }
                }
            }
        }
        .sheet(item: $selectedPump, onDismiss: { viewModel.load() }) { selection in
            PumpSaleView(store: store, cut: viewModel.cut, branch: viewModel.branch, pumpNumber: selection.number)
        }
        .sheet(isPresented: $isShowingReception, onDismiss: { viewModel.load() }) {
            ReceptionFormView(store: store, cut: viewModel.cut, branch: viewModel.branch)
        }
        .sheet(isPresented: $isShowingLoss, onDismiss: { viewModel.load() }) {
            LossFormView(store: store, cut: viewModel.cut, branch: viewModel.branch)
        }
        .errorAlert($viewModel.errorMessage)
        .onAppear { viewModel.load() }
    }

    private var closeLabel: String {
        if viewModel.cut.isClosed { return "Ver reporte consolidado" }
        if viewModel.missingCount > 0 {
            return viewModel.missingCount == 1 ? "Cerrar corte · falta 1 bomba" : "Cerrar corte · faltan \(viewModel.missingCount) bombas"
        }
        return "Revisar y cerrar corte"
    }
}

private struct PumpSlotRow: View {
    let slot: PumpSlot

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(
                systemImage: slot.isRegistered ? "checkmark" : "fuelpump",
                color: slot.isRegistered ? .brandGreen : .secondary,
                size: 34
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("Bomba \(slot.number)")
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let sale = slot.sale {
                Text(AppFormat.currency(sale.totalAmount, decimals: true))
                    .font(.subheadline.weight(.semibold))
            } else {
                Pill(text: "Pendiente", color: .warningAmber)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        guard let sale = slot.sale else { return "Sin registrar" }
        if sale.isOutOfService { return "Fuera de servicio" }
        return "\(AppFormat.gallons(sale.totalGallons)) registrados"
    }
}

struct ReceptionRow: View {
    let reception: FuelReception

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(systemImage: "truck.box", color: .brandGreen, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(reception.fuel.displayName) · \(AppFormat.gallons(reception.gallons))")
                    .font(.subheadline.weight(.medium))
                Text("\(reception.supplier) · Factura \(reception.invoiceNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(AppFormat.currency(reception.total, decimals: true))
                .font(.subheadline.weight(.semibold))
        }
    }
}

extension String {
    /// "corte matutino" → "Corte matutino".
    var capitalizedFirst: String {
        self.prefix(1).uppercased() + String(self.dropFirst())
    }
}
