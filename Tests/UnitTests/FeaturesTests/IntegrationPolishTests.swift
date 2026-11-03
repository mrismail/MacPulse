import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseFeatures

private actor FailingLoginItem: LoginItemControlling {
    struct Refused: Error {}
    func isEnabled() -> Bool { false }
    func setEnabled(_ enabled: Bool) throws -> Bool { throw Refused() }
}

@Suite("Settings — preferences, login item, histories")
@MainActor
struct SettingsPreferencesTests {
    func model(
        store: InMemoryPreferencesStore = InMemoryPreferencesStore(),
        login: any LoginItemControlling = InMemoryLoginItem(),
        scans: InMemoryScanHistory? = nil,
        cleanups: InMemoryCleanupHistory? = nil
    ) -> SettingsViewModel {
        SettingsViewModel(
            systemInfoRepository: PreviewSystemInfoRepository(), batteryMonitor: PreviewBatteryMonitor(),
            preferences: store, loginItem: login, scanHistory: scans, cleanupHistory: cleanups,
            confirmationDuration: .milliseconds(10)
        )
    }

    @Test func preferencesAreSavedAndIntervalChangesNeedARestart() {
        let store = InMemoryPreferencesStore()
        let settings = model(store: store)
        #expect(!settings.needsRestart)
        settings.update { $0.showsMenuBarExtra = false }
        #expect(store.load().showsMenuBarExtra == false)
        #expect(!settings.needsRestart, "The menu bar applies at once")
        settings.update { $0.batteryInterval = .fiveMinutes }
        #expect(settings.needsRestart)
        #expect(settings.batteryHistoryRetentionDays == 30, "Retention shown is the one in use")
        settings.update { $0.batteryRetentionDays = 999 }
        #expect(store.load().batteryRetentionDays == 30, "Values outside the choices are not saved")
    }

    @Test func openAtLoginIsOffUntilTurnedOnAndFailuresAreShown() async {
        let settings = model()
        await settings.loadLoginItem()
        #expect(!settings.opensAtLogin)
        await settings.setOpensAtLogin(true)
        #expect(settings.opensAtLogin)

        let failing = model(login: FailingLoginItem())
        await failing.setOpensAtLogin(true)
        #expect(!failing.opensAtLogin)
        #expect(failing.loginItemError != nil)
    }

    @Test func scanAndCleanupHistoryCanBeCleared() async {
        let scans = InMemoryScanHistory([ScanSummary(result: PreviewScanner.result(root: "/Users/p"))])
        let cleanups = InMemoryCleanupHistory([CleanupReport(category: .logs, finishedAt: Date(), items: [], isComplete: true)])
        let settings = model(scans: scans, cleanups: cleanups)
        #expect(settings.canClearScanHistory && settings.canClearCleanupHistory)
        await settings.clearScanHistory()
        await settings.clearCleanupHistory()
        #expect(await scans.summaries().isEmpty)
        #expect(await cleanups.reports().isEmpty)
        #expect(settings.clearScanHistoryState == .cleared)
    }
}

@Suite("Shared safety policy and Put Back")
@MainActor
struct SharedSafetyTests {
    @Test func cleanerUsesTheSameExclusionsAsScans() async {
        let model = CleanerViewModel(source: PreviewCleanupSource(), trash: PreviewTrashService(), homePath: "/Users/preview", appDataPath: nil)
        model.connect(
            largeFiles: { [] }, duplicates: { [] },
            exclusions: { ["/Users/preview/Library/Caches/com.example.chat"] },
            initialAgeDays: 90,
            didClean: { _ in }
        )
        #expect(model.minimumAgeDays == 90)
        #expect(model.policy.verdict(for: "/Users/preview/Library/Caches/com.example.chat") != .allowed)
        #expect(model.policy.verdict(for: "/Users/preview/Library/Caches/com.example.browser") == .allowed)
    }

    @Test func putBackIsRecordedInHistory() async throws {
        let history = InMemoryCleanupHistory()
        let model = CleanerViewModel(source: PreviewCleanupSource(), trash: PreviewTrashService(), history: history, homePath: "/Users/preview", appDataPath: nil)
        await model.open(.appCaches)
        model.selectAll()
        model.requestCleanup()
        model.confirmCleanup()
        await model.waitForTask()
        let report = try #require(model.history.first)
        let item = try #require(report.moved.first)
        await model.putBack(item, in: report)
        #expect(model.putBackError == nil)
        let updated = try #require(await history.reports().first)
        #expect(updated.items.first { $0.path == item.path }?.outcome == .putBack)
        #expect(updated.bytesMovedToTrash < report.bytesMovedToTrash)
    }
}

@Suite("Menu bar")
struct MenuBarTests {
    @Test func labelNeverInventsACharge() {
        #expect(MenuBarPresentation.chargeText(.unavailable(.notSupportedOnThisMac)) == "—")
        #expect(MenuBarPresentation.symbol(.unavailable(.notSupportedOnThisMac), charging: false) == "gauge.with.dots.needle.50percent")
        #expect(MenuBarPresentation.symbol(.measured(10), charging: false) == "battery.0percent")
        #expect(MenuBarPresentation.symbol(.measured(55), charging: false) == "battery.50percent")
        #expect(MenuBarPresentation.symbol(.measured(55), charging: true) == "battery.100percent.bolt")
    }
}
