import Foundation

/// Locale-aware formatters for battery and electrical values, built on Foundation
/// format styles so digits, separators, percent placement and units follow the user's
/// locale (including Arabic digits and right-to-left layout).
public enum NumberFormatting {
    /// A 0–100 percentage, e.g. "82%" (en) or "٨٢٪" (ar). Rounded to a whole number.
    public static func percent(_ value: Double, locale: Locale = .current) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// A rate in percentage points per hour, e.g. "12.5% per hour".
    public static func percentPerHour(_ value: Double, locale: Locale = .current) -> String {
        let percent = (value / 100).formatted(.percent.precision(.fractionLength(0...1)).locale(locale))
        return String(localized: "\(percent) per hour")
    }

    /// Battery temperature in the unit the user's locale prefers (°C or °F).
    public static func temperature(celsius: Double, locale: Locale = .current) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius).formatted(
            .measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0...1)))
                .locale(locale)
        )
    }

    /// Voltage, e.g. "12.48 V".
    public static func volts(_ value: Double, locale: Locale = .current) -> String {
        Measurement(value: value, unit: UnitElectricPotentialDifference.volts).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...2)))
                .locale(locale)
        )
    }

    /// Power, e.g. "45.2 W".
    public static func watts(_ value: Double, locale: Locale = .current) -> String {
        Measurement(value: value, unit: UnitPower.watts).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))
                .locale(locale)
        )
    }

    /// Battery charge capacity, e.g. "7,480 mAh".
    public static func milliampereHours(_ value: Int, locale: Locale = .current) -> String {
        Measurement(value: Double(value), unit: UnitElectricCharge.milliampereHours).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
    }

    /// A plain integer with locale digits and grouping, e.g. "1,204".
    public static func integer(_ value: Int, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale))
    }
}
