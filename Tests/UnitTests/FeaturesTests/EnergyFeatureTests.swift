import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseFeatures

private let referenceDate = Date(timeIntervalSince1970: 1_793_448_000)

/// Energy monitor double whose notification permission can be denied.
actor StubEnergyMonitor: EnergyMonitoring {
    private(set) var detailedCalls: [Bool] = []
    private(set) var updateCalls = 0
    private(set) var historyReads = 0
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
    func usageHistory(since date: Date) async throws -> [AppUsageRecord] {
        historyReads += 1
        return []
    }
    func alertSettings() async -> DrainAlertSettings { settings }
    func updateAlertSettings(_ newSettings: DrainAlertSettings) async -> Bool {
        updateCalls += 1
        var accepted = newSettings
        if newSettings.sendsNotifications && !allowNotifications { accepted.sendsNotifications = false }
        settings = accepted
        return !newSettings.sendsNotifications || allowNotifications
    }
    func clearHistory() async throws {}
    func flush() async {}
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

    @Test func sliderEditsAreSavedOnce() async {
        let stub = StubEnergyMonitor(status: nil)
        let model = EnergyViewModel(monitor: stub, saveDelay: .milliseconds(50), now: { referenceDate })
        for value in stride(from: 60.0, through: 120.0, by: 10) {
            model.editSettings { $0.cpuThresholdPercent = value }
        }
        #expect(model.settings.cpuThresholdPercent == 120)  // the view updates immediately
        try? await Task.sleep(for: .milliseconds(300))
        #expect(await stub.updateCalls == 1)
        #expect(await stub.alertSettings().cpuThresholdPercent == 120)
    }

    @Test func impactColumnSortCanBeReversed() async {
        let model = EnergyViewModel(monitor: PreviewEnergyMonitor(referenceDate: referenceDate), now: { referenceDate })
        await model.observe(detailed: false)
        let ranked = model.apps.map(\.id)
        model.sortOrder = [KeyPathComparator(\AppUsage.shareOfActivity, order: .forward)]
        #expect(model.apps.map(\.id) == ranked.reversed())
        model.sortOrder = [KeyPathComparator(\AppUsage.cpuPercent, order: .forward)]
        #expect(model.apps.map(\.cpuPercent) == model.apps.map(\.cpuPercent).sorted())
    }

    @Test func selectedAppWithoutActivityIsReported() async {
        let model = EnergyViewModel(monitor: PreviewEnergyMonitor(referenceDate: referenceDate), now: { referenceDate })
        await model.observe(detailed: false)
        model.select("/Applications/Gone.app")
        #expect(model.selectedApp == nil)
        #expect(model.selectedAppIsIdle)
    }

    @Test func historyIsLoadedWhenTheVersionChanges() async {
        let preview = PreviewEnergyMonitor(referenceDate: referenceDate)
        let stub = StubEnergyMonitor(status: await preview.status())
        let model = EnergyViewModel(monitor: stub, now: { referenceDate })
        await model.observe(detailed: true)
        #expect(await stub.historyReads == 1)
    }

    @Test func wordingNeverClaimsBatteryUseWithoutEnergyData() {
        #expect(EnergyPresentation.impactTitle(energyDataAvailable: false) == "Activity (CPU-based)")
        #expect(EnergyPresentation.topAppsTitle(energyDataAvailable: false) == "Most active apps")
        #expect(EnergyPresentation.impactTitle(energyDataAvailable: true) == "Battery impact")
    }

    @Test func smallCPUValuesKeepADecimal() {
        #expect(EnergyPresentation.cpuText(0.4).contains("0.4"))
        #expect(EnergyPresentation.cpuText(62).contains("62"))
    }

    @Test func topAppsSkipIdleApps() {
        let idle = AppUsage(
            id: "idle", displayName: "Idle", appBundlePath: nil, processCount: 1, cpuPercent: 0.1,
            memoryBytes: nil, threadCount: nil, energyMilliwatts: nil, diskBytesPerSecond: nil,
            wakeupsPerSecond: nil, impact: .estimated(.low, basis: "t"), shareOfActivity: 0
        )
        let apps = PreviewEnergyMonitor.sampleApps() + [idle]
        #expect(!EnergyPresentation.topApps(apps, limit: 10).contains { $0.id == "idle" })
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
        #expect(model.isWaitingForFirstUpdate)
        await model.observeEnergy()
        #expect(!model.isWaitingForFirstUpdate)
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
