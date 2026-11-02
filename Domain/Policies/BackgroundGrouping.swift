import Foundation

/// Folds processes that aren't apps the user sees (Dock, Notification Center, agents,
/// XPC services, command-line tools) into one "macOS & background" row, like Activity
/// Monitor's Applications view — but the row still counts toward totals and ranking, so
/// heavy background work is never hidden. Its members stay available as `children`.
///
/// Presentation only: history and drain alerts keep working per app or process.
public enum BackgroundGrouping {
    public static let groupID = "group:background"

    public static var groupName: String {
        String(localized: "macOS & background")
    }

    /// - Parameter foregroundApps: bundle paths of apps with a Dock icon. When empty
    ///   (unknown), the list is returned unchanged.
    public static func fold(
        _ apps: [AppUsage],
        foregroundApps: Set<String>,
        basis: AppUsageAggregator.ImpactBasis,
        thresholds: AppUsageAggregator.Thresholds = AppUsageAggregator.Thresholds()
    ) -> [AppUsage] {
        guard !foregroundApps.isEmpty else { return apps }
        var visible: [AppUsage] = []
        var background: [AppUsage] = []
        for app in apps {
            if let path = app.appBundlePath, foregroundApps.contains(path) {
                visible.append(app)
            } else {
                background.append(app)
            }
        }
        guard !background.isEmpty else { return apps }

        let cpu = background.map(\.cpuPercent).reduce(0, +)
        let energy = AppUsageAggregator.sumOptional(background.map(\.energyMilliwatts))
        let impact: Metric<BatteryImpactLevel>
        switch basis {
        case .energy:
            let level = AppUsageAggregator.level(
                energy ?? 0, high: thresholds.highMilliwatts, moderate: thresholds.moderateMilliwatts
            )
            impact = .estimated(level, basis: AppUsageAggregator.energyBasis)
        case .cpu:
            let level = AppUsageAggregator.level(
                cpu, high: thresholds.highCPUPercent, moderate: thresholds.moderateCPUPercent
            )
            impact = .estimated(level, basis: AppUsageAggregator.cpuBasis)
        }
        let group = AppUsage(
            id: groupID,
            displayName: groupName,
            appBundlePath: nil,
            processCount: background.map(\.processCount).reduce(0, +),
            cpuPercent: cpu,
            memoryBytes: AppUsageAggregator.sumOptional(background.map(\.memoryBytes)),
            threadCount: AppUsageAggregator.sumOptional(background.map(\.threadCount)),
            energyMilliwatts: energy,
            diskBytesPerSecond: AppUsageAggregator.sumOptional(background.map(\.diskBytesPerSecond)),
            wakeupsPerSecond: AppUsageAggregator.sumOptional(background.map(\.wakeupsPerSecond)),
            impact: impact,
            shareOfActivity: background.map(\.shareOfActivity).reduce(0, +),
            children: AppUsageAggregator.rank(background)
        )
        return AppUsageAggregator.rank(visible + [group])
    }
}
