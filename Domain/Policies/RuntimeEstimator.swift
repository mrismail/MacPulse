import Foundation

/// Estimates remaining battery runtime from recent discharge history.
///
/// Method: take the most recent uninterrupted run of on-battery samples inside
/// `window`, fit a least-squares line to charge over time, and divide the current
/// charge by the discharge rate. Refuses to estimate when the data is too thin, so the
/// UI shows "Unavailable" instead of a noisy number.
public enum RuntimeEstimator {
    public struct Parameters: Sendable, Equatable {
        /// How far back to look.
        public var window: TimeInterval = 30 * 60
        /// Minimum time covered by the samples used.
        public var minimumSpan: TimeInterval = 5 * 60
        /// Minimum number of samples used.
        public var minimumSamples = 3
        /// Minimum charge drop (percentage points) — below this the rate is mostly rounding noise.
        public var minimumDrop = 1.0
        /// A larger gap between samples (sleep, app closed) ends the run.
        public var maximumGap: TimeInterval = 10 * 60
        /// Estimates above this are not shown.
        public var maximumMinutes = 24 * 60

        public init() {}
    }

    public struct Estimate: Sendable, Equatable {
        public let runtime: Metric<Int>
        public let ratePercentPerHour: Metric<Double>
    }

    public static func estimate(
        from snapshots: [BatterySnapshot],
        now: Date,
        parameters: Parameters = Parameters()
    ) -> Estimate {
        let run = recentDischargeRun(snapshots, now: now, parameters: parameters)

        guard let latest = run.last, let currentCharge = latest.percentage else {
            return notEnoughData
        }
        guard run.count >= parameters.minimumSamples,
              let first = run.first,
              latest.timestamp.timeIntervalSince(first.timestamp) >= parameters.minimumSpan,
              let firstCharge = first.percentage,
              firstCharge - currentCharge >= parameters.minimumDrop
        else {
            return notEnoughData
        }

        // Least-squares slope of charge (percentage points) against time (minutes).
        let origin = first.timestamp
        let points = run.compactMap { snapshot -> (x: Double, y: Double)? in
            guard let y = snapshot.percentage else { return nil }
            return (snapshot.timestamp.timeIntervalSince(origin) / 60, y)
        }
        guard let slope = leastSquaresSlope(points), slope < 0 else {
            return notEnoughData
        }

        let ratePerMinute = -slope
        let minutes = Int((currentCharge / ratePerMinute).rounded())
        let spanMinutes = Int((latest.timestamp.timeIntervalSince(first.timestamp) / 60).rounded())
        let basis = "Based on your discharge rate over the last \(spanMinutes) minutes."
        let rate = Metric<Double>.estimated(ratePerMinute * 60, basis: basis)

        guard minutes <= parameters.maximumMinutes else {
            return Estimate(runtime: .unavailable(.notYetSampled), ratePercentPerHour: rate)
        }
        return Estimate(runtime: .estimated(minutes, basis: basis), ratePercentPerHour: rate)
    }

    private static let notEnoughData = Estimate(
        runtime: .unavailable(.notYetSampled),
        ratePercentPerHour: .unavailable(.notYetSampled)
    )

    /// The newest contiguous sequence of on-battery samples, oldest first.
    static func recentDischargeRun(
        _ snapshots: [BatterySnapshot],
        now: Date,
        parameters: Parameters
    ) -> [BatterySnapshot] {
        let sorted = snapshots
            .filter { $0.timestamp <= now && $0.timestamp >= now.addingTimeInterval(-parameters.window) }
            .sorted { $0.timestamp < $1.timestamp }

        guard let newest = sorted.last, now.timeIntervalSince(newest.timestamp) <= parameters.maximumGap else {
            return []
        }

        var run: [BatterySnapshot] = []
        for snapshot in sorted.reversed() {
            guard snapshot.isPluggedIn == false, snapshot.percentage != nil else { break }
            if let later = run.last, later.timestamp.timeIntervalSince(snapshot.timestamp) > parameters.maximumGap {
                break
            }
            // Charge rising while on battery means a gap we did not see (e.g. charged while asleep).
            if let later = run.last, let laterCharge = later.percentage, let charge = snapshot.percentage,
               laterCharge > charge + 0.5 {
                break
            }
            run.append(snapshot)
        }
        return run.reversed()
    }

    static func leastSquaresSlope(_ points: [(x: Double, y: Double)]) -> Double? {
        let n = Double(points.count)
        guard n >= 2 else { return nil }
        let meanX = points.map(\.x).reduce(0, +) / n
        let meanY = points.map(\.y).reduce(0, +) / n
        var numerator = 0.0
        var denominator = 0.0
        for point in points {
            numerator += (point.x - meanX) * (point.y - meanY)
            denominator += (point.x - meanX) * (point.x - meanX)
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }
}
