import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseFeatures

private let referenceDate = Date(timeIntervalSince1970: 1_793_448_000)

/// Energy monitor double whose notification permission can be denied.
actor StubEnergyMonitor: EnergyMonitoring {
    private(set) var detailedCalls: [Bool] = []
    private var settings = DrainAlertSettings()
    let allowNotifications: Bool
    let statusToSend: EnergyStatus?

    init(status: EnergyStatus?, allowNotifications: Bool = true) {
        statusToSend = status
        self.allowNotifications = allowNotifications
    }

    func start() async {}
    func setDetailedSampling(_ enabled: Bool) async { detailedCalls.append(enabled) }
    func updates() async -> AsyncStream<EnergyStatus> {
        let status = statusToSend
        return AsyncStream { continuation in
            if let status { continuation.yield(status) }
            continuation.finish()
        }
    }
    func usageHistory(since date: Date) async throws -> [AppUsageRecord] { [] }
    func alertSettings() async -> DrainAlertSettings { settings }
    func updateAlertSettings(_ newSettings: DrainAlertSettings) async -> Bool {
        var accepted = newSettings
        if newSettings.sendsNotifications && !allowNotifications { accepted.sendsNotifications = false }
        settings = accepted
        return !newSettings.sendsNotifications || allowNotifications
    }
    func clearHistory() async throws {}
}

@Suite("EnergyViewModel")
@MainActor
struct EnergyViewModelTests {
    @Test func observeLoadsStatusAndTogglesDetailedSampling() async {
        let preview = PreviewEnergyMonitor(referenceDate: referenceDate)
        let stub = StubEnergyMonitor(status: await preview.status())
        let model = EnergyViewModel(monitor: stub, now: { referenceDate })
        await model.observe(detailed: true)

        #expect(model.apps.first?.displayName == "Web Browser")
        #expect(model.topApps.count == 4)
        #expect(model.systemCPU == .measured(23))
        #expect(model.ownCPU.isMeasured)
        #expect(await stub.detailedCalls == [true, false])  // fast while visible, back to slow after
    }

    @Test func summaryObservationDoesNotChangeSamplingRate() async {
        let stub = StubEnergyMonitor(status: nil)
        let model = EnergyViewModel(monitor: stub, now: { referenceDate })
        await model.observe(detailed: false)
        #expect(await stub.detailedCalls.isEmpty)
    }

    @Test func timeframeSwitchesBetweenNowAndRecent() async {
        let preview = PreviewEnergyMonitor(referenceDate: referenceDate)
        let model = EnergyViewModel(monitor: preview, now: { referenceDate })
        await model.observe(detailed: false)
        model.timeframe = .now
        #expect(model.apps == model.status?.current)
        model.timeframe = .recent
        #expect(model.apps == model.status?.recent)
    }

    @Test func selectingAnAppBuildsItsTrend() async throws {
        let preview = PreviewEnergyMonitor(referenceDate: referenceDate)
        let model = EnergyViewModel(monitor: preview, now: { referenceDate })
        await model.observe(detailed: false)
        await model.loadHistory()
        let app = try #require(model.apps.first)
        model.select(app.id)
        #expect(model.selectedApp?.id == app.id)
        #expect(model.trend.count >= 24)
        #expect(model.trend.contains { $0.onBattery })
        model.select(nil)
        #expect(model.trend.isEmpty)
    }

    @Test func deniedNotificationsAreReported() async {
        let stub = StubEnergyMonitor(status: nil, allowNotifications: false)
        let model = EnergyViewModel(monitor: stub, now: { referenceDate })
        await model.updateSettings(DrainAlertSettings(sendsNotifications: true))
        #expect(model.notificationsDenied)
        #expect(model.settings.sendsNotifications == false)
    }

    @Test func impactIsAlwaysAnEstimate() async {
        let model = EnergyViewModel(monitor: PreviewEnergyMonitor(referenceDate: referenceDate), now: { referenceDate })
        await model.observe(detailed: false)
        #expect(!model.apps.isEmpty)
        #expect(model.apps.allSatisfy { !$0.impact.isMeasured && $0.impact.isAvailable })
    }
}

@Suite("Overview energy integration")
@MainActor
struct OverviewEnergyTests {
    @Test func drainAlertsBecomeRecommendations() async throws {
        let model = OverviewViewModel(
            systemInfoRepository: StubSystemInfoRepository(result: .success(sampleInfo)),
            batteryMonitor: PreviewBatteryMonitor(referenceDate: referenceDate),
            energyMonitor: PreviewEnergyMonitor(referenceDate: referenceDate)
        )
        await model.observeEnergy()
        let first = try #require(model.recommendations.first)
        #expect(first.id.hasPrefix("drain-"))
        #expect(first.severity == .warning)
        #expect(model.topApps.count == 3)
    }
}

@Suite("Settings usage history")
@MainActor
struct SettingsUsageHistoryTests {
    @Test func clearsUsageHistoryThroughTheMonitor() async {
        let model = SettingsViewModel(
            systemInfoRepository: StubSystemInfoRepository(result: .success(sampleInfo)),
            batteryMonitor: PreviewBatteryMonitor(referenceDate: referenceDate),
            energyMonitor: StubEnergyMonitor(status: nil)
        )
        #expect(model.canClearUsageHistory)
        await model.clearUsageHistory()
        #expect(model.clearUsageHistoryState == .cleared)
    }

    @Test func hiddenWithoutAnEnergyMonitor() {
        let model = SettingsViewModel(
            systemInfoRepository: StubSystemInfoRepository(result: .success(sampleInfo)),
            batteryMonitor: PreviewBatteryMonitor(referenceDate: referenceDate)
        )
        #expect(!model.canClearUsageHistory)
    }
}
