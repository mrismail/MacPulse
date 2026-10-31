import Foundation

/// Resource use of one process over one sampling interval.
public struct ProcessActivity: Identifiable, Sendable, Equatable {
    public var id: ProcessIdentity { identity }
    public let identity: ProcessIdentity
    public let name: String
    public let appBundlePath: String?
    /// Percent of one CPU core (Activity Monitor convention: 200% = two full cores).
    public let cpuPercent: Double
    /// Footprint when available, otherwise resident memory.
    public let memoryBytes: UInt64?
    public let threadCount: Int?
    /// Average power macOS attributed to the process, milliwatts.
    public let energyMilliwatts: Double?
    public let diskBytesPerSecond: Double?
    public let wakeupsPerSecond: Double?

    public init(
        identity: ProcessIdentity,
        name: String,
        appBundlePath: String?,
        cpuPercent: Double,
        memoryBytes: UInt64?,
        threadCount: Int?,
        energyMilliwatts: Double?,
        diskBytesPerSecond: Double?,
        wakeupsPerSecond: Double?
    ) {
        self.identity = identity
        self.name = name
        self.appBundlePath = appBundlePath
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.threadCount = threadCount
        self.energyMilliwatts = energyMilliwatts
        self.diskBytesPerSecond = diskBytesPerSecond
        self.wakeupsPerSecond = wakeupsPerSecond
    }
}

/// Battery impact category. Always presented as an estimate.
public enum BatteryImpactLevel: Int, Sendable, Equatable, Comparable, Codable {
    case low
    case moderate
    case high

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Resource use of one app (all its processes, including helpers) over an interval.
public struct AppUsage: Identifiable, Sendable, Equatable {
    /// Stable key: the app bundle path, or `process:<name>` for processes outside an app.
    public let id: String
    public let displayName: String
    public let appBundlePath: String?
    public let processCount: Int
    public let cpuPercent: Double
    public let memoryBytes: UInt64?
    public let threadCount: Int?
    public let energyMilliwatts: Double?
    public let diskBytesPerSecond: Double?
    public let wakeupsPerSecond: Double?
    /// Estimated battery impact, with the basis in its provenance.
    public let impact: Metric<BatteryImpactLevel>
    /// This app's share (0–1) of the activity measure used for `impact`.
    public let shareOfActivity: Double

    public init(
        id: String,
        displayName: String,
        appBundlePath: String?,
        processCount: Int,
        cpuPercent: Double,
        memoryBytes: UInt64?,
        threadCount: Int?,
        energyMilliwatts: Double?,
        diskBytesPerSecond: Double?,
        wakeupsPerSecond: Double?,
        impact: Metric<BatteryImpactLevel>,
        shareOfActivity: Double
    ) {
        self.id = id
        self.displayName = displayName
        self.appBundlePath = appBundlePath
        self.processCount = processCount
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.threadCount = threadCount
        self.energyMilliwatts = energyMilliwatts
        self.diskBytesPerSecond = diskBytesPerSecond
        self.wakeupsPerSecond = wakeupsPerSecond
        self.impact = impact
        self.shareOfActivity = shareOfActivity
    }
}

/// App usage over one sampling interval.
public struct UsageInterval: Sendable, Equatable {
    public let start: Date
    public let end: Date
    /// `true` on battery, `false` on external power, `nil` unknown.
    public let onBattery: Bool?
    public let apps: [AppUsage]

    public init(start: Date, end: Date, onBattery: Bool?, apps: [AppUsage]) {
        self.start = start
        self.end = end
        self.onBattery = onBattery
        self.apps = apps
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// One persisted hour of an app's usage (for trends).
public struct AppUsageRecord: Sendable, Equatable, Codable, Identifiable {
    public var id: String { "\(appKey)|\(hourStart.timeIntervalSince1970)" }
    public let hourStart: Date
    public let appKey: String
    public let displayName: String
    /// CPU time used, seconds (sum over the hour).
    public let cpuSeconds: Double
    /// Energy macOS attributed, joules; `nil` when energy accounting was unavailable.
    public let energyJoules: Double?
    /// How much of the hour MacPulse observed, seconds.
    public let sampledSeconds: Double
    /// How much of the observed time was on battery, seconds.
    public let onBatterySeconds: Double
    public let peakCPUPercent: Double
    /// Memory × observed seconds, for the hourly average. `nil` in records written before
    /// memory trends existed.
    public let memoryByteSeconds: Double?
    public let peakMemoryBytes: UInt64?
    /// How long the app was running during the observed time, seconds.
    public let activeSeconds: Double?

    public init(
        hourStart: Date,
        appKey: String,
        displayName: String,
        cpuSeconds: Double,
        energyJoules: Double?,
        sampledSeconds: Double,
        onBatterySeconds: Double,
        peakCPUPercent: Double,
        memoryByteSeconds: Double? = nil,
        peakMemoryBytes: UInt64? = nil,
        activeSeconds: Double? = nil
    ) {
        self.hourStart = hourStart
        self.appKey = appKey
        self.displayName = displayName
        self.cpuSeconds = cpuSeconds
        self.energyJoules = energyJoules
        self.sampledSeconds = sampledSeconds
        self.onBatterySeconds = onBatterySeconds
        self.peakCPUPercent = peakCPUPercent
        self.memoryByteSeconds = memoryByteSeconds
        self.peakMemoryBytes = peakMemoryBytes
        self.activeSeconds = activeSeconds
    }

    /// Average CPU over the observed part of the hour, percent of one core.
    public var averageCPUPercent: Double {
        sampledSeconds > 0 ? cpuSeconds / sampledSeconds * 100 : 0
    }

    /// Average memory while the app was running during the hour.
    public var averageMemoryBytes: Double? {
        guard let memoryByteSeconds else { return nil }
        let seconds = activeSeconds ?? sampledSeconds
        return seconds > 0 ? memoryByteSeconds / seconds : nil
    }

    /// Records are cumulative snapshots of an hour; for each (app, hour) the last one written
    /// is the most complete. Keeps that one, in time order.
    public static func latestPerAppAndHour(_ records: [AppUsageRecord]) -> [AppUsageRecord] {
        var latest: [String: AppUsageRecord] = [:]
        var order: [String] = []
        for record in records {
            if latest[record.id] == nil { order.append(record.id) }
            latest[record.id] = record
        }
        return order.compactMap { latest[$0] }.sorted { $0.hourStart < $1.hourStart }
    }
}
