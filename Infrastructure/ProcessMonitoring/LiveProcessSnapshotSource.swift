import Darwin
import Foundation
import MacPulseDomain

/// Reads the current user's processes with public, documented APIs:
/// `sysctl(KERN_PROC_ALL)`, `proc_pidinfo`, `proc_pid_rusage`, `proc_pidpath` and
/// `host_statistics`. Read-only: never signals, never attaches to a process, no admin rights.
///
/// Processes of other users (root and system daemons) are counted but not read.
public actor LiveProcessSnapshotSource: ProcessSnapshotSource {
    private struct PathInfo: Sendable {
        let executablePath: String?
        let appBundlePath: String?
        let name: String
    }

    private let timebase: MachTimebase
    private let userID: uid_t
    private let ownPID: pid_t
    /// Per-process path and name, cached by identity (paths don't change for a process).
    private var pathCache: [ProcessIdentity: PathInfo] = [:]
    private var displayNameCache: [String: String] = [:]

    public init() {
        timebase = MachTimebase.current
        userID = getuid()
        ownPID = getpid()
    }

    public func snapshot(at timestamp: Date) -> ProcessSnapshot {
        let table = ProcessTable.entries()
        var samples: [ProcessSample] = []
        samples.reserveCapacity(table.count)
        var unreadable = 0
        var seen = Set<ProcessIdentity>()

        for entry in table where entry.pid > 0 {
            guard entry.uid == userID else {
                unreadable += 1
                continue
            }
            let identity = ProcessIdentity(pid: entry.pid, startTime: entry.startTimeMicroseconds)
            let usage = ProcessTable.resourceUsage(of: entry.pid)
            let task = ProcessTable.taskInfo(of: entry.pid)

            let cpuTicks: UInt64
            if let task {
                cpuTicks = task.pti_total_user + task.pti_total_system
            } else if let usage {
                cpuTicks = usage.ri_user_time + usage.ri_system_time
            } else {
                // Exited between listing and reading, or not readable.
                continue
            }

            seen.insert(identity)
            let path = pathInfo(for: identity, shortName: entry.shortName)
            samples.append(ProcessSample(
                identity: identity,
                name: path.name,
                parentPID: entry.parentPID,
                executablePath: path.executablePath,
                appBundlePath: path.appBundlePath,
                cpuTimeNanoseconds: timebase.nanoseconds(fromTicks: cpuTicks),
                residentBytes: task.map { UInt64($0.pti_resident_size) },
                footprintBytes: usage.map { $0.ri_phys_footprint },
                threadCount: task.map { Int($0.pti_threadnum) },
                billedEnergyNanojoules: usage.map { $0.ri_billed_energy },
                diskReadBytes: usage.map { $0.ri_diskio_bytesread },
                diskWrittenBytes: usage.map { $0.ri_diskio_byteswritten },
                wakeups: usage.map { $0.ri_interrupt_wkups + $0.ri_pkg_idle_wkups }
            ))
        }

        // Forget processes that have exited.
        pathCache = pathCache.filter { seen.contains($0.key) }

        let bundles = Set(samples.compactMap(\.appBundlePath))
        let ticks = ProcessTable.hostCPUTicks()
        return ProcessSnapshot(
            timestamp: timestamp,
            processes: samples,
            unreadableProcessCount: unreadable,
            systemCPU: ticks.map {
                SystemCPUTicks(
                    user: UInt64($0.cpu_ticks.0),
                    system: UInt64($0.cpu_ticks.1),
                    idle: UInt64($0.cpu_ticks.2),
                    nice: UInt64($0.cpu_ticks.3)
                )
            },
            logicalCPUCount: ProcessInfo.processInfo.activeProcessorCount,
            ownPID: ownPID,
            appDisplayNames: displayNames(for: bundles)
        )
    }

    private func pathInfo(for identity: ProcessIdentity, shortName: String) -> PathInfo {
        if let cached = pathCache[identity] { return cached }
        let executable = ProcessTable.executablePath(of: identity.pid)
        let name = ProcessTable.name(of: identity.pid)
            ?? executable.map { ($0 as NSString).lastPathComponent }
            ?? shortName
        let info = PathInfo(
            executablePath: executable,
            appBundlePath: executable.flatMap(AppUsageAggregator.outermostAppBundle(in:)),
            name: name
        )
        pathCache[identity] = info
        return info
    }

    private func displayNames(for bundles: Set<String>) -> [String: String] {
        var result: [String: String] = [:]
        for bundle in bundles {
            if let cached = displayNameCache[bundle] {
                result[bundle] = cached
                continue
            }
            // Finder's localized display name, without the ".app" extension.
            var name = FileManager.default.displayName(atPath: bundle)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            displayNameCache[bundle] = name
            result[bundle] = name
        }
        return result
    }
}
