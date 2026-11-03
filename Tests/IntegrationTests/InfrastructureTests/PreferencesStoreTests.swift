import Foundation
import MacPulseDomain
@testable import MacPulseInfrastructure
import Testing

@Suite("UserDefaultsPreferencesStore")
struct PreferencesStoreTests {
    @Test func savesAndLoads() throws {
        let suite = "macpulse-prefs-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        #expect(store.load() == AppPreferences())
        var changed = AppPreferences()
        changed.batteryInterval = .thirtySeconds
        changed.usageRetentionDays = 30
        store.save(changed)
        #expect(UserDefaultsPreferencesStore(defaults: defaults).load() == changed)
    }

    @Test func corruptDataFallsBackToDefaults() throws {
        let suite = "macpulse-prefs-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: UserDefaultsPreferencesStore.key)
        #expect(UserDefaultsPreferencesStore(defaults: defaults).load() == AppPreferences())
    }
}
