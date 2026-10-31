import AppKit
import Darwin
import Foundation
import MacPulseDomain

/// Reads the current user's processes with public, documented APIs:
/// `sysctl(KERN_PROC_ALL)`, `proc_pid_rusage` (falling back to `proc_pidinfo`),
/// `proc_pidpath` and `host_statistics`. Read-only: never signals, never attaches to a
/// process, no admin rights.
///
/// Processes of other users (root and system daemons) are counted but not read.
public actor LiveProcessSnapshotSource: ProcessSnapshotSource {
    private struct PathInfo: Sendable {
        let shortName: String
        let executablePath: String?
        let appBundlePath: String?
        let name: String
    }

    private let timebase: MachTimebase
    private let userID: uid_t
    private let ownPID: pid_t
    /// Per-process path and name, cached by identity. Re-read if the short name changes
    /// (a process that `exec`s keeps its pid and start time, e.g. xpcproxy → service).
    private var pathCache: [ProcessIdentity: PathInfo] = [:]
    private var displayNameCache: [String: String] = [:]

    public init() {
        timebase = MachTimebase.current
        userID = getuid()
        ownPID = getpid()
    }

    public func snapshot(at timestamp: Date) async -> ProcessSnapshot {
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
            guard let counters = readCounters(of: entry.pid) else {
                continue  // exited between listing and reading
            }
            seen.insert(identity)
            let path = pathInfo(for: identity, shortName: entry.shortName)
            samples.append(ProcessSample(
                identity: identity,
                name: path.name,
                parentPID: entry.parentPID,
                executablePath: path.executablePath,
                appBundlePath: path.appBundlePath,
                cpuTimeNanoseconds: timebase.nanoseconds(fromTicks: counters.cpuTicks),
                residentBytes: counters.resident,
                footprintBytes: counters.footprint,
                threadCount: counters.threads,
                billedEnergyNanojoules: counters.billedEnergy,
                diskReadBytes: counters.diskRead,
                diskWrittenBytes: counters.diskWritten,
                wakeups: counters.idleWakeups
            ))
        }

        // Forget processes that have exited.
        pathCache = pathCache.filter { seen.contains($0.key) }

        let bundles = Set(samples.compactMap(\.appBundlePath))
        let ticks = ProcessTable.hostCPUTicks()
        return ProcessSnapshot(
            timestamp: timestamp,
            awakeUptime: ProcessInfo.processInfo.systemUptime,
            memoryPressure: ProcessTable.memoryPressureLevel().flatMap { MemoryPressureLevel(rawValue: Int($0)) },
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
            appDisplayNames: await displayNames(for: bundles)
        )
    }

    // MARK: Counters

    private struct Counters {
        var cpuTicks: UInt64
        var resident: UInt64?
        var footprint: UInt64?
        var threads: Int?
        var billedEnergy: UInt64?
        var diskRead: UInt64?
        var diskWritten: UInt64?
        /// Package idle wake-ups — the figure Activity Monitor shows as "Idle Wake Ups".
        /// (Interrupt wake-ups already include these, so the two are never added.)
        var idleWakeups: UInt64?
    }

    /// One `proc_pid_rusage` call gives CPU, memory, energy, disk and wake-ups.
    /// `proc_pidinfo` is only used if rusage is refused.
    private func readCounters(of pid: pid_t) -> Counters? {
        if let usage = ProcessTable.resourceUsage(of: pid) {
            return Counters(
                cpuTicks: usage.ri_user_time + usage.ri_system_time,
                resident: usage.ri_resident_size,
                footprint: usage.ri_phys_footprint,
                threads: nil,
                billedEnergy: usage.ri_billed_energy,
                diskRead: usage.ri_diskio_bytesread,
                diskWritten: usage.ri_diskio_byteswritten,
                idleWakeups: usage.ri_pkg_idle_wkups
            )
        }
        if let task = ProcessTable.taskInfo(of: pid) {
            return Counters(
                cpuTicks: task.pti_total_user + task.pti_total_system,
                resident: task.pti_resident_size,
                threads: Int(task.pti_threadnum)
            )
        }
        return nil
    }

    // MARK: Names

    private func pathInfo(for identity: ProcessIdentity, shortName: String) -> PathInfo {
        if let cached = pathCache[identity], cached.shortName == shortName { return cached }
        let executable = ProcessTable.executablePath(of: identity.pid)
        let name = ProcessTable.name(of: identity.pid)
            ?? executable.map { ($0 as NSString).lastPathComponent }
            ?? shortName
        let info = PathInfo(
            shortName: shortName,
            executablePath: executable,
            appBundlePath: executable.flatMap(AppUsageAggregator.outermostAppBundle(in:)),
            name: name
        )
        pathCache[identity] = info
        return info
    }

    /// Display names come from running apps (`NSRunningApplication.localizedName`) or the
    /// bundle's folder name. Nothing is read from disk, so apps running from Downloads or
    /// a disk image never trigger a macOS privacy prompt.
    private func displayNames(for bundles: Set<String>) async -> [String: String] {
        let missing = bundles.filter { displayNameCache[$0] == nil }
        if !missing.isEmpty {
            let running = await MainActor.run { () -> [String: String] in
                var names: [String: String] = [:]
                for app in NSWorkspace.shared.runningApplications {
                    if let path = app.bundleURL?.path, let name = app.localizedName {
                        names[path] = name
                    }
                }
                return names
            }
            for bundle in missing {
                displayNameCache[bundle] = running[bundle] ?? Self.folderName(of: bundle)
            }
        }
        return displayNameCache.filter { bundles.contains($0.key) }
    }

    static func folderName(of bundlePath: String) -> String {
        let last = (bundlePath as NSString).lastPathComponent
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }
}
