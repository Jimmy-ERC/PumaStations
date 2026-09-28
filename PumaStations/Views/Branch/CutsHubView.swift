import SwiftUI

/// Today's two cuts plus the history of previous cuts.
struct CutsHubView: View {
    @State private var viewModel: CutsHubViewModel
    @State private var openedCut: SalesCut?
    private let store: DataStore

    init(store: DataStore, branch: Branch) {
        self.store = store
        _viewModel = State(initialValue: CutsHubViewModel(store: store, branch: branch))
    }

    var body: some View {
        List {
            Section {
                ForEach(CutShift.allCases) { shift in
                    TodayCutCard(
                        shift: shift,
                        cut: viewModel.todayCuts[shift],
                        canStart: viewModel.canStart(shift),
                        onStart: { openedCut = viewModel.start(shift) },
                        onOpen: { openedCut = viewModel.todayCuts[shift] }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            } header: {
                Text("Hoy · \(AppFormat.date(.now, format: "EEEE d 'de' MMMM"))")
            } footer: {
                Text("Un corte solo se puede cerrar cuando las \(BusinessRules.pumpsPerBranch) bombas tienen su registro. El sistema consolida los \(BusinessRules.pumpsPerBranch) registros en el reporte del corte.")
            }

            Section("Historial") {
                if viewModel.history.isEmpty {
                    Text("Aún no hay cortes anteriores.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.history) { cut in
                    NavigationLink {
                        if cut.isClosed {
                            CutReportView(store: store, cut: cut, branch: viewModel.branch)
                        } else {
                            CutDetailView(store: store, cut: cut, branch: viewModel.branch)
                        }
                    } label: {
                        HistoryRow(cut: cut)
                    }
                }
            }
        }
        .navigationTitle("Cortes")
        .navigationDestination(item: $openedCut) { cut in
            CutDetailView(store: store, cut: cut, branch: viewModel.branch)
        }
        .errorAlert($viewModel.errorMessage, title: "No se pudo iniciar el corte")
        .onAppear { viewModel.load() }
    }
}

private struct TodayCutCard: View {
    let shift: CutShift
    let cut: SalesCut?
    let canStart: Bool
    let onStart: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shift.title)
                        .font(.headline)
                    Text(shift.hoursText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusPill
            }

            PumpStepsView(registered: Set(cut?.pumpSales.map(\.pumpNumber) ?? []))

            if let cut {
                HStack {
                    Text(summary(of: cut))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(AppFormat.currency(cut.totalSales, decimals: true))
                        .font(.subheadline.weight(.bold))
                }
                Button(cut.isClosed ? "Ver reporte" : "Continuar corte", action: onOpen)
                    .buttonStyle(PrimaryButtonStyle())
            } else if canStart {
                Button("Iniciar corte", action: onStart)
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Text("Disponible cuando se cierre el corte matutino.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.brandGreen, lineWidth: isActive ? 2 : 0)
        )
    }

    private var isActive: Bool {
        guard let cut else { return canStart }
        return !cut.isClosed
    }

    @ViewBuilder
    private var statusPill: some View {
        if let cut {
            if cut.isClosed {
                Pill(text: "Cerrado", color: .brandGreen, systemImage: "checkmark")
            } else {
                Pill(text: "\(cut.registeredPumpCount) de \(BusinessRules.pumpsPerBranch) bombas", color: .warningAmber, systemImage: "clock")
            }
        } else {
            Pill(text: "Sin iniciar", color: .secondary)
        }
    }

    private func summary(of cut: SalesCut) -> String {
        let receptions = cut.receptions.count
        let losses = cut.losses.count
        return "\(AppFormat.gallons(cut.totalGallons.rounded())) · \(receptions) recep. · \(losses) pérd."
    }
}

private struct HistoryRow: View {
    let cut: SalesCut

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(AppFormat.date(cut.day, format: "EEE d MMM").capitalized) · \(cut.shift.displayName)")
                    .font(.subheadline.weight(.medium))
                Text(cut.isClosed ? "\(AppFormat.gallons(cut.totalGallons.rounded())) · cerrado" : "Sin cerrar · \(cut.registeredPumpCount)/\(BusinessRules.pumpsPerBranch) bombas")
                    .font(.caption)
                    .foregroundStyle(cut.isClosed ? Color.secondary : Color.warningAmber)
            }
            Spacer()
            Text(AppFormat.currency(cut.totalSales, decimals: true))
                .font(.subheadline.weight(.semibold))
        }
    }
}
