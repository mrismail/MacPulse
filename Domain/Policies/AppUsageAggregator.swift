import Foundation

/// Groups process activity by app and estimates each app's battery impact.
///
/// Impact is always an **estimate** and never a battery percentage:
/// - When macOS energy accounting is available for the interval, it is based on the
///   power macOS attributes to the app.
/// - Otherwise it is based on CPU use, the dominant driver of battery drain for apps.
public enum AppUsageAggregator {
    /// Which measure the impact estimate uses. Chosen once per session (see
    /// `ProcessMonitor`), so labels and rankings don't flip between intervals.
    public enum ImpactBasis: Sendable, Equatable {
        /// macOS energy accounting (`ri_billed_energy`) has been seen on this Mac.
        case energy
        /// No energy accounting seen: CPU-based activity, not a battery measurement.
        case cpu
    }

    public struct Thresholds: Sendable, Equatable {
        /// Power above which an app counts as high / moderate impact, milliwatts.
        public var highMilliwatts = 2_000.0
        public var moderateMilliwatts = 400.0
        /// CPU (percent of one core) above which an app counts as high / moderate impact.
        public var highCPUPercent = 50.0
        public var moderateCPUPercent = 10.0

        public init() {}
    }

    public static var energyBasis: String {
        String(localized: "Estimated from the energy macOS attributes to this app's processes.")
    }

    public static var cpuBasis: String {
        String(localized: "Estimated from CPU use only. This Mac hasn't reported per-app energy, so this shows activity, not measured battery use.")
    }

    /// Apps ranked by estimated impact, then CPU.
    public static func aggregate(
        _ activities: [ProcessActivity],
        displayNames: [String: String],
        excludingPID ownPID: Int32? = nil,
        basis: ImpactBasis,
        thresholds: Thresholds = Thresholds()
    ) -> [AppUsage] {
        let relevant = activities.filter { $0.identity.pid != ownPID }
        let groups = Dictionary(grouping: relevant, by: groupKey)

        // One basis for every app, so the ranking is consistent. An idle interval on an
        // energy-reporting Mac stays energy-based (0 W), it doesn't fall back to CPU.
        let useEnergy = basis == .energy
        let totalEnergy = relevant.compactMap(\.energyMilliwatts).reduce(0, +)
        let totalCPU = relevant.map(\.cpuPercent).reduce(0, +)

        let apps = groups.map { key, members -> AppUsage in
            let bundlePath = members.first?.appBundlePath
            let cpu = members.map(\.cpuPercent).reduce(0, +)
            let energy = sumOptional(members.map(\.energyMilliwatts))
            let impact: Metric<BatteryImpactLevel>
            let share: Double
            if useEnergy {
                let power = energy ?? 0
                share = totalEnergy > 0 ? power / totalEnergy : 0
                impact = .estimated(level(power, high: thresholds.highMilliwatts, moderate: thresholds.moderateMilliwatts), basis: energyBasis)
            } else {
                share = totalCPU > 0 ? cpu / totalCPU : 0
                impact = .estimated(level(cpu, high: thresholds.highCPUPercent, moderate: thresholds.moderateCPUPercent), basis: cpuBasis)
            }
            return AppUsage(
                id: key,
                displayName: displayName(key: key, bundlePath: bundlePath, members: members, names: displayNames),
                appBundlePath: bundlePath,
                processCount: members.count,
                cpuPercent: cpu,
                memoryBytes: sumOptional(members.map(\.memoryBytes)),
                threadCount: sumOptional(members.map(\.threadCount)),
                energyMilliwatts: useEnergy ? (energy ?? 0) : nil,
                diskBytesPerSecond: sumOptional(members.map(\.diskBytesPerSecond)),
                wakeupsPerSecond: sumOptional(members.map(\.wakeupsPerSecond)),
                impact: impact,
                shareOfActivity: share
            )
        }
        return rank(apps)
    }

    /// Highest estimated impact first, then highest share, then name for stability.
    public static func rank(_ apps: [AppUsage]) -> [AppUsage] {
        apps.sorted { lhs, rhs in
            let left = lhs.impact.value ?? .low
            let right = rhs.impact.value ?? .low
            if left != right { return left > right }
            if lhs.shareOfActivity != rhs.shareOfActivity { return lhs.shareOfActivity > rhs.shareOfActivity }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// Averages several intervals into one usage per app, weighting by duration.
    /// Apps missing from an interval count as idle for it.
    public static func average(_ intervals: [UsageInterval], basis: ImpactBasis, thresholds: Thresholds = Thresholds()) -> [AppUsage] {
        let totalDuration = intervals.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else { return [] }
        let useEnergy = basis == .energy

        var latest: [String: AppUsage] = [:]
        var cpuSeconds: [String: Double] = [:]
        var energyJoules: [String: Double] = [:]
        var wakeups: [String: Double] = [:]
        for interval in intervals {
            for app in interval.apps {
                latest[app.id] = app
                cpuSeconds[app.id, default: 0] += app.cpuPercent / 100 * interval.duration
                energyJoules[app.id, default: 0] += (app.energyMilliwatts ?? 0) / 1_000 * interval.duration
                wakeups[app.id, default: 0] += (app.wakeupsPerSecond ?? 0) * interval.duration
            }
        }
        let totalCPUSeconds = cpuSeconds.values.reduce(0, +)
        let totalJoules = energyJoules.values.reduce(0, +)

        let apps = latest.values.map { app -> AppUsage in
            let cpu = (cpuSeconds[app.id] ?? 0) / totalDuration * 100
            let milliwatts = (energyJoules[app.id] ?? 0) / totalDuration * 1_000
            let impact: Metric<BatteryImpactLevel>
            let share: Double
            if useEnergy {
                share = totalJoules > 0 ? (energyJoules[app.id] ?? 0) / totalJoules : 0
                impact = .estimated(level(milliwatts, high: thresholds.highMilliwatts, moderate: thresholds.moderateMilliwatts), basis: energyBasis)
            } else {
                share = totalCPUSeconds > 0 ? (cpuSeconds[app.id] ?? 0) / totalCPUSeconds : 0
                impact = .estimated(level(cpu, high: thresholds.highCPUPercent, moderate: thresholds.moderateCPUPercent), basis: cpuBasis)
            }
            return AppUsage(
                id: app.id,
                displayName: app.displayName,
                appBundlePath: app.appBundlePath,
                processCount: app.processCount,
                cpuPercent: cpu,
                memoryBytes: app.memoryBytes,
                threadCount: app.threadCount,
                energyMilliwatts: useEnergy ? milliwatts : nil,
                diskBytesPerSecond: app.diskBytesPerSecond,
                wakeupsPerSecond: app.wakeupsPerSecond == nil ? nil : (wakeups[app.id] ?? 0) / totalDuration,
                impact: impact,
                shareOfActivity: share
            )
        }
        return rank(apps)
    }

    // MARK: Helpers

    static func groupKey(_ activity: ProcessActivity) -> String {
        activity.appBundlePath ?? "process:\(activity.name)"
    }

    static func displayName(key: String, bundlePath: String?, members: [ProcessActivity], names: [String: String]) -> String {
        if let bundlePath {
            if let name = names[bundlePath], !name.isEmpty { return name }
            let last = (bundlePath as NSString).lastPathComponent
            return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
        }
        return members.first?.name ?? key
    }

    static func level(_ value: Double, high: Double, moderate: Double) -> BatteryImpactLevel {
        if value >= high { return .high }
        if value >= moderate { return .moderate }
        return .low
    }

    static func sumOptional<T: AdditiveArithmetic>(_ values: [T?]) -> T? {
        let present = values.compactMap { $0 }
        return present.isEmpty ? nil : present.reduce(.zero, +)
    }

    /// The outermost `.app` bundle in a path, so helpers nested inside an app's
    /// `Contents/Frameworks/…/Helper.app` are attributed to the app itself.
    public static func outermostAppBundle(in executablePath: String) -> String? {
        let components = (executablePath as NSString).pathComponents
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return NSString.path(withComponents: Array(components[...index]))
    }
}
