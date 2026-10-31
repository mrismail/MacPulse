import Foundation

/// Formats durations such as estimated battery runtime, localized by Foundation
/// (e.g. "3 hr, 25 min" in English).
public enum DurationFormatting {
    /// Negative input is treated as zero.
    public static func string(fromMinutes minutes: Int, locale: Locale = .current) -> String {
        let duration = Duration.seconds(max(0, minutes) * 60)
        return duration.formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, zeroValueUnits: .hide)
                .locale(locale)
        )
    }
}
