import Foundation

/// User preferences shared by every screen. Monitoring intervals and retention apply at
/// the next launch; the other settings apply at once.
public struct AppPreferences: Codable, Sendable, Equatable {
    public enum BatteryInterval: Int, Codable, Sendable, CaseIterable, Identifiable {
        case thirtySeconds = 30
        case oneMinute = 60
        case fiveMinutes = 300
        public var id: Int { rawValue }
        public var duration: Duration { .seconds(rawValue) }
        public var title: String {
            switch self {
            case .thirtySeconds: String(localized: "Every 30 seconds")
            case .oneMinute: String(localized: "Every minute")
            case .fiveMinutes: String(localized: "Every 5 minutes")
            }
        }
        /// The interval inside a sentence ("records the battery level every minute"), as
        /// its own phrase so translations don't depend on lowercasing the title.
        public var inSentence: String {
            switch self {
            case .thirtySeconds: String(localized: "every 30 seconds")
            case .oneMinute: String(localized: "every minute")
            case .fiveMinutes: String(localized: "every 5 minutes")
            }
        }
    }

    public enum ActivityInterval: Int, Codable, Sendable, CaseIterable, Identifiable {
        case oneMinute = 60
        case fiveMinutes = 300
        public var id: Int { rawValue }
        public var duration: Duration { .seconds(rawValue) }
        public var title: String {
            switch self {
            case .oneMinute: String(localized: "Every minute")
            case .fiveMinutes: String(localized: "Every 5 minutes (uses less energy)")
            }
        }
    }

    public var batteryInterval: BatteryInterval = .oneMinute
    public var activityInterval: ActivityInterval = .oneMinute
    /// Days of battery history kept.
    public var batteryRetentionDays = 30
    /// Days of hourly app usage kept.
    public var usageRetentionDays = 7
    public var showsMenuBarExtra = true
    /// Old-downloads age the Cleaner starts with.
    public var cleanupDownloadsAgeDays = 30

    public static let batteryRetentionChoices = [7, 30, 90]
    public static let usageRetentionChoices = [7, 14, 30]

    public init() {}

    /// Values outside the offered choices (e.g. edited by hand) fall back to defaults.
    public func validated() -> AppPreferences {
        var copy = self
        if !Self.batteryRetentionChoices.contains(copy.batteryRetentionDays) { copy.batteryRetentionDays = 30 }
        if !Self.usageRetentionChoices.contains(copy.usageRetentionDays) { copy.usageRetentionDays = 7 }
        if ![30, 90, 365].contains(copy.cleanupDownloadsAgeDays) { copy.cleanupDownloadsAgeDays = 30 }
        return copy
    }

    // Decoding tolerates missing keys so new preferences don't reset existing ones.
    enum CodingKeys: String, CodingKey {
        case batteryInterval, activityInterval, batteryRetentionDays, usageRetentionDays, showsMenuBarExtra, cleanupDownloadsAgeDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppPreferences()
        batteryInterval = (try? container.decode(BatteryInterval.self, forKey: .batteryInterval)) ?? defaults.batteryInterval
        activityInterval = (try? container.decode(ActivityInterval.self, forKey: .activityInterval)) ?? defaults.activityInterval
        batteryRetentionDays = (try? container.decode(Int.self, forKey: .batteryRetentionDays)) ?? defaults.batteryRetentionDays
        usageRetentionDays = (try? container.decode(Int.self, forKey: .usageRetentionDays)) ?? defaults.usageRetentionDays
        showsMenuBarExtra = (try? container.decode(Bool.self, forKey: .showsMenuBarExtra)) ?? defaults.showsMenuBarExtra
        cleanupDownloadsAgeDays = (try? container.decode(Int.self, forKey: .cleanupDownloadsAgeDays)) ?? defaults.cleanupDownloadsAgeDays
    }
}

/// Where preferences are kept.
public protocol PreferencesStore: Sendable {
    func load() -> AppPreferences
    func save(_ preferences: AppPreferences)
}

/// Opening MacPulse at login (`SMAppService` in the app).
public protocol LoginItemControlling: Sendable {
    /// `true` when macOS will open MacPulse at login.
    func isEnabled() async -> Bool
    /// Asks macOS to open (or stop opening) MacPulse at login. Returns the new state;
    /// macOS may need the user to approve it in System Settings.
    func setEnabled(_ enabled: Bool) async throws -> Bool
}

public final class InMemoryPreferencesStore: PreferencesStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: AppPreferences
    public init(_ value: AppPreferences = AppPreferences()) { self.value = value }
    public func load() -> AppPreferences { lock.withLock { value } }
    public func save(_ preferences: AppPreferences) { lock.withLock { value = preferences } }
}

public actor InMemoryLoginItem: LoginItemControlling {
    private var enabled = false
    public init() {}
    public func isEnabled() -> Bool { enabled }
    public func setEnabled(_ enabled: Bool) -> Bool {
        self.enabled = enabled
        return enabled
    }
}
