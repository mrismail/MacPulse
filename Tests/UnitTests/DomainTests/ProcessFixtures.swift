import Foundation
@testable import MacPulseDomain

enum ProcessFixtures {
    static let start = Date(timeIntervalSince1970: 1_793_448_000)  // 2026-10-31 12:00 UTC

    static func sample(
        pid: Int32,
        started: UInt64 = 1,
        name: String,
        bundle: String? = nil,
        cpuSeconds: Double,
        memory: UInt64 = 100_000_000,
        energyJoules: Double? = nil,
        wakeups: UInt64? = nil,
        disk: UInt64? = nil
    ) -> ProcessSample {
        ProcessSample(
            identity: ProcessIdentity(pid: pid, startTime: started),
            name: name,
            appBundlePath: bundle,
            cpuTimeNanoseconds: UInt64(cpuSeconds * 1_000_000_000),
            residentBytes: memory,
            footprintBytes: memory,
            threadCount: 4,
            billedEnergyNanojoules: energyJoules.map { UInt64($0 * 1_000_000_000) },
            diskReadBytes: disk,
            diskWrittenBytes: disk.map { _ in 0 },
            wakeups: wakeups
        )
    }

    static func snapshot(
        at offset: TimeInterval,
        _ processes: [ProcessSample],
        ownPID: Int32 = 999,
        busy: UInt64? = nil,
        uptime: TimeInterval? = nil
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            timestamp: start.addingTimeInterval(offset),
            awakeUptime: uptime,
            processes: processes,
            unreadableProcessCount: 3,
            // Idle grows 100 ticks per second; busy is cumulative and supplied by the test.
            systemCPU: busy.map { SystemCPUTicks(user: $0, system: 0, idle: 1_000_000 + UInt64(max(0, offset)) * 100, nice: 0) },
            logicalCPUCount: 8,
            ownPID: ownPID,
            appDisplayNames: ["/Applications/Chrome.app": "Google Chrome"]
        )
    }

    static func usage(_ id: String, cpu: Double, name: String? = nil) -> AppUsage {
        AppUsage(
            id: id, displayName: name ?? id, appBundlePath: nil, processCount: 1,
            cpuPercent: cpu, memoryBytes: nil, threadCount: nil, energyMilliwatts: nil,
            diskBytesPerSecond: nil, wakeupsPerSecond: nil,
            impact: .estimated(.low, basis: "test"), shareOfActivity: 0
        )
    }

    /// Intervals of `length` seconds ending at `end`, each with the given apps.
    static func intervals(count: Int, length: TimeInterval = 60, end: Date = start, onBattery: Bool? = true, apps: [AppUsage]) -> [UsageInterval] {
        (0..<count).map { index in
            let intervalEnd = end.addingTimeInterval(-Double(count - 1 - index) * length)
            return UsageInterval(start: intervalEnd.addingTimeInterval(-length), end: intervalEnd, onBattery: onBattery, apps: apps)
        }
    }
}
