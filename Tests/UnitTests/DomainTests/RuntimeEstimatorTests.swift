import Foundation
import Testing
@testable import MacPulseDomain

/// Builds a sample series: `values` are percentages, one per `interval` seconds, ending at `end`.
func series(
    _ values: [Double],
    interval: TimeInterval = 60,
    end: Date = BatteryFixtures.date,
    pluggedIn: Bool = false
) -> [BatterySnapshot] {
    values.enumerated().map { index, value in
        BatterySnapshot(
            timestamp: end.addingTimeInterval(-Double(values.count - 1 - index) * interval),
            percentage: value,
            isCharging: pluggedIn,
            isPluggedIn: pluggedIn
        )
    }
}

@Suite("RuntimeEstimator")
struct RuntimeEstimatorTests {
    private let now = BatteryFixtures.date

    @Test func steadyDischargeGivesExpectedRuntime() throws {
        // 1 point every 2 minutes over 20 minutes: 0.5 %/min → 50% left = 100 minutes.
        let values = stride(from: 60.0, through: 50.0, by: -1.0).map { $0 }
        let estimate = RuntimeEstimator.estimate(from: series(values, interval: 120), now: now)

        #expect(estimate.runtime.value == 100)
        guard case .estimated(let basis) = estimate.runtime.provenance else {
            Issue.record("Runtime must be an estimate")
            return
        }
        #expect(basis.contains("20 minutes"))
        let rate = try #require(estimate.ratePercentPerHour.value)
        #expect(abs(rate - 30) < 0.0001)
    }

    @Test func tooFewSamplesIsUnavailable() {
        let estimate = RuntimeEstimator.estimate(from: series([60, 59], interval: 300), now: now)
        #expect(estimate.runtime.provenance == .unavailable(.notYetSampled))
    }

    @Test func tooShortSpanIsUnavailable() {
        let estimate = RuntimeEstimator.estimate(from: series([60, 59, 58, 57], interval: 60), now: now)
        #expect(estimate.runtime.value == nil)  // only 3 minutes covered
    }

    @Test func noDropIsUnavailable() {
        let estimate = RuntimeEstimator.estimate(from: series(Array(repeating: 80, count: 10), interval: 60), now: now)
        #expect(estimate.runtime.value == nil)
        #expect(estimate.ratePercentPerHour.value == nil)
    }

    @Test func pluggedInSamplesAreExcluded() {
        let charging = series([40, 45, 50, 55, 60], interval: 60, end: now.addingTimeInterval(-600), pluggedIn: true)
        let discharging = series([60, 60, 59, 59, 58], interval: 120, end: now)
        let run = RuntimeEstimator.recentDischargeRun(charging + discharging, now: now, parameters: .init())
        #expect(run.count == 5)
        #expect(run.allSatisfy { $0.isPluggedIn == false })
    }

    @Test func gapEndsTheRun() {
        let old = series([90, 89, 88, 87, 86, 85], interval: 120, end: now.addingTimeInterval(-15 * 60))
        let recent = series([70, 69, 68], interval: 120, end: now)
        let run = RuntimeEstimator.recentDischargeRun(old + recent, now: now, parameters: .init())
        #expect(run.map(\.percentage) == [70, 69, 68])
    }

    @Test func staleHistoryIsIgnored() {
        let values = stride(from: 60.0, through: 50.0, by: -1.0).map { $0 }
        let stale = series(values, interval: 120, end: now.addingTimeInterval(-20 * 60))
        #expect(RuntimeEstimator.estimate(from: stale, now: now).runtime.value == nil)
    }

    @Test func chargeRiseOnBatteryEndsTheRun() {
        // Charged while MacPulse wasn't watching: 50 → 80 between samples.
        let samples = series([52, 51, 50, 80, 79, 78], interval: 120, end: now)
        let run = RuntimeEstimator.recentDischargeRun(samples, now: now, parameters: .init())
        #expect(run.map(\.percentage) == [80, 79, 78])
    }

    @Test func absurdlyLongEstimateIsNotShown() {
        // 1 point over 30 minutes at 99% → ~49 h, above the 24 h cap.
        let values: [Double] = [100, 100, 100, 100, 100, 99.5, 99.5, 99.5, 99, 99, 99, 99, 99, 99, 99, 99]
        let estimate = RuntimeEstimator.estimate(from: series(values, interval: 120), now: now)
        #expect(estimate.runtime.value == nil)
    }

    @Test func slopeOfLine() {
        let slope = RuntimeEstimator.leastSquaresSlope([(0, 10), (1, 8), (2, 6)])
        #expect(slope == -2)
        #expect(RuntimeEstimator.leastSquaresSlope([(1, 1)]) == nil)
        #expect(RuntimeEstimator.leastSquaresSlope([(1, 1), (1, 2)]) == nil)
    }
}

@Suite("ChargingSessionDetector")
struct ChargingSessionDetectorTests {
    private let now = BatteryFixtures.date

    @Test func detectsOneCompletedSession() throws {
        let before = series([50, 49], interval: 300, end: now.addingTimeInterval(-3_600))
        let charging = series([49, 60, 70, 80], interval: 300, end: now.addingTimeInterval(-1_800), pluggedIn: true)
        let after = series([80, 79], interval: 300, end: now)
        let sessions = ChargingSessionDetector.sessions(from: before + charging + after, now: now)

        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.startPercentage == 49)
        #expect(session.endPercentage == 80)
        #expect(session.percentageGained == 31)
        #expect(session.duration == 900)
        #expect(!session.isOngoing)
    }

    @Test func ongoingSessionIsFlagged() throws {
        let charging = series([30, 40, 50], interval: 300, end: now, pluggedIn: true)
        let session = try #require(ChargingSessionDetector.sessions(from: charging, now: now).first)
        #expect(session.isOngoing)
    }

    @Test func longGapSplitsSessions() {
        let first = series([20, 30], interval: 300, end: now.addingTimeInterval(-7_200), pluggedIn: true)
        let second = series([60, 70], interval: 300, end: now, pluggedIn: true)
        let sessions = ChargingSessionDetector.sessions(from: second + first, now: now)  // unsorted input
        #expect(sessions.count == 2)
        #expect(sessions[0].start < sessions[1].start)
    }

    @Test func noPluggedInSamplesMeansNoSessions() {
        #expect(ChargingSessionDetector.sessions(from: series([80, 79, 78]), now: now).isEmpty)
    }
}
