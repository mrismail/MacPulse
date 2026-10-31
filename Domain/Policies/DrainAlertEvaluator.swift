import Foundation

/// User-configurable alert rule.
public struct DrainAlertSettings: Sendable, Equatable, Codable {
    public var isEnabled: Bool
    /// Average CPU (percent of one core) that counts as heavy use.
    public var cpuThresholdPercent: Double
    /// How long the use must last before alerting.
    public var sustainedMinutes: Int
    /// Only alert while running on battery.
    public var onlyOnBattery: Bool
    /// Also post a macOS notification (needs the user's permission).
    public var sendsNotifications: Bool

    public init(
        isEnabled: Bool = true,
        cpuThresholdPercent: Double = 50,
        sustainedMinutes: Int = 10,
        onlyOnBattery: Bool = true,
        sendsNotifications: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.cpuThresholdPercent = cpuThresholdPercent
        self.sustainedMinutes = sustainedMinutes
        self.onlyOnBattery = onlyOnBattery
        self.sendsNotifications = sendsNotifications
    }
}

/// An app that has used heavy CPU for the configured time.
public struct DrainAlert: Identifiable, Sendable, Equatable {
    public var id: String { appKey }
    public let appKey: String
    public let displayName: String
    public let averageCPUPercent: Double
    public let since: Date
    public let minutes: Int

    public init(appKey: String, displayName: String, averageCPUPercent: Double, since: Date, minutes: Int) {
        self.appKey = appKey
        self.displayName = displayName
        self.averageCPUPercent = averageCPUPercent
        self.since = since
        self.minutes = minutes
    }

    /// Explains why the alert fired, in plain language. CPU is never presented as battery %.
    public var explanation: String {
        let percent = Int(averageCPUPercent.rounded())
        return "\(displayName) has averaged \(percent)% CPU for the last \(minutes) minutes. Sustained CPU use is a common cause of faster battery drain."
    }
}

public enum DrainAlertEvaluator {
    /// Apps whose average CPU stayed above the threshold across intervals covering at
    /// least `sustainedMinutes` (ending at the latest interval). Gaps longer than twice
    /// the typical interval break the run, so sleep never counts as sustained use.
    public static func alerts(
        for intervals: [UsageInterval],
        settings: DrainAlertSettings,
        now: Date
    ) -> [DrainAlert] {
        guard settings.isEnabled, settings.sustainedMinutes > 0 else { return [] }
        let required = TimeInterval(settings.sustainedMinutes * 60)

        // Most recent contiguous run of intervals.
        let sorted = intervals.sorted { $0.start < $1.start }
        guard let last = sorted.last, now.timeIntervalSince(last.end) <= max(120, last.duration * 2) else { return [] }
        var run: [UsageInterval] = []
        for interval in sorted.reversed() {
            if let later = run.last, later.start.timeIntervalSince(interval.end) > max(120, interval.duration * 2) { break }
            if settings.onlyOnBattery && interval.onBattery != true { break }
            run.append(interval)
        }
        run.reverse()
        guard let first = run.first, last.end.timeIntervalSince(first.start) >= required else { return [] }

        // Only intervals inside the required window count.
        let windowStart = last.end.addingTimeInterval(-required)
        let window = run.filter { $0.end > windowStart }
        let duration = window.map(\.duration).reduce(0, +)
        guard duration > 0 else { return [] }

        var cpuSeconds: [String: Double] = [:]
        var minimumCPU: [String: Double] = [:]
        var names: [String: String] = [:]
        var presence: [String: Int] = [:]
        for interval in window {
            for app in interval.apps {
                cpuSeconds[app.id, default: 0] += app.cpuPercent / 100 * interval.duration
                minimumCPU[app.id] = min(minimumCPU[app.id] ?? .infinity, app.cpuPercent)
                names[app.id] = app.displayName
                presence[app.id, default: 0] += 1
            }
        }

        return cpuSeconds.compactMap { key, seconds -> DrainAlert? in
            let average = seconds / duration * 100
            // Sustained: above threshold on average and in every interval of the window.
            guard presence[key] == window.count,
                  average >= settings.cpuThresholdPercent,
                  (minimumCPU[key] ?? 0) >= settings.cpuThresholdPercent * 0.5
            else { return nil }
            return DrainAlert(
                appKey: key,
                displayName: names[key] ?? key,
                averageCPUPercent: average,
                since: windowStart,
                minutes: settings.sustainedMinutes
            )
        }
        .sorted { $0.averageCPUPercent > $1.averageCPUPercent }
    }
}
