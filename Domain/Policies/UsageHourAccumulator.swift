import Foundation

/// Accumulates per-interval app usage into per-hour records for persisted trends.
public struct UsageHourAccumulator: Sendable {
    private struct Bucket: Sendable {
        var displayName: String
        var cpuSeconds = 0.0
        var energyJoules: Double?
        var sampledSeconds = 0.0
        var onBatterySeconds = 0.0
        var peakCPUPercent = 0.0
    }

    private var calendar: Calendar
    private(set) var currentHour: Date?
    private var buckets: [String: Bucket] = [:]

    public init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// Adds one interval. Returns the finished hour's records when the interval starts a
    /// new hour (attributed to the hour the interval ends in).
    public mutating func add(_ interval: UsageInterval) -> [AppUsageRecord] {
        let hour = hourStart(for: interval.end)
        var finished: [AppUsageRecord] = []
        if let currentHour, currentHour != hour {
            finished = flush()
        }
        currentHour = hour
        for app in interval.apps {
            var bucket = buckets[app.id] ?? Bucket(displayName: app.displayName)
            bucket.displayName = app.displayName
            bucket.cpuSeconds += app.cpuPercent / 100 * interval.duration
            if let milliwatts = app.energyMilliwatts {
                bucket.energyJoules = (bucket.energyJoules ?? 0) + milliwatts / 1_000 * interval.duration
            }
            bucket.peakCPUPercent = max(bucket.peakCPUPercent, app.cpuPercent)
            buckets[app.id] = bucket
        }
        // Observed time is per interval, shared by every app (idle apps count as observed).
        for key in buckets.keys {
            buckets[key]?.sampledSeconds += interval.duration
            if interval.onBattery == true {
                buckets[key]?.onBatterySeconds += interval.duration
            }
        }
        return finished
    }

    /// Records for the hour in progress, without resetting it (for showing the current hour).
    public func pending() -> [AppUsageRecord] {
        guard let currentHour else { return [] }
        return records(for: currentHour)
    }

    /// Ends the current hour and returns its records.
    public mutating func flush() -> [AppUsageRecord] {
        guard let currentHour else { return [] }
        let result = records(for: currentHour)
        buckets.removeAll()
        self.currentHour = nil
        return result
    }

    private func records(for hour: Date) -> [AppUsageRecord] {
        buckets
            .filter { $0.value.cpuSeconds > 0 || ($0.value.energyJoules ?? 0) > 0 }
            .map { key, bucket in
                AppUsageRecord(
                    hourStart: hour,
                    appKey: key,
                    displayName: bucket.displayName,
                    cpuSeconds: bucket.cpuSeconds,
                    energyJoules: bucket.energyJoules,
                    sampledSeconds: bucket.sampledSeconds,
                    onBatterySeconds: bucket.onBatterySeconds,
                    peakCPUPercent: bucket.peakCPUPercent
                )
            }
            .sorted { $0.cpuSeconds > $1.cpuSeconds }
    }

    func hourStart(for date: Date) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }
}
