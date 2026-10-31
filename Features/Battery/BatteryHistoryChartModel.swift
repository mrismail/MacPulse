import Foundation
import MacPulseDomain

/// Time range offered by the history chart.
public enum BatteryHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case sixHours
    case day
    case week

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sixHours: "6 Hours"
        case .day: "24 Hours"
        case .week: "7 Days"
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .sixHours: 6 * 3_600
        case .day: 24 * 3_600
        case .week: 7 * 24 * 3_600
        }
    }
}

/// One plotted point. `segment` changes wherever history has a gap, so the chart
/// draws separate lines instead of interpolating across time MacPulse did not observe.
public struct BatteryChartPoint: Identifiable, Sendable, Equatable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let percentage: Double
    public let segment: Int
}

/// Prepares history for plotting.
public enum BatteryHistoryChartModel {
    /// A gap longer than this breaks the line.
    public static let gapThreshold: TimeInterval = 15 * 60
    /// Upper bound on plotted points; longer ranges are averaged into buckets.
    public static let maximumPoints = 400

    public static func points(
        from snapshots: [BatterySnapshot],
        maximumPoints: Int = maximumPoints,
        gapThreshold: TimeInterval = gapThreshold
    ) -> [BatteryChartPoint] {
        let valid = snapshots
            .compactMap { snapshot -> (Date, Double)? in
                snapshot.percentage.map { (snapshot.timestamp, $0) }
            }
            .sorted { $0.0 < $1.0 }
        guard !valid.isEmpty else { return [] }

        // Split into segments first so buckets never average across a gap.
        var segments: [[(Date, Double)]] = [[]]
        for sample in valid {
            if let last = segments[segments.count - 1].last, sample.0.timeIntervalSince(last.0) > gapThreshold {
                segments.append([])
            }
            segments[segments.count - 1].append(sample)
        }

        let stride = max(1, Int((Double(valid.count) / Double(max(1, maximumPoints))).rounded(.up)))
        var points: [BatteryChartPoint] = []
        for (index, segment) in segments.enumerated() {
            var start = 0
            while start < segment.count {
                let bucket = segment[start..<min(start + stride, segment.count)]
                let averageTime = bucket.map { $0.0.timeIntervalSinceReferenceDate }.reduce(0, +) / Double(bucket.count)
                let averageValue = bucket.map(\.1).reduce(0, +) / Double(bucket.count)
                points.append(BatteryChartPoint(
                    timestamp: Date(timeIntervalSinceReferenceDate: averageTime),
                    percentage: averageValue,
                    segment: index
                ))
                start += stride
            }
        }
        return points
    }
}
