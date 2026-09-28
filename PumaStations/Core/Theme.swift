import SwiftUI
import UIKit

// MARK: - Brand colors (adapt automatically to light and dark mode)

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    static let brandGreen = Color(light: 0x00773B, dark: 0x34B86B)
    static let brandRed = Color(light: 0xD0021B, dark: 0xFF5A67)
    static let dieselGray = Color(light: 0x48484D, dark: 0xBDBDC2)
    static let warningAmber = Color(light: 0xA35F00, dark: 0xF2A93B)
    static let screenBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let trackBackground = Color(uiColor: .tertiarySystemFill)
}

extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

// MARK: - Card

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }

    /// Shows an alert while `message` is not nil and clears it when dismissed.
    func errorAlert(_ message: Binding<String?>, title: String = "No se pudo guardar") -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented { message.wrappedValue = nil }
                }
            )
        ) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

// MARK: - Small reusable pieces

struct Pill: View {
    let text: String
    let color: Color
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonLabel(configuration: configuration)
    }

    private struct PrimaryButtonLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Color.brandGreen.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
    }
}

struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 38

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.37, weight: .semibold))
            .foregroundStyle(Color.brandGreen)
            .frame(width: size, height: size)
            .background(Color.brandGreen.opacity(0.14), in: Circle())
    }
}

struct IconSquare: View {
    let systemImage: String
    var color: Color = .brandGreen
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Placeholder where the official Puma Energy logo should be placed.
struct BrandLogoPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(.tertiary)
            .overlay(
                Text("LOGO PUMA ENERGY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            )
    }
}

struct FuelDot: View {
    let fuel: FuelType
    var body: some View {
        Circle()
            .fill(fuel.color)
            .frame(width: 8, height: 8)
    }
}

/// Numeric text field used in forms (decimal keyboard, right aligned, unit suffix).
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String? = nil

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                if let unit {
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
