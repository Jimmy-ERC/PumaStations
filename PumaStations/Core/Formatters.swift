import Foundation

enum AppFormat {
    static let usLocale = Locale(identifier: "en_US")
    static let spanishLocale = Locale(identifier: "es_SV")

    static func currency(_ value: Double, decimals: Bool = false) -> String {
        value.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(decimals ? 2 : 0))
                .locale(usLocale)
        )
    }

    static func compactCurrency(_ value: Double) -> String {
        if abs(value) >= 1_000 {
            return "$" + (value / 1_000).formatted(.number.precision(.fractionLength(0...1)).locale(usLocale)) + "k"
        }
        return currency(value)
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(usLocale))
    }

    static func gallons(_ value: Double) -> String {
        number(value) + " gal"
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0...1)).locale(usLocale))
    }

    static func date(_ date: Date, format: String = "d MMM yyyy") -> String {
        let formatter = DateFormatter()
        formatter.locale = spanishLocale
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

enum AppCalendar {
    /// Gregorian calendar with weeks starting on Monday.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppFormat.spanishLocale
        calendar.firstWeekday = 2
        return calendar
    }()
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
