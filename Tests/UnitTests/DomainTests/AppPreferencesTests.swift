import Foundation
import Testing
@testable import MacPulseDomain

@Suite("AppPreferences")
struct AppPreferencesTests {
    @Test func defaultsAreTheShippedBehaviour() {
        let preferences = AppPreferences()
        #expect(preferences.batteryInterval == .oneMinute)
        #expect(preferences.activityInterval == .oneMinute)
        #expect(preferences.batteryRetentionDays == 30)
        #expect(preferences.usageRetentionDays == 7)
        #expect(preferences.showsMenuBarExtra)
    }

    @Test func missingKeysKeepTheirDefaultsAndBadValuesAreReplaced() throws {
        let partial = Data(#"{"batteryInterval":300,"batteryRetentionDays":12345}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: partial).validated()
        #expect(decoded.batteryInterval == .fiveMinutes)
        #expect(decoded.batteryRetentionDays == 30, "Not one of the choices, so the default")
        #expect(decoded.usageRetentionDays == 7)
        #expect(decoded.showsMenuBarExtra)
    }

    @Test func roundTrips() throws {
        var preferences = AppPreferences()
        preferences.activityInterval = .fiveMinutes
        preferences.showsMenuBarExtra = false
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(AppPreferences.self, from: data) == preferences)
    }
}
