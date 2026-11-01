import Darwin
import Foundation
import MacPulseDomain

/// What one monitoring sample costs MacPulse itself (Phase 3 acceptance evidence).
public struct OverheadReport: Sendable, Codable, Equatable {
    public var samples: Int
    public var processCount: Int
    /// CPU time MacPulse spent per sample (process read + aggregation), milliseconds.
    public var cpuMillisecondsPerSample: Double
    /// MacPulse's own wake-ups per sample.
    public var wakeupsPerSample: Double
    /// Equivalent average CPU at the background (60 s) and detailed (10 s) rates, % of one core.
    public var cpuPercentAtBackgroundRate: Double
    public var cpuPercentAtDetailedRate: Double
    public var footprintBytes: UInt64
    /// Average wall-clock milliseconds per snapshot phase, to see where time goes.
    public var averageTiming: LiveProcessSnapshotSource.Timing
}

/// Runs the real sampling path in an otherwise idle MacPulse process and measures its own
/// CPU time with `proc_pid_rusage`. Must run in its own process: inside a parallel test
/// run, other tests' CPU would be counted too.
public enum OverheadBenchmark {
    public static let launchArgument = "--macpulse-overhead-benchmark"
    public static let outputPrefix = "MACPULSE_OVERHEAD "

    public static func run(samples: Int = 30) async -> OverheadReport {
        let source = LiveProcessSnapshotSource()
        let pid = getpid()
        var previous = await source.snapshot(at: Date())  // warm caches, as the monitor does
        let before = ProcessTable.resourceUsage(of: pid)
        var timing = LiveProcessSnapshotSource.Timing()
        for index in 1...samples {
            let next = await source.snapshot(at: Date().addingTimeInterval(Double(index)))
            let last = await source.lastTiming
            timing.listMilliseconds += last.listMilliseconds / Double(samples)
            timing.countersMilliseconds += last.countersMilliseconds / Double(samples)
            timing.namesMilliseconds += last.namesMilliseconds / Double(samples)
            timing.systemMilliseconds += last.systemMilliseconds / Double(samples)
            let activity = ProcessActivityCalculator.activity(from: previous, to: next)
            _ = AppUsageAggregator.aggregate(activity, displayNames: next.appDisplayNames, excludingPID: pid, basis: .cpu)
            previous = next
        }
        let after = ProcessTable.resourceUsage(of: pid)

        let timebase = MachTimebase.current
        let ticks = { (usage: rusage_info_v4?) in (usage?.ri_user_time ?? 0) + (usage?.ri_system_time ?? 0) }
        let cpuNanoseconds = timebase.nanoseconds(fromTicks: ticks(after) &- ticks(before))
        let perSample = Double(cpuNanoseconds) / Double(samples) / 1_000_000
        let wakeups = Double((after?.ri_interrupt_wkups ?? 0) &- (before?.ri_interrupt_wkups ?? 0)) / Double(samples)
        return OverheadReport(
            samples: samples,
            processCount: previous.processes.count,
            cpuMillisecondsPerSample: perSample,
            wakeupsPerSample: wakeups,
            cpuPercentAtBackgroundRate: perSample / 60_000 * 100,
            cpuPercentAtDetailedRate: perSample / 10_000 * 100,
            footprintBytes: after?.ri_phys_footprint ?? 0,
            averageTiming: timing
        )
    }

    public static func encode(_ report: OverheadReport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(report)) ?? Data("{}".utf8)
        return outputPrefix + String(decoding: data, as: UTF8.self)
    }
}
