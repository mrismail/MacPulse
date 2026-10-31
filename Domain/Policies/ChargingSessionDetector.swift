import Foundation

/// A continuous period on external power.
public struct ChargingSession: Identifiable, Sendable, Equatable {
    public var id: Date { start }
    public let start: Date
    public let end: Date
    public let startPercentage: Double?
    public let endPercentage: Double?
    /// The Mac is still on external power (last sample is plugged in and recent).
    public let isOngoing: Bool

    public init(start: Date, end: Date, startPercentage: Double?, endPercentage: Double?, isOngoing: Bool) {
        self.start = start
        self.end = end
        self.startPercentage = startPercentage
        self.endPercentage = endPercentage
        self.isOngoing = isOngoing
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Percentage points gained during the session, if both ends are known.
    public var percentageGained: Double? {
        guard let startPercentage, let endPercentage else { return nil }
        return endPercentage - startPercentage
    }
}

/// Groups history samples into charging sessions.
public enum ChargingSessionDetector {
    /// A gap larger than this between plugged-in samples splits the session
    /// (the Mac slept or MacPulse was not running, so we cannot vouch for the gap).
    public static let defaultMaximumGap: TimeInterval = 15 * 60

    public static func sessions(
        from snapshots: [BatterySnapshot],
        now: Date,
        maximumGap: TimeInterval = defaultMaximumGap
    ) -> [ChargingSession] {
        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }
        var sessions: [ChargingSession] = []
        var current: [BatterySnapshot] = []

        func close(ongoing: Bool) {
            guard let first = current.first, let last = current.last else { return }
            sessions.append(ChargingSession(
                start: first.timestamp,
                end: last.timestamp,
                startPercentage: first.percentage,
                endPercentage: last.percentage,
                isOngoing: ongoing
            ))
            current.removeAll()
        }

        for snapshot in sorted {
            if snapshot.isPluggedIn == true {
                if let last = current.last, snapshot.timestamp.timeIntervalSince(last.timestamp) > maximumGap {
                    close(ongoing: false)
                }
                current.append(snapshot)
            } else {
                close(ongoing: false)
            }
        }
        if let last = current.last {
            close(ongoing: now.timeIntervalSince(last.timestamp) <= maximumGap)
        }
        return sessions
    }
}
