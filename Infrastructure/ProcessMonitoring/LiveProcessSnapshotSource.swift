import AppKit
import Darwin
import Foundation
import MacPulseDomain

/// Reads the current user's processes with public, documented APIs:
/// `proc_listpids(PROC_UID_ONLY)`, `proc_pid_rusage`, `proc_pidpath`, `proc_name` and
/// `host_statistics`. Read-only: never signals, never attaches to a process, no admin
/// rights. Processes of other users (root and system daemons) are counted but not read.
///
/// Cost per sample (ADR-012): one kernel-filtered pid list and one `proc_pid_rusage` per
/// user process. Paths and names are looked up once per process and refreshed every
/// ten minutes (a process that `exec`s keeps its pid and start time).
public actor LiveProcessSnapshotSource: ProcessSnapshotSource {
    private struct PathInfo: Sendable {
        let executablePath: String?
        let appBundlePath: String?
        let name: String
        let checkedAt: Date
    }

    /// Wall-clock time spent in each part of the last snapshot, for the overhead benchmark.
    public struct Timing: Sendable, Codable, Equatable {
        public var listMilliseconds = 0.0
        public var countersMilliseconds = 0.0
        public var namesMilliseconds = 0.0
        public var systemMilliseconds = 0.0
    }

    private static let pathRefreshInterval: TimeInterval = 10 * 60

    private let timebase: MachTimebase
    private let userID: uid_t
    private let ownPID: pid_t
    /// Per-process path and name, cached by identity.
    private var pathCache: [ProcessIdentity: PathInfo] = [:]
    private var displayNameCache: [String: String] = [:]
    public private(set) var lastTiming = Timing()

    public init() {
        timebase = MachTimebase.current
        userID = getuid()
        ownPID = getpid()
    }

    public func snapshot(at timestamp: Date) async -> ProcessSnapshot {
        let clock = ContinuousClock()
        var timing = Timing()
        var mark = clock.now
        func lap() -> Double {
            let now = clock.now
            defer { mark = now }
            let elapsed = now - mark
            return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
        }

        let pids = ProcessTable.pids(ofUser: userID)
        let total = ProcessTable.totalProcessCount()
        timing.listMilliseconds = lap()

        var readings: [(pid: pid_t, usage: rusage_info_v4)] = []
        readings.reserveCapacity(pids.count)
        for pid in pids {
            // rusage carries the start time used for identity; a process that exited
            // between listing and reading is simply skipped.
            if let usage = ProcessTable.resourceUsage(of: pid) {
                readings.append((pid, usage))
            }
        }
        timing.countersMilliseconds = lap()

        var samples: [ProcessSample] = []
        samples.reserveCapacity(readings.count)
        var seen = Set<ProcessIdentity>()
        for (pid, usage) in readings {
            let identity = ProcessIdentity(pid: pid, startTime: usage.ri_proc_start_abstime)
            seen.insert(identity)
            let path = pathInfo(for: identity, at: timestamp)
            samples.append(ProcessSample(
                identity: identity,
                name: path.name,
                executablePath: path.executablePath,
                appBundlePath: path.appBundlePath,
                cpuTimeNanoseconds: timebase.nanoseconds(fromTicks: usage.ri_user_time + usage.ri_system_time),
                residentBytes: usage.ri_resident_size,
                footprintBytes: usage.ri_phys_footprint,
                billedEnergyNanojoules: usage.ri_billed_energy,
                diskReadBytes: usage.ri_diskio_bytesread,
                diskWrittenBytes: usage.ri_diskio_byteswritten,
                // Package idle wake-ups — what Activity Monitor shows as "Idle Wake Ups".
                // (Interrupt wake-ups already include these, so the two are never added.)
                wakeups: usage.ri_pkg_idle_wkups
            ))
        }
        // Forget processes that have exited.
        if pathCache.count > seen.count {
            pathCache = pathCache.filter { seen.contains($0.key) }
        }
        let bundles = Set(samples.compactMap(\.appBundlePath))
        let names = await displayNames(for: bundles)
        timing.namesMilliseconds = lap()

        let ticks = ProcessTable.hostCPUTicks()
        let pressure = ProcessTable.memoryPressureLevel().flatMap { MemoryPressureLevel(rawValue: Int($0)) }
        timing.systemMilliseconds = lap()
        lastTiming = timing

        return ProcessSnapshot(
            timestamp: timestamp,
            awakeUptime: ProcessInfo.processInfo.systemUptime,
            memoryPressure: pressure,
            processes: samples,
            unreadableProcessCount: max(0, total - pids.count),
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
            appDisplayNames: names
        )
    }

    // MARK: Names

    private func pathInfo(for identity: ProcessIdentity, at now: Date) -> PathInfo {
        if let cached = pathCache[identity], now.timeIntervalSince(cached.checkedAt) < Self.pathRefreshInterval {
            return cached
        }
        let executable = ProcessTable.executablePath(of: identity.pid)
        let name = ProcessTable.name(of: identity.pid)
            ?? executable.map { ($0 as NSString).lastPathComponent }
            ?? "pid \(identity.pid)"
        let info = PathInfo(
            executablePath: executable,
            appBundlePath: executable.flatMap(AppUsageAggregator.outermostAppBundle(in:)),
            name: name,
            checkedAt: now
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
        var result: [String: String] = [:]
        result.reserveCapacity(bundles.count)
        for bundle in bundles {
            result[bundle] = displayNameCache[bundle]
        }
        return result
    }

    static func folderName(of bundlePath: String) -> String {
        let last = (bundlePath as NSString).lastPathComponent
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }
}
