import SwiftUI

// MARK: - Pills

struct StockStatusPill: View {
    let level: StockLevel

    var body: some View {
        Pill(text: text, color: level.status.color)
    }

    private var text: String {
        level.status == .out ? level.status.displayName : "\(level.available) uds."
    }
}

struct AttendancePill: View {
    let status: AttendanceStatus

    var body: some View {
        Pill(text: status.displayName, color: status.color, systemImage: status.systemImage)
    }
}

// MARK: - Store and maintenance sales

/// Sales of convenience products, lubricants and maintenance services in a period.
struct StoreSalesCard: View {
    var title = "Tienda y mantenimiento"
    let metrics: StoreMetrics

    private var maxAmount: Double {
        max(metrics.categories.map(\.amount).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: title, trailing: AppFormat.currency(metrics.total, decimals: true))
            ForEach(metrics.categories) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: row.category.systemImage)
                            .font(.footnote)
                            .foregroundStyle(row.category.color)
                            .frame(width: 18)
                        Text(row.category.displayName)
                            .font(.subheadline)
                        Spacer()
                        Text(AppFormat.currency(row.amount, decimals: true))
                            .font(.subheadline.weight(.semibold))
                    }
                    ProgressBar(ratio: row.amount / maxAmount, color: row.category.color)
                }
            }
            Divider()
            HStack {
                Text(metrics.tickets == 1 ? "1 venta" : "\(metrics.tickets) ventas")
                Spacer()
                Text("Ticket promedio \(AppFormat.currency(metrics.averageTicket, decimals: true))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

/// Row of a store ticket or a maintenance order.
struct SaleRow: View {
    let sale: Sale
    var showsSeller = true

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(
                systemImage: sale.kind.systemImage,
                color: sale.kind == .store ? .brandGreen : .dieselGray,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(sale.summary)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(AppFormat.currency(sale.total, decimals: true))
                .font(.subheadline.weight(.semibold))
        }
    }

    private var subtitle: String {
        var parts = [AppFormat.date(sale.soldAt, format: "d MMM · h:mm a")]
        if !sale.vehiclePlate.isEmpty {
            parts.append(sale.vehiclePlate)
        }
        if showsSeller, let seller = sale.seller {
            parts.append(seller.fullName)
        }
        return parts.joined(separator: " · ")
    }
}

/// Detail of a sale: its lines, payment and who registered it.
struct SaleDetailView: View {
    let sale: Sale

    private var lines: [SaleItem] {
        sale.items.sorted { ($0.item?.name ?? "") < ($1.item?.name ?? "") }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Tipo", value: sale.kind.displayName)
                LabeledContent("Fecha", value: AppFormat.date(sale.soldAt, format: "d MMM yyyy · h:mm a"))
                LabeledContent("Pago", value: sale.payment.displayName)
                if !sale.vehiclePlate.isEmpty {
                    LabeledContent("Placa", value: sale.vehiclePlate)
                }
                LabeledContent("Atendió", value: sale.seller?.fullName ?? "—")
                if let branch = sale.branch {
                    LabeledContent("Sucursal", value: branch.name)
                }
            }

            Section(sale.kind == .store ? "Productos" : "Servicios") {
                ForEach(lines) { line in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.item?.name ?? "Artículo")
                                .font(.subheadline)
                            Text("\(line.quantity) × \(AppFormat.currency(line.unitPrice, decimals: true))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(AppFormat.currency(line.total, decimals: true))
                            .font(.subheadline.weight(.medium))
                    }
                }
                HStack {
                    Text("Total")
                    Spacer()
                    Text(AppFormat.currency(sale.total, decimals: true))
                }
                .font(.headline)
            }
        }
        .navigationTitle(sale.kind == .store ? "Venta de tienda" : "Orden de mantenimiento")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Row of a work shift with its attendance.
struct WorkShiftRow: View {
    let workShift: WorkShift
    var showsDate = true

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(systemImage: workShift.shift == .morning ? "sun.max" : "moon", color: status.color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(workShift.attendanceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AttendancePill(status: status)
        }
    }

    private var status: AttendanceStatus {
        workShift.status()
    }

    private var title: String {
        let shift = "Turno \(workShift.shift.displayName.lowercased())"
        guard showsDate else { return shift }
        return "\(AppFormat.date(workShift.day, format: "EEE d MMM").capitalized) · \(workShift.shift.displayName)"
    }
}
