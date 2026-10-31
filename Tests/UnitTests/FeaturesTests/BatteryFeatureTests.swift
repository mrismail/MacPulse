import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseFeatures

/// Battery monitor double with configurable history and failure.
actor StubBatteryMonitor: BatteryMonitoring {
    var statusToSend: BatteryStatus?
    var storedHistory: [BatterySnapshot]
    var historyError: (any Error)?
    private(set) var clearCount = 0
    private(set) var refreshCount = 0

    init(status: BatteryStatus?, history: [BatterySnapshot] = [], historyError: (any Error)? = nil) {
        statusToSend = status
        storedHistory = history
        self.historyError = historyError
    }

    func start() async {}
    func refresh() async { refreshCount += 1 }

    func updates() async -> AsyncStream<BatteryStatus> {
        let status = statusToSend
        return AsyncStream { continuation in
            if let status { continuation.yield(status) }
            continuation.finish()
        }
    }

    func history(since date: Date) async throws -> [BatterySnapshot] {
        if let historyError { throw historyError }
        return storedHistory.filter { $0.timestamp >= date }
    }

    func clearHistory() async throws {
        if let historyError { throw historyError }
        storedHistory.removeAll()
        clearCount += 1
    }
}

private let referenceDate = Date(timeIntervalSince1970: 1_793_448_000)

private func status(_ raw: RawBatteryData) -> BatteryStatus {
    BatteryStatus(
        reading: BatteryReadingBuilder.build(from: raw, at: referenceDate),
        runtimeFromRecentDischarge: .unavailable(.notYetSampled),
        dischargeRatePercentPerHour: .unavailable(.notYetSampled)
    )
}

@Suite("BatteryViewModel")
@MainActor
struct BatteryViewModelTests {
    @Test func observeLoadsStatusHistoryAndSessions() async {
        let preview = PreviewBatteryMonitor(referenceDate: referenceDate)
        let model = BatteryViewModel(monitor: preview, now: { referenceDate })

        await model.observe()

        #expect(model.status == preview.status())
        #expect(model.hasBattery)
        #expect(model.stateDescription == "On battery")
        #expect(!model.chartPoints.isEmpty)
        #expect(model.recentSessions.count == 1)
        #expect(model.conditionDescription == .measured("Normal"))
    }

    @Test func rangeLimitsHistory() async {
        let preview = PreviewBatteryMonitor(referenceDate: referenceDate)
        let model = BatteryViewModel(monitor: preview, now: { referenceDate })

        model.range = .sixHours
        await model.reloadHistory()
        let sixHourPoints = model.chartPoints.count
        #expect(model.recentSessions.isEmpty)  // the session was 14–20 h ago

        model.range = .day
        await model.reloadHistory()
        #expect(model.chartPoints.count > sixHourPoints)
        #expect(model.chartPoints.allSatisfy { $0.timestamp >= referenceDate.addingTimeInterval(-24 * 3_600) })
    }

    @Test func desktopMacReportsNoBattery() async {
        let stub = StubBatteryMonitor(status: status(RawBatteryData(hasInternalBattery: false)))
        let model = BatteryViewModel(monitor: stub, now: { referenceDate })
        await model.observe()
        #expect(!model.hasBattery)
        #expect(model.stateDescription == "No battery")
    }

    @Test func stateDescriptions() async {
        var raw = PreviewBatteryMonitor.sampleRaw
        raw.powerSourceState = "AC Power"
        raw.isCharging = true
        let model = BatteryViewModel(monitor: StubBatteryMonitor(status: status(raw)), now: { referenceDate })
        #expect(model.stateDescription == "Reading battery…")
        await model.observe()
        #expect(model.stateDescription == "Charging")
    }

    @Test func historyFailureIsReported() async {
        let stub = StubBatteryMonitor(
            status: status(PreviewBatteryMonitor.sampleRaw),
            historyError: CocoaError(.fileReadNoPermission)
        )
        let model = BatteryViewModel(monitor: stub, now: { referenceDate })
        await model.observe()
        #expect(model.historyError?.kind == .permissionDenied)
        #expect(model.chartPoints.isEmpty)
    }

    @Test func refreshAsksTheMonitor() async {
        let stub = StubBatteryMonitor(status: nil)
        let model = BatteryViewModel(monitor: stub, now: { referenceDate })
        await model.refresh()
        #expect(await stub.refreshCount == 1)
    }
}

@Suite("BatteryHistoryChartModel")
struct BatteryHistoryChartModelTests {
    private func snapshot(_ minutes: Double, _ percentage: Double?) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: referenceDate.addingTimeInterval(minutes * 60),
            percentage: percentage,
            isCharging: false,
            isPluggedIn: false
        )
    }

    @Test func gapsStartNewSegments() {
        let points = BatteryHistoryChartModel.points(from: [
            snapshot(0, 80), snapshot(1, 79), snapshot(30, 70), snapshot(31, 69),
        ])
        #expect(points.map(\.segment) == [0, 0, 1, 1])
    }

    @Test func missingPercentagesAreSkipped() {
        let points = BatteryHistoryChartModel.points(from: [snapshot(0, 80), snapshot(1, nil), snapshot(2, 78)])
        #expect(points.map(\.percentage) == [80, 78])
    }

    @Test func longHistoriesAreDownsampled() {
        let week = (0..<10_080).map { snapshot(Double($0), 100 - Double($0) / 200) }
        let points = BatteryHistoryChartModel.points(from: week, maximumPoints: 400)
        #expect(points.count <= 400)
        #expect(points.count > 300)
        #expect(points.first?.timestamp ?? .distantFuture >= referenceDate)
    }

    @Test func bucketsAverageValues() {
        let points = BatteryHistoryChartModel.points(
            from: [snapshot(0, 80), snapshot(1, 78), snapshot(2, 76), snapshot(3, 74)],
            maximumPoints: 2
        )
        #expect(points.map(\.percentage) == [79, 75])
    }

    @Test func emptyInputGivesNoPoints() {
        #expect(BatteryHistoryChartModel.points(from: []).isEmpty)
    }
}

@Suite("Overview and Settings battery integration")
@MainActor
struct BatteryIntegrationViewModelTests {
    private let systemInfo = StubSystemInfoRepository(result: .success(sampleInfo))

    @Test func overviewShowsLiveCharge() async {
        let monitor = PreviewBatteryMonitor(referenceDate: referenceDate)
        let model = OverviewViewModel(systemInfoRepository: systemInfo, batteryMonitor: monitor)
        await model.observeBattery()
        #expect(model.batteryCharge == .measured(72))
        #expect(model.estimatedRuntimeMinutes.value == 295)
        #expect(model.batteryStateDescription == "On battery")
    }

    @Test func overviewOnPowerShowsSystemEstimateState() async {
        var raw = PreviewBatteryMonitor.sampleRaw
        raw.powerSourceState = "AC Power"
        raw.isCharging = false
        let model = OverviewViewModel(
            systemInfoRepository: systemInfo,
            batteryMonitor: StubBatteryMonitor(status: status(raw))
        )
        await model.observeBattery()
        #expect(model.batteryStateDescription == "Plugged in, not charging")
        #expect(model.estimatedRuntimeMinutes.provenance == .unavailable(.notApplicable("Connected to power.")))
    }

    @Test func settingsClearsHistory() async {
        let stub = StubBatteryMonitor(status: nil, history: [
            BatterySnapshot(timestamp: referenceDate, percentage: 50, isCharging: false, isPluggedIn: false),
        ])
        let model = SettingsViewModel(systemInfoRepository: systemInfo, batteryMonitor: stub)
        await model.clearBatteryHistory()
        #expect(model.clearBatteryHistoryState == .cleared)
        #expect(await stub.clearCount == 1)
        #expect(await stub.storedHistory.isEmpty)
    }

    @Test func settingsReportsClearFailure() async {
        let stub = StubBatteryMonitor(status: nil, historyError: POSIXError(.EACCES))
        let model = SettingsViewModel(systemInfoRepository: systemInfo, batteryMonitor: stub)
        await model.clearBatteryHistory()
        guard case .failed(let error) = model.clearBatteryHistoryState else {
            Issue.record("Expected failure state")
            return
        }
        #expect(error.kind == .permissionDenied)
    }
}
