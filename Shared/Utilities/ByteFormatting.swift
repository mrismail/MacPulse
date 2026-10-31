import Foundation

/// Formats byte counts with decimal (SI) units, matching how Finder and
/// System Settings → Storage report sizes (1 KB = 1,000 bytes).
public enum ByteFormatting {
    private static let units = ["KB", "MB", "GB", "TB", "PB"]

    /// - Parameters:
    ///   - bytes: The byte count.
    ///   - locale: Controls the decimal separator. Defaults to the user's locale.
    /// - Returns: For example "512 bytes", "1.5 MB", "250 GB".
    public static func string(fromBytes bytes: UInt64, locale: Locale = .current) -> String {
        if bytes < 1_000 {
            return bytes == 1 ? "1 byte" : "\(bytes) bytes"
        }
        var value = Double(bytes)
        var unitIndex = -1
        while value >= 1_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }
        // Rounding can push 999.95 up to "1000"; promote to the next unit instead.
        if value.rounded(toPlaces: 1) >= 1_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }
        // One decimal below 100 ("1.5 GB", "12.3 GB"); whole numbers above ("250 GB").
        let fractionDigits = value < 100 ? 0...1 : 0...0
        let number = value.formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .grouping(.never)
                .locale(locale)
        )
        return "\(number) \(units[unitIndex])"
    }
}

extension Double {
    fileprivate func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
