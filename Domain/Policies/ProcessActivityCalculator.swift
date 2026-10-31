import Foundation

/// Turns two snapshots into per-process activity over the interval between them.
public enum ProcessActivityCalculator {
    /// Activity for every process present in both snapshots (same pid *and* start time).
    /// Processes that started or exited in between are skipped, as are counters that
    /// went backwards, so a reused pid or a counter reset can never produce a spike.
    public static func activity(from previous: ProcessSnapshot, to current: ProcessSnapshot) -> [ProcessActivity] {
        let interval = current.timestamp.timeIntervalSince(previous.timestamp)
        guard interval > 0 else { return [] }
        let before = Dictionary(previous.processes.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })

        return current.processes.compactMap { now in
            guard let then = before[now.identity],
                  now.cpuTimeNanoseconds >= then.cpuTimeNanoseconds
            else { return nil }

            let cpuSeconds = Double(now.cpuTimeNanoseconds - then.cpuTimeNanoseconds) / 1_000_000_000
            return ProcessActivity(
                identity: now.identity,
                name: now.name,
                appBundlePath: now.appBundlePath,
                cpuPercent: cpuSeconds / interval * 100,
                memoryBytes: now.footprintBytes ?? now.residentBytes,
                threadCount: now.threadCount,
                energyMilliwatts: rate(now.billedEnergyNanojoules, then.billedEnergyNanojoules, interval)
                    .map { $0 / 1_000_000 },  // nJ/s = nW → mW
                diskBytesPerSecond: diskRate(now: now, then: then, interval: interval),
                wakeupsPerSecond: rate(now.wakeups, then.wakeups, interval)
            )
        }
    }

    /// System-wide busy fraction (0–1) between two tick readings.
    ///
    /// macOS keeps these counters as 32-bit values that wrap (after weeks of uptime), so
    /// differences are computed modulo 2³².
    public static func systemBusyFraction(from previous: SystemCPUTicks?, to current: SystemCPUTicks?) -> Double? {
        guard let previous, let current else { return nil }
        let busy = wrappingDelta(current.user, previous.user)
            + wrappingDelta(current.system, previous.system)
            + wrappingDelta(current.nice, previous.nice)
        let idle = wrappingDelta(current.idle, previous.idle)
        let total = busy + idle
        guard total > 0 else { return nil }
        return Double(busy) / Double(total)
    }

    /// Difference of two 32-bit tick counters, allowing one wrap.
    static func wrappingDelta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        let now = UInt32(truncatingIfNeeded: current)
        let then = UInt32(truncatingIfNeeded: previous)
        return UInt64(now &- then)
    }

    static func rate(_ now: UInt64?, _ then: UInt64?, _ interval: TimeInterval) -> Double? {
        guard let now, let then, now >= then else { return nil }
        return Double(now - then) / interval
    }

    static func diskRate(now: ProcessSample, then: ProcessSample, interval: TimeInterval) -> Double? {
        guard let read = rate(now.diskReadBytes, then.diskReadBytes, interval),
              let written = rate(now.diskWrittenBytes, then.diskWrittenBytes, interval)
        else { return nil }
        return read + written
    }
}
