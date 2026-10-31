import Foundation
import MacPulseDomain
import MacPulseShared
import UserNotifications

/// Alert settings saved in the app's user defaults.
public final class UserDefaultsDrainAlertSettingsStore: DrainAlertSettingsStore, @unchecked Sendable {
    // UserDefaults is documented as thread-safe.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "drainAlertSettings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> DrainAlertSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(DrainAlertSettings.self, from: data)
        else { return DrainAlertSettings() }
        return settings
    }

    public func save(_ settings: DrainAlertSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Posts drain alerts as macOS notifications. Permission is requested only when the
/// user turns notifications on.
public struct UserNotificationDrainNotifier: DrainAlertNotifier {
    public init() {}

    public func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.logger(.energy).log(
                AppError.wrapping(error, userMessage: "Couldn't ask for notification permission."),
                context: "Notifications"
            )
            return false
        }
    }

    public func post(_ alert: DrainAlert) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(alert.displayName) is using a lot of CPU")
        content.body = alert.explanation
        let request = UNNotificationRequest(identifier: "drain-\(alert.appKey)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Log.logger(.energy).log(
                AppError.wrapping(error, userMessage: "Couldn't show a notification."),
                context: "Notifications"
            )
        }
    }
}
