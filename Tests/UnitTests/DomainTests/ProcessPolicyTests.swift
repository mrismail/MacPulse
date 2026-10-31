import Foundation
import Testing
@testable import MacPulseDomain

@Suite("ProcessActivityCalculator")
struct ProcessActivityCalculatorTests {
    typealias F = ProcessFixtures

    @Test func cpuPercentIsPerCore() throws {
        let before = F.snapshot(at: 0, [F.sample(pid: 10, name: "a", cpuSeconds: 100)])
        let after = F.snapshot(at: 10, [F.sample(pid: 10, name: "a", cpuSeconds: 115)])  // 15 s CPU in 10 s
        let activity = try #require(ProcessActivityCalculator.activity(from: before, to: after).first)
        #expect(abs(activity.cpuPercent - 150) < 0.0001)  // 1.5 cores
    }

    @Test func reusedPidIsNotMerged() {
        let before = F.snapshot(at: 0, [F.sample(pid: 10, started: 1, name: "old", cpuSeconds: 500)])
        let after = F.snapshot(at: 10, [F.sample(pid: 10, started: 2, name: "new", cpuSeconds: 1)])
        #expect(ProcessActivityCalculator.activity(from: before, to: after).isEmpty)
    }

    @Test func backwardsCountersAreSkipped() {
        let before = F.snapshot(at: 0, [F.sample(pid: 10, name: "a", cpuSeconds: 50)])
        let after = F.snapshot(at: 10, [F.sample(pid: 10, name: "a", cpuSeconds: 40)])
        #expect(ProcessActivityCalculator.activity(from: before, to: after).isEmpty)
    }

    @Test func energyAndRatesAreConverted() throws {
        let before = F.snapshot(at: 0, [F.sample(pid: 10, name: "a", cpuSeconds: 0, energyJoules: 1, wakeups: 100, disk: 0)])
        let after = F.snapshot(at: 10, [F.sample(pid: 10, name: "a", cpuSeconds: 1, energyJoules: 6, wakeups: 600, disk: 1_000)])
        let activity = try #require(ProcessActivityCalculator.activity(from: before, to: after).first)
        #expect(abs((activity.energyMilliwatts ?? 0) - 500) < 0.001)  // 5 J / 10 s = 0.5 W
        #expect(activity.wakeupsPerSecond == 50)
        #expect(activity.diskBytesPerSecond == 100)
    }

    @Test func zeroOrNegativeIntervalGivesNothing() {
        let snapshot = F.snapshot(at: 0, [F.sample(pid: 10, name: "a", cpuSeconds: 1)])
        #expect(ProcessActivityCalculator.activity(from: snapshot, to: snapshot).isEmpty)
    }

    @Test func systemBusyFraction() {
        let before = SystemCPUTicks(user: 100, system: 100, idle: 800, nice: 0)
        let after = SystemCPUTicks(user: 150, system: 150, idle: 900, nice: 0)
        #expect(ProcessActivityCalculator.systemBusyFraction(from: before, to: after) == 0.5)
        #expect(ProcessActivityCalculator.systemBusyFraction(from: nil, to: after) == nil)
        #expect(ProcessActivityCalculator.systemBusyFraction(from: before, to: before) == nil)
    }

    @Test func systemTickCountersWrapAt32Bits() {
        // user counter wraps from near 2^32 to a small value.
        let before = SystemCPUTicks(user: UInt64(UInt32.max) - 99, system: 0, idle: 1_000, nice: 0)
        let after = SystemCPUTicks(user: 100, system: 0, idle: 1_200, nice: 0)  // +200 busy, +200 idle
        #expect(ProcessActivityCalculator.systemBusyFraction(from: before, to: after) == 0.5)
    }
}

@Suite("AppUsageAggregator")
struct AppUsageAggregatorTests {
    typealias F = ProcessFixtures

    private func activities(_ samples: [(ProcessSample, ProcessSample)]) -> [ProcessActivity] {
        ProcessActivityCalculator.activity(
            from: F.snapshot(at: 0, samples.map(\.0)),
            to: F.snapshot(at: 10, samples.map(\.1))
        )
    }

    @Test func helpersAreGroupedUnderTheirApp() throws {
        let chrome = "/Applications/Chrome.app"
        let list = activities([
            (F.sample(pid: 1, name: "Google Chrome", bundle: chrome, cpuSeconds: 0), F.sample(pid: 1, name: "Google Chrome", bundle: chrome, cpuSeconds: 2)),
            (F.sample(pid: 2, name: "Chrome Helper", bundle: chrome, cpuSeconds: 0), F.sample(pid: 2, name: "Chrome Helper", bundle: chrome, cpuSeconds: 3)),
            (F.sample(pid: 3, name: "mds_stores", cpuSeconds: 0), F.sample(pid: 3, name: "mds_stores", cpuSeconds: 1)),
        ])
        let apps = AppUsageAggregator.aggregate(list, displayNames: [chrome: "Google Chrome"], basis: .cpu)
        #expect(apps.count == 2)
        let first = try #require(apps.first)
        #expect(first.displayName == "Google Chrome")
        #expect(first.processCount == 2)
        #expect(abs(first.cpuPercent - 50) < 0.0001)
        #expect(first.memoryBytes == 200_000_000)
        #expect(apps[1].id == "process:mds_stores")
    }

    @Test func outermostBundleWinsForNestedHelpers() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(AppUsageAggregator.outermostAppBundle(in: path) == "/Applications/Google Chrome.app")
        #expect(AppUsageAggregator.outermostAppBundle(in: "/usr/sbin/cfprefsd") == nil)
    }

    @Test func impactUsesCPUWhenNoEnergyAccounting() throws {
        let list = activities([
            (F.sample(pid: 1, name: "busy", cpuSeconds: 0), F.sample(pid: 1, name: "busy", cpuSeconds: 6)),   // 60%
            (F.sample(pid: 2, name: "mid", cpuSeconds: 0), F.sample(pid: 2, name: "mid", cpuSeconds: 2)),     // 20%
            (F.sample(pid: 3, name: "idle", cpuSeconds: 0), F.sample(pid: 3, name: "idle", cpuSeconds: 0.1)), // 1%
        ])
        let apps = AppUsageAggregator.aggregate(list, displayNames: [:], basis: .cpu)
        #expect(apps.map(\.displayName) == ["busy", "mid", "idle"])
        #expect(apps.map { $0.impact.value } == [.high, .moderate, .low])
        #expect(apps.allSatisfy { !$0.impact.isMeasured })
        guard case .estimated(let basis) = apps[0].impact.provenance else {
            Issue.record("Impact must be an estimate")
            return
        }
        #expect(basis == AppUsageAggregator.cpuBasis)
        #expect(apps[0].energyMilliwatts == nil)
    }

    @Test func impactUsesEnergyWhenAvailable() throws {
        let list = activities([
            // Low CPU but high energy (e.g. GPU work): energy decides.
            (F.sample(pid: 1, name: "gpu", cpuSeconds: 0, energyJoules: 0), F.sample(pid: 1, name: "gpu", cpuSeconds: 0.5, energyJoules: 30)),  // 3 W
            (F.sample(pid: 2, name: "cpu", cpuSeconds: 0, energyJoules: 0), F.sample(pid: 2, name: "cpu", cpuSeconds: 3, energyJoules: 2)),     // 200 mW
        ])
        let apps = AppUsageAggregator.aggregate(list, displayNames: [:], basis: .energy)
        #expect(apps.first?.displayName == "gpu")
        #expect(apps.first?.impact.value == .high)
        #expect(apps.last?.impact.value == .low)
        guard case .estimated(let basis) = try #require(apps.first).impact.provenance else {
            Issue.record("Impact must be an estimate")
            return
        }
        #expect(basis == AppUsageAggregator.energyBasis)
        #expect(abs(apps.map(\.shareOfActivity).reduce(0, +) - 1) < 0.0001)
    }

    @Test func idleIntervalOnEnergyMacStaysEnergyBased() throws {
        // Energy accounting exists but this interval used none: the label must not flip to CPU.
        let list = activities([
            (F.sample(pid: 1, name: "a", cpuSeconds: 0, energyJoules: 5), F.sample(pid: 1, name: "a", cpuSeconds: 0.01, energyJoules: 5)),
        ])
        let app = try #require(AppUsageAggregator.aggregate(list, displayNames: [:], basis: .energy).first)
        guard case .estimated(let basis) = app.impact.provenance else {
            Issue.record("Impact must be an estimate")
            return
        }
        #expect(basis == AppUsageAggregator.energyBasis)
        #expect(app.energyMilliwatts == 0)
        #expect(app.shareOfActivity == 0)
    }

    @Test func cpuBasisSaysItIsNotABatteryMeasurement() {
        #expect(AppUsageAggregator.cpuBasis.contains("not measured battery use"))
    }

    @Test func ownProcessIsExcluded() {
        let list = activities([
            (F.sample(pid: 999, name: "MacPulse", cpuSeconds: 0), F.sample(pid: 999, name: "MacPulse", cpuSeconds: 1)),
            (F.sample(pid: 1, name: "other", cpuSeconds: 0), F.sample(pid: 1, name: "other", cpuSeconds: 1)),
        ])
        let apps = AppUsageAggregator.aggregate(list, displayNames: [:], excludingPID: 999, basis: .cpu)
        #expect(apps.map(\.displayName) == ["other"])
    }

    @Test func bundleNameFallsBackToFolderName() {
        let bundle = "/Applications/Some Tool.app"
        let list = activities([(F.sample(pid: 1, name: "x", bundle: bundle, cpuSeconds: 0), F.sample(pid: 1, name: "x", bundle: bundle, cpuSeconds: 1))])
        #expect(AppUsageAggregator.aggregate(list, displayNames: [:], basis: .cpu).first?.displayName == "Some Tool")
    }

    @Test func averageWeightsByDurationAndCountsAbsenceAsIdle() throws {
        let busy = F.usage("a", cpu: 100)
        let first = UsageInterval(start: F.start, end: F.start.addingTimeInterval(60), onBattery: true, apps: [busy])
        let second = UsageInterval(start: F.start.addingTimeInterval(60), end: F.start.addingTimeInterval(180), onBattery: true, apps: [])
        let averaged = AppUsageAggregator.average([first, second], basis: .cpu)
        let app = try #require(averaged.first)
        #expect(abs(app.cpuPercent - 100.0 / 3) < 0.0001)  // 60 s of 180 s
    }
}

@Suite("DrainAlertEvaluator")
struct DrainAlertEvaluatorTests {
    typealias F = ProcessFixtures
    private let settings = DrainAlertSettings(isEnabled: true, cpuThresholdPercent: 50, sustainedMinutes: 10, onlyOnBattery: true)

    @Test func sustainedHeavyUseAlerts() throws {
        let intervals = F.intervals(count: 12, apps: [F.usage("hog", cpu: 80), F.usage("calm", cpu: 5)])
        let alerts = DrainAlertEvaluator.alerts(for: intervals, settings: settings, now: F.start)
        let alert = try #require(alerts.first)
        #expect(alerts.count == 1)
        #expect(alert.appKey == "hog")
        #expect(abs(alert.averageCPUPercent - 80) < 0.0001)
        #expect(alert.explanation.contains("80% CPU"))
        #expect(!alert.explanation.contains("battery %"))
    }

    @Test func shortBurstsDoNotAlert() {
        let intervals = F.intervals(count: 5, apps: [F.usage("hog", cpu: 90)])
        #expect(DrainAlertEvaluator.alerts(for: intervals, settings: settings, now: F.start).isEmpty)
    }

    @Test func externalPowerDoesNotAlertWhenBatteryOnly() {
        let intervals = F.intervals(count: 12, onBattery: false, apps: [F.usage("hog", cpu: 90)])
        #expect(DrainAlertEvaluator.alerts(for: intervals, settings: settings, now: F.start).isEmpty)
        var anyPower = settings
        anyPower.onlyOnBattery = false
        #expect(DrainAlertEvaluator.alerts(for: intervals, settings: anyPower, now: F.start).count == 1)
    }

    @Test func gapBreaksTheRun() {
        let old = F.intervals(count: 8, end: F.start.addingTimeInterval(-3_600), apps: [F.usage("hog", cpu: 90)])
        let recent = F.intervals(count: 4, apps: [F.usage("hog", cpu: 90)])
        #expect(DrainAlertEvaluator.alerts(for: old + recent, settings: settings, now: F.start).isEmpty)
    }

    @Test func appMustBeBusyThroughout() {
        var intervals = F.intervals(count: 12, apps: [F.usage("hog", cpu: 95)])
        // One quiet minute in the middle: average stays high but it isn't sustained.
        let quiet = intervals[6]
        intervals[6] = UsageInterval(start: quiet.start, end: quiet.end, onBattery: true, apps: [F.usage("hog", cpu: 2)])
        #expect(DrainAlertEvaluator.alerts(for: intervals, settings: settings, now: F.start).isEmpty)
    }

    @Test func disabledOrStaleGivesNothing() {
        let intervals = F.intervals(count: 12, apps: [F.usage("hog", cpu: 90)])
        var off = settings
        off.isEnabled = false
        #expect(DrainAlertEvaluator.alerts(for: intervals, settings: off, now: F.start).isEmpty)
        #expect(DrainAlertEvaluator.alerts(for: intervals, settings: settings, now: F.start.addingTimeInterval(3_600)).isEmpty)
    }
}

@Suite("UsageHourAccumulator")
struct UsageHourAccumulatorTests {
    typealias F = ProcessFixtures

    @Test func accumulatesAndRollsOverByHour() throws {
        var accumulator = UsageHourAccumulator(timeZone: TimeZone(identifier: "UTC")!)
        // 12:00–12:59 in 60 s intervals, app at 50% CPU on battery.
        let hour = F.intervals(count: 59, end: F.start.addingTimeInterval(59 * 60), apps: [F.usage("a", cpu: 50)])
        for interval in hour {
            #expect(accumulator.add(interval).isEmpty)
        }
        let pending = try #require(accumulator.pending().first)
        #expect(abs(pending.cpuSeconds - 59 * 30) < 0.001)
        #expect(pending.averageCPUPercent == 50)

        // First interval ending in the next hour flushes 12:00.
        let next = UsageInterval(start: F.start.addingTimeInterval(3_600), end: F.start.addingTimeInterval(3_660), onBattery: false, apps: [F.usage("a", cpu: 10)])
        let finished = accumulator.add(next)
        let record = try #require(finished.first)
        #expect(record.hourStart == F.start)
        #expect(record.appKey == "a")
        #expect(abs(record.onBatterySeconds - 59 * 60) < 0.001)
        #expect(record.peakCPUPercent == 50)
        #expect(accumulator.pending().first?.hourStart == F.start.addingTimeInterval(3_600))
    }

    @Test func lateAppsAreAveragedOverTheWholeObservedHour() throws {
        var accumulator = UsageHourAccumulator(timeZone: TimeZone(identifier: "UTC")!)
        let early = UsageInterval(start: F.start, end: F.start.addingTimeInterval(1_800), onBattery: true, apps: [F.usage("a", cpu: 10)])
        let late = UsageInterval(start: F.start.addingTimeInterval(1_800), end: F.start.addingTimeInterval(3_540), onBattery: true, apps: [F.usage("a", cpu: 10), F.usage("b", cpu: 50)])
        _ = accumulator.add(early)
        _ = accumulator.add(late)
        let b = try #require(accumulator.pending().first { $0.appKey == "b" })
        #expect(b.sampledSeconds == 3_540)  // the hour's observed time, not just b's
        #expect(abs(b.averageCPUPercent - 50 * 1_740 / 3_540) < 0.001)
        #expect(b.activeSeconds == 1_740)
    }

    @Test func seedingContinuesTheHourAfterARelaunch() throws {
        var first = UsageHourAccumulator(timeZone: TimeZone(identifier: "UTC")!)
        _ = first.add(UsageInterval(start: F.start, end: F.start.addingTimeInterval(600), onBattery: false, apps: [F.usage("a", cpu: 50)]))
        let saved = first.pending()

        var relaunched = UsageHourAccumulator(timeZone: TimeZone(identifier: "UTC")!)
        relaunched.seed(with: saved, at: F.start.addingTimeInterval(900))
        _ = relaunched.add(UsageInterval(start: F.start.addingTimeInterval(900), end: F.start.addingTimeInterval(1_500), onBattery: false, apps: [F.usage("a", cpu: 50)]))
        let record = try #require(relaunched.pending().first)
        #expect(record.cpuSeconds == 600)  // 300 before + 300 after the relaunch
        #expect(record.sampledSeconds == 1_200)

        // Readers keep the latest cumulative record per (app, hour).
        let merged = AppUsageRecord.latestPerAppAndHour(saved + relaunched.pending())
        #expect(merged.count == 1)
        #expect(merged.first?.cpuSeconds == 600)
    }

    @Test func memoryIsTrackedPerHour() throws {
        var accumulator = UsageHourAccumulator(timeZone: TimeZone(identifier: "UTC")!)
        let app = AppUsage(
            id: "a", displayName: "a", appBundlePath: nil, processCount: 1, cpuPercent: 5,
            memoryBytes: 1_000, threadCount: nil, energyMilliwatts: nil, diskBytesPerSecond: nil,
            wakeupsPerSecond: nil, impact: .estimated(.low, basis: "t"), shareOfActivity: 1
        )
        _ = accumulator.add(UsageInterval(start: F.start, end: F.start.addingTimeInterval(60), onBattery: nil, apps: [app]))
        let record = try #require(accumulator.pending().first)
        #expect(record.averageMemoryBytes == 1_000)
        #expect(record.peakMemoryBytes == 1_000)
    }

    @Test func oldRecordsWithoutMemoryStillDecode() throws {
        let json = #"{"appKey":"a","cpuSeconds":1,"displayName":"a","hourStart":1793448000,"onBatterySeconds":0,"peakCPUPercent":1,"sampledSeconds":60}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let record = try decoder.decode(AppUsageRecord.self, from: Data(json.utf8))
        #expect(record.averageMemoryBytes == nil)
    }

    @Test func idleAppsDoNotProduceRecords() {
        var accumulator = UsageHourAccumulator(timeZone: TimeZone(identifier: "UTC")!)
        _ = accumulator.add(UsageInterval(start: F.start, end: F.start.addingTimeInterval(60), onBattery: nil, apps: [F.usage("idle", cpu: 0)]))
        #expect(accumulator.flush().isEmpty)
    }
}
