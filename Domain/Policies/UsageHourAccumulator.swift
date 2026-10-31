import Foundation

/// Accumulates per-interval app usage into per-hour records for persisted trends.
///
/// Records are cumulative: the record for an (app, hour) written later always contains
/// everything in earlier ones. That lets the monitor save the hour in progress
/// periodically and reload it after a relaunch (`seed`), and readers keep only the latest
/// record per (app, hour) (`AppUsageRecord.latestPerAppAndHour`).
public struct UsageHourAccumulator: Sendable {
    private struct Bucket: Sendable {
        var displayName: String
        var cpuSeconds = 0.0
        var energyJoules: Double?
        var peakCPUPercent = 0.0
        var memoryByteSeconds = 0.0
        var peakMemoryBytes: UInt64 = 0
        /// Time the app was running (had a sample) in this hour.
        var activeSeconds = 0.0
    }

    private var calendar: Calendar
    public private(set) var currentHour: Date?
    private var buckets: [String: Bucket] = [:]
    /// Observed time in the current hour, shared by all apps (an idle app is still observed).
    private var observedSeconds = 0.0
    private var onBatterySeconds = 0.0

    public init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// Continues an hour from records saved earlier (for example before a relaunch).
    /// Ignored unless the records belong to the hour of `date`.
    public mutating func seed(with records: [AppUsageRecord], at date: Date) {
        let hour = hourStart(for: date)
        let relevant = AppUsageRecord.latestPerAppAndHour(records).filter { $0.hourStart == hour }
        guard !relevant.isEmpty, currentHour == nil || currentHour == hour else { return }
        currentHour = hour
        for record in relevant {
            var bucket = Bucket(displayName: record.displayName)
            bucket.cpuSeconds = record.cpuSeconds
            bucket.energyJoules = record.energyJoules
            bucket.peakCPUPercent = record.peakCPUPercent
            bucket.memoryByteSeconds = record.memoryByteSeconds ?? 0
            bucket.peakMemoryBytes = record.peakMemoryBytes ?? 0
            bucket.activeSeconds = record.activeSeconds ?? 0
            buckets[record.appKey] = bucket
        }
        observedSeconds = max(observedSeconds, relevant.map(\.sampledSeconds).max() ?? 0)
        onBatterySeconds = max(onBatterySeconds, relevant.map(\.onBatterySeconds).max() ?? 0)
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
        observedSeconds += interval.duration
        if interval.onBattery == true {
            onBatterySeconds += interval.duration
        }
        for app in interval.apps {
            var bucket = buckets[app.id] ?? Bucket(displayName: app.displayName)
            bucket.displayName = app.displayName
            bucket.cpuSeconds += app.cpuPercent / 100 * interval.duration
            if let milliwatts = app.energyMilliwatts {
                bucket.energyJoules = (bucket.energyJoules ?? 0) + milliwatts / 1_000 * interval.duration
            }
            bucket.peakCPUPercent = max(bucket.peakCPUPercent, app.cpuPercent)
            bucket.activeSeconds += interval.duration
            if let memory = app.memoryBytes {
                bucket.memoryByteSeconds += Double(memory) * interval.duration
                bucket.peakMemoryBytes = max(bucket.peakMemoryBytes, memory)
            }
            buckets[app.id] = bucket
        }
        return finished
    }

    /// Cumulative records for the hour in progress, without resetting it.
    public func pending() -> [AppUsageRecord] {
        guard let currentHour else { return [] }
        return records(for: currentHour)
    }

    /// Ends the current hour and returns its records.
    public mutating func flush() -> [AppUsageRecord] {
        guard let currentHour else { return [] }
        let result = records(for: currentHour)
        buckets.removeAll()
        observedSeconds = 0
        onBatterySeconds = 0
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
                    sampledSeconds: observedSeconds,
                    onBatterySeconds: onBatterySeconds,
                    peakCPUPercent: bucket.peakCPUPercent,
                    memoryByteSeconds: bucket.memoryByteSeconds > 0 ? bucket.memoryByteSeconds : nil,
                    peakMemoryBytes: bucket.peakMemoryBytes > 0 ? bucket.peakMemoryBytes : nil,
                    activeSeconds: bucket.activeSeconds
                )
            }
            .sorted { $0.cpuSeconds > $1.cpuSeconds }
    }

    func hourStart(for date: Date) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }
}
