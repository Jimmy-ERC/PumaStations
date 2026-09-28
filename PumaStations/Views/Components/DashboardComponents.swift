import SwiftUI
import Charts

// MARK: - Basic pieces

struct CardHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProgressBar: View {
    let ratio: Double
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.trackBackground)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(ratio, 0), 1))
            }
        }
        .frame(height: height)
    }
}

struct StatTile: View {
    let systemImage: String
    let title: String
    let value: String
    var subtitle: String? = nil
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct FilterChip: View {
    let systemImage: String
    let text: String
    var isHighlighted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .background(isHighlighted ? Color.brandGreen : Color.cardBackground, in: Capsule())
    }
}

// MARK: - Tank status

struct TankStatusPill: View {
    let status: TankStatus

    var body: some View {
        Pill(text: status.displayName, color: status.color, systemImage: status.systemImage)
    }
}

struct TankLevelRow: View {
    let tank: TankLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                FuelDot(fuel: tank.fuel)
                Text(tank.fuel.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                TankStatusPill(status: tank.status)
            }
            ProgressBar(ratio: tank.ratio, color: tank.status.color, height: 12)
            HStack {
                Text("\(AppFormat.number(tank.stock)) de \(AppFormat.gallons(tank.capacity)) · \(AppFormat.percent(tank.ratio))")
                Spacer()
                Text(daysText)
                    .fontWeight(.semibold)
                    .foregroundStyle(tank.status == .optimal ? Color.secondary : tank.status.color)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var daysText: String {
        guard let days = tank.daysLeft else { return "Sin ventas recientes" }
        return "≈ \(AppFormat.number(days.rounded(toPlaces: 1))) días"
    }
}

struct TankLevelsCard: View {
    var title = "Nivel de tanques"
    var subtitle: String? = nil
    let tanks: [TankLevel]
    var showsLegend = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeader(title: title, trailing: subtitle)
            ForEach(tanks) { tank in
                TankLevelRow(tank: tank)
            }
            if showsLegend {
                Divider()
                Text(TankStatus.legend)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
}

/// Red or amber banner that recommends restocking a tank.
struct RestockBanner: View {
    let tank: TankLevel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(tank.status == .critical ? "Reabastecer \(tank.fuel.displayName) hoy" : "\(tank.fuel.displayName) en nivel medio")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(tank.status.color)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tank.status.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var message: String {
        var text = "Existencia: \(AppFormat.gallons(tank.stock))"
        if let days = tank.daysLeft {
            text += " · ≈ \(AppFormat.number(days.rounded(toPlaces: 1))) días de venta"
        }
        if tank.suggestedOrder > 0 {
            text += ". Sugerido: pedir \(AppFormat.gallons(tank.suggestedOrder))."
        }
        return text
    }
}

/// Matrix branch × fuel with the tank level and its status color.
struct TankMatrixCard: View {
    let rows: [BranchTanks]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Tanques por sucursal", trailing: "Nivel actual")
            Grid(alignment: .center, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    Text("Sucursal").gridColumnAlignment(.leading)
                    ForEach(FuelType.allCases) { fuel in
                        Text(fuel.displayName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                ForEach(rows) { row in
                    GridRow {
                        Text(row.name.replacingOccurrences(of: "Puma ", with: ""))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        ForEach(row.levels) { level in
                            HStack(spacing: 5) {
                                Circle().fill(level.status.color).frame(width: 9, height: 9)
                                Text(AppFormat.percent(level.ratio))
                            }
                            .font(.caption.weight(.medium))
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                ForEach([TankStatus.optimal, .medium, .critical], id: \.rawValue) { status in
                    HStack(spacing: 5) {
                        Circle().fill(status.color).frame(width: 8, height: 8)
                        Text(status.displayName)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

// MARK: - Sales

struct SalesKPICard: View {
    let title: String
    let metrics: DashboardMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(AppFormat.currency(metrics.totalSales))
                .font(.system(size: 34, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let change = metrics.salesChange {
                HStack(spacing: 6) {
                    Pill(
                        text: (change >= 0 ? "▲ " : "▼ ") + AppFormat.percent(abs(change)),
                        color: change >= 0 ? Color.brandGreen : Color.brandRed
                    )
                    Text("vs. periodo anterior")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .padding(.vertical, 10)

            HStack(spacing: 12) {
                column(title: "Volumen vendido", value: AppFormat.gallons(metrics.totalGallons), color: .primary)
                Divider()
                column(title: "Margen bruto", value: AppFormat.currency(metrics.margin), color: metrics.margin >= 0 ? .brandGreen : .brandRed)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private func column(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stacked bars of sales per period, split by fuel.
struct SalesChartCard: View {
    let buckets: [ChartBucket]
    var fuels: [FuelType] = FuelType.allCases

    private struct Point: Identifiable {
        let id = UUID()
        let label: String
        let fuel: String
        let value: Double
    }

    private var points: [Point] {
        buckets.flatMap { bucket in
            fuels.map { Point(label: bucket.label, fuel: $0.displayName, value: bucket.sales[$0] ?? 0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Ventas", trailing: "Por combustible")
            if buckets.isEmpty {
                Text("Sin datos en este periodo")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Periodo", point.label),
                        y: .value("Ventas", point.value)
                    )
                    .foregroundStyle(by: .value("Combustible", point.fuel))
                    .cornerRadius(3)
                }
                .chartForegroundStyleScale(
                    domain: FuelType.allCases.map(\.displayName),
                    range: FuelType.allCases.map(\.color)
                )
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(AppFormat.compactCurrency(amount))
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 210)
            }
        }
        .cardStyle()
    }
}

struct FuelVolumeCard: View {
    var title = "Consumo por combustible"
    let gallons: [FuelType: Double]

    private var maxValue: Double {
        max(gallons.values.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: title, trailing: AppFormat.gallons(gallons.values.reduce(0, +)))
            ForEach(FuelType.allCases) { fuel in
                let value = gallons[fuel] ?? 0
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        FuelDot(fuel: fuel)
                        Text(fuel.displayName)
                            .font(.subheadline)
                        Spacer()
                        Text(AppFormat.gallons(value))
                            .font(.subheadline.weight(.semibold))
                    }
                    ProgressBar(ratio: value / maxValue, color: fuel.color)
                }
            }
        }
        .cardStyle()
    }
}

struct FuelSalesTableCard: View {
    let metrics: DashboardMetrics
    var fuels: [FuelType] = FuelType.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Ventas por combustible")
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Combustible").gridColumnAlignment(.leading)
                    Text("Galones")
                    Text("Ventas")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                ForEach(fuels) { fuel in
                    GridRow {
                        HStack(spacing: 6) {
                            FuelDot(fuel: fuel)
                            Text(fuel.displayName)
                        }
                        Text(AppFormat.number(metrics.gallons(fuel).rounded()))
                        Text(AppFormat.currency(metrics.sales(fuel)))
                    }
                    .font(.subheadline)
                }
                Divider()
                GridRow {
                    Text("Total")
                    Text(AppFormat.number(metrics.totalGallons.rounded()))
                    Text(AppFormat.currency(metrics.totalSales))
                }
                .font(.subheadline.weight(.bold))
            }
        }
        .cardStyle()
    }
}

struct BranchSalesTableCard: View {
    let rows: [BranchMetricRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Por sucursal")
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Sucursal").gridColumnAlignment(.leading)
                    Text("Galones")
                    Text("Ventas")
                    Text("Margen")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                ForEach(rows) { row in
                    GridRow {
                        Text(row.name.replacingOccurrences(of: "Puma ", with: ""))
                        Text(AppFormat.number(row.totalGallons.rounded()))
                        Text(AppFormat.currency(row.totalSales))
                        Text(AppFormat.currency(row.margin))
                            .foregroundStyle(row.margin >= 0 ? Color.brandGreen : Color.brandRed)
                    }
                    .font(.caption.weight(.medium))
                }
                Divider()
                GridRow {
                    Text("Total")
                    Text(AppFormat.number(rows.reduce(0) { $0 + $1.totalGallons }.rounded()))
                    Text(AppFormat.currency(rows.reduce(0) { $0 + $1.totalSales }))
                    Text(AppFormat.currency(rows.reduce(0) { $0 + $1.margin }))
                        .foregroundStyle(Color.brandGreen)
                }
                .font(.caption.weight(.bold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .cardStyle()
    }
}

// MARK: - Cuts

/// Row of 6 boxes (B1…B6) showing which pumps are registered.
struct PumpStepsView: View {
    let registered: Set<Int>
    var current: Int? = nil
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...BusinessRules.pumpsPerBranch, id: \.self) { number in
                let isCurrent = number == current
                let isDone = registered.contains(number)
                Text("B\(number)")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .foregroundStyle(isCurrent ? Color.white : (isDone ? Color.brandGreen : Color.secondary))
                    .background(
                        isCurrent ? Color.brandGreen : (isDone ? Color.brandGreen.opacity(0.14) : Color.trackBackground),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect?(number) }
                    .accessibilityLabel("Bomba \(number)\(isDone ? ", registrada" : ", pendiente")")
            }
        }
    }
}

/// Compact row with the state of one of today's cuts.
struct CutStatusRow: View {
    let shift: CutShift
    let cut: SalesCut?

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(systemImage: icon, color: color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Corte \(shift.displayName.lowercased())")
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let cut, cut.isClosed {
                Text(AppFormat.currency(cut.totalSales, decimals: true))
                    .font(.subheadline.weight(.semibold))
            } else if cut != nil {
                Pill(text: "En proceso", color: .warningAmber)
            } else {
                Pill(text: "Sin iniciar", color: .secondary)
            }
        }
    }

    private var icon: String {
        guard let cut else { return "circle.dashed" }
        return cut.isClosed ? "checkmark" : "clock"
    }

    private var color: Color {
        guard let cut else { return .secondary }
        return cut.isClosed ? .brandGreen : .warningAmber
    }

    private var subtitle: String {
        guard let cut else { return shift.hoursText }
        let pumps = "\(cut.registeredPumpCount)/\(BusinessRules.pumpsPerBranch) bombas"
        if cut.isClosed { return "\(pumps) · cerrado" }
        return "\(pumps) · \(AppFormat.currency(cut.totalSales, decimals: true)) hasta ahora"
    }
}
