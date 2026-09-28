import SwiftUI

/// Consolidated report of a cut: the 6 pump records, receptions, losses and tank inventory.
/// For an open cut it also closes it.
struct CutReportView: View {
    @State private var viewModel: CutReportViewModel
    @State private var isConfirmingClose = false
    @Environment(\.dismiss) private var dismiss

    init(store: DataStore, cut: SalesCut, branch: Branch) {
        _viewModel = State(initialValue: CutReportViewModel(store: store, cut: cut, branch: branch))
    }

    private var cut: SalesCut { viewModel.cut }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusBanner

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(cut.title.capitalizedFirst) · \(AppFormat.date(cut.day, format: "EEE d MMM").capitalized)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(AppFormat.currency(cut.totalSales, decimals: true))
                        .font(.system(size: 34, weight: .bold))
                    Text("\(AppFormat.gallons(cut.totalGallons)) vendidos · \(viewModel.branch.name)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .cardStyle()

                pumpsTable

                HStack(spacing: 12) {
                    StatTile(
                        systemImage: "truck.box",
                        title: "2 · Recepciones",
                        value: AppFormat.gallons(cut.receptions.reduce(0) { $0 + $1.gallons }),
                        subtitle: cut.receptions.isEmpty ? "Sin compras" : AppFormat.currency(cut.totalPurchases, decimals: true)
                    )
                    StatTile(
                        systemImage: "exclamationmark.triangle",
                        title: "3 · Pérdidas",
                        value: AppFormat.gallons(cut.totalLossGallons),
                        subtitle: cut.losses.isEmpty ? "Sin pérdidas" : "\(cut.losses.count) registro(s)",
                        valueColor: cut.totalLossGallons > 0 ? .brandRed : .primary
                    )
                }

                if !cut.receptions.isEmpty || !cut.losses.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Detalle de movimientos")
                        ForEach(cut.receptions) { reception in
                            ReceptionRow(reception: reception)
                        }
                        ForEach(cut.losses) { loss in
                            LossRow(loss: loss)
                        }
                    }
                    .cardStyle()
                }

                inventoryTable

                if !cut.isClosed {
                    Text("Al cerrar, el corte queda bloqueado para edición y se actualizan los niveles y alertas de los tanques.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        isConfirmingClose = true
                    } label: {
                        Label("Cerrar \(cut.title)", systemImage: "lock.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!viewModel.canClose)
                }
            }
            .padding(16)
        }
        .background(Color.screenBackground)
        .navigationTitle(cut.isClosed ? "Reporte del corte" : "Cerrar corte")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("¿Cerrar el corte?", isPresented: $isConfirmingClose, titleVisibility: .visible) {
            Button("Cerrar corte") {
                if viewModel.close() {
                    dismiss()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Ya no podrás modificar sus registros.")
        }
        .errorAlert($viewModel.errorMessage, title: "No se pudo cerrar el corte")
        .onAppear { viewModel.load() }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if cut.isClosed {
            banner(
                icon: "lock.fill",
                title: "Corte cerrado",
                message: cut.closedAt.map { "Cerrado el \(AppFormat.date($0, format: "d MMM, h:mm a"))." } ?? "",
                color: .brandGreen
            )
        } else if cut.isReadyToClose {
            banner(icon: "checkmark.circle.fill", title: "\(BusinessRules.pumpsPerBranch) de \(BusinessRules.pumpsPerBranch) bombas registradas", message: "Revisa el reporte consolidado antes de cerrar.", color: .brandGreen)
        } else {
            banner(
                icon: "exclamationmark.triangle.fill",
                title: "Faltan bombas por registrar",
                message: "Registradas \(cut.registeredPumpCount) de \(BusinessRules.pumpsPerBranch).",
                color: .warningAmber
            )
        }
    }

    private func banner(icon: String, title: String, message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(14)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var pumpsTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "1 · Ventas por bomba", trailing: "galones")
            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    Text("Bomba").gridColumnAlignment(.leading)
                    ForEach(FuelType.allCases) { fuel in
                        Text(fuel.displayName)
                    }
                    Text("Monto")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                ForEach(viewModel.sales) { sale in
                    GridRow {
                        Text("B\(sale.pumpNumber)")
                        if sale.isOutOfService {
                            Text("Fuera de servicio")
                                .foregroundStyle(.secondary)
                                .gridCellColumns(FuelType.allCases.count)
                        } else {
                            ForEach(FuelType.allCases) { fuel in
                                Text(AppFormat.number(sale.gallons(fuel).rounded()))
                            }
                        }
                        Text(AppFormat.currency(sale.totalAmount, decimals: true))
                    }
                    .font(.caption.weight(.medium))
                }
                Divider()
                GridRow {
                    Text("Total")
                    ForEach(FuelType.allCases) { fuel in
                        Text(AppFormat.number(cut.gallonsSold(fuel).rounded()))
                    }
                    Text(AppFormat.currency(cut.totalSales, decimals: true))
                }
                .font(.caption.weight(.bold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .cardStyle()
    }

    private var inventoryTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Inventario de tanques", trailing: "galones")
            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    Text("Tanque").gridColumnAlignment(.leading)
                    Text("Inicial")
                    Text("Recib.")
                    Text("Vend.")
                    Text("Pérd.")
                    Text("Final")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                ForEach(viewModel.inventory) { row in
                    GridRow {
                        HStack(spacing: 4) {
                            FuelDot(fuel: row.fuel)
                            Text(row.fuel.displayName)
                        }
                        Text(AppFormat.number(row.opening.rounded()))
                        Text("+\(AppFormat.number(row.received.rounded()))")
                        Text("−\(AppFormat.number(row.sold.rounded()))")
                        Text(row.lost > 0 ? "−\(AppFormat.number(row.lost.rounded(toPlaces: 1)))" : "0")
                            .foregroundStyle(row.lost > 0 ? Color.brandRed : Color.primary)
                        Text(AppFormat.number(row.closing.rounded()))
                            .fontWeight(.bold)
                            .foregroundStyle(row.closing < 0 ? Color.brandRed : Color.primary)
                    }
                    .font(.caption)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .cardStyle()
    }
}
