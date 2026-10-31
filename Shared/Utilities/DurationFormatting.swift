import Foundation

/// Formats durations such as estimated battery runtime.
public enum DurationFormatting {
    /// - Returns: "0 min", "45 min", "3 h", "3 h 25 min". Negative input is treated as zero.
    public static func string(fromMinutes minutes: Int) -> String {
        let total = max(0, minutes)
        let hours = total / 60
        let remainder = total % 60
        switch (hours, remainder) {
        case (0, let mins):
            return "\(mins) min"
        case (let hrs, 0):
            return "\(hrs) h"
        case (let hrs, let mins):
            return "\(hrs) h \(mins) min"
        }
    }
}
