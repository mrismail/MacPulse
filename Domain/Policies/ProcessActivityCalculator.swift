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
    public static func systemBusyFraction(from previous: SystemCPUTicks?, to current: SystemCPUTicks?) -> Double? {
        guard let previous, let current,
              current.total > previous.total, current.busy >= previous.busy
        else { return nil }
        return Double(current.busy - previous.busy) / Double(current.total - previous.total)
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
