import Foundation
import MacPulseDomain
import MacPulseShared
import ServiceManagement

/// Preferences as JSON in user defaults.
public final class UserDefaultsPreferencesStore: PreferencesStore, @unchecked Sendable {
    // UserDefaults is documented as thread-safe.
    private let defaults: UserDefaults
    static let key = "appPreferences"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppPreferences {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(AppPreferences.self, from: data) else { return AppPreferences() }
        return stored.validated()
    }

    public func save(_ preferences: AppPreferences) {
        guard let data = try? JSONEncoder().encode(preferences.validated()) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// Opens MacPulse at login with `SMAppService.mainApp` (ADR-016). Off unless the user
/// turns it on; macOS lists it in System Settings → General → Login Items.
public struct ServiceManagementLoginItem: LoginItemControlling {
    public init() {}

    public func isEnabled() async -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) async throws -> Bool {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try await service.unregister()
        }
        return service.status == .enabled
    }
}
