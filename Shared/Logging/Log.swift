import OSLog

/// Log categories, one per functional area. Shown as the "Category" column in Console.app.
public enum LogCategory: String, Sendable, CaseIterable {
    case app
    case navigation
    case system
    case battery
    case energy
    case fileSystem
    case duplicates
    case cleanup
    case persistence
}

/// Central access to `os.Logger`.
///
/// Privacy rule: file paths, file names and process names are personal data. Interpolate
/// them with `privacy: .private` (the default for dynamic strings) so they are redacted
/// in logs collected from other machines. Never log file contents.
public enum Log {
    public static let subsystem = "com.mrismail.MacPulse"

    public static func logger(_ category: LogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}
