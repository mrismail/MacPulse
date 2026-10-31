import Foundation

/// Small formatters for battery and electrical values.
public enum NumberFormatting {
    /// A 0–100 percentage, e.g. "82%". Rounded to a whole number.
    public static func percent(_ value: Double, locale: Locale = .current) -> String {
        let whole = Int(value.rounded())
        return "\(whole.formatted(.number.locale(locale)))%"
    }

    /// A value with a unit and at most `fractionDigits` decimals, e.g. "12.6 V", "31.2 °C".
    public static func measurement(
        _ value: Double,
        unit: String,
        fractionDigits: Int = 1,
        locale: Locale = .current
    ) -> String {
        let number = value.formatted(
            .number.precision(.fractionLength(0...fractionDigits)).grouping(.never).locale(locale)
        )
        return "\(number) \(unit)"
    }

    /// A rate in percentage points per hour, e.g. "12.5% per hour".
    public static func percentPerHour(_ value: Double, locale: Locale = .current) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return "\(number)% per hour"
    }
}
