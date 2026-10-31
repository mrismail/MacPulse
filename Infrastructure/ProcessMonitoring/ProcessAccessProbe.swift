import AppKit
import Darwin
import Foundation

/// Measures which process-information APIs work in this build (ADR-009 spike; kept as
/// a diagnostic after ADR-010 removed the sandbox). Reports only counts and error codes —
/// no process names, paths or arguments — so the output is safe to paste into an issue.
public struct ProcessAccessReport: Sendable, Codable, Equatable {
    public struct Attempt: Sendable, Codable, Equatable {
        public var tried = 0
        public var succeeded = 0
        /// errno → count for failures.
        public var failures: [String: Int] = [:]

        mutating func record(success: Bool, errorNumber: Int32) {
            tried += 1
            if success {
                succeeded += 1
            } else {
                failures[String(errorNumber), default: 0] += 1
            }
        }
    }

    public var macOSVersion = ""
    public var isSandboxed = false
    /// Processes visible via `proc_listallpids`.
    public var listedProcessCount = 0
    /// Processes visible via `sysctl(KERN_PROC_ALL)`.
    public var sysctlProcessCount = 0
    /// Of the "any process" sample, how many belong to the current user.
    public var anyProcessSameUserCount = 0
    /// System-wide CPU ticks via `host_statistics(HOST_CPU_LOAD_INFO)`.
    public var hostCPULoadReadable = false
    /// Regular apps listed by `NSWorkspace.runningApplications`.
    public var runningApplicationCount = 0

    /// `proc_pid_rusage(RUSAGE_INFO_V4)` on MacPulse itself.
    public var ownRusage = Attempt()
    /// Own `ri_billed_energy` (nJ) is non-zero — energy attribution exists on this Mac.
    public var ownBilledEnergyNonZero = false
    /// Same-user GUI apps (from NSWorkspace).
    public var userAppRusage = Attempt()
    public var userAppTaskInfo = Attempt()
    public var userAppBSDInfo = Attempt()
    /// Any other process (includes root/system processes).
    public var anyProcessRusage = Attempt()
    public var anyProcessTaskInfo = Attempt()
}

public enum ProcessAccessProbe {
    public static let launchArgument = "--macpulse-process-access-probe"
    public static let outputPrefix = "MACPULSE_PROCESS_PROBE "

    @MainActor
    public static func run(sampleLimit: Int = 300) -> ProcessAccessReport {
        var report = ProcessAccessReport()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        report.macOSVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        report.isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

        let ownPID = getpid()
        let pids = allPIDs()
        report.listedProcessCount = pids.count
        report.sysctlProcessCount = sysctlProcessCount()
        report.hostCPULoadReadable = hostCPULoadReadable()

        // Own process.
        let own = rusage(of: ownPID)
        report.ownRusage.record(success: own.info != nil, errorNumber: own.errorNumber)
        report.ownBilledEnergyNonZero = (own.info?.ri_billed_energy ?? 0) > 0

        // Same-user GUI apps.
        let apps = NSWorkspace.shared.runningApplications.filter { $0.processIdentifier > 0 && $0.processIdentifier != ownPID }
        report.runningApplicationCount = apps.count
        for app in apps.prefix(sampleLimit) {
            let pid = app.processIdentifier
            let usage = rusage(of: pid)
            report.userAppRusage.record(success: usage.info != nil, errorNumber: usage.errorNumber)
            let task = taskInfo(of: pid)
            report.userAppTaskInfo.record(success: task.ok, errorNumber: task.errorNumber)
            let bsd = bsdInfo(of: pid)
            report.userAppBSDInfo.record(success: bsd.ok, errorNumber: bsd.errorNumber)
        }

        // Any process, from sysctl (proc_listallpids returns nothing in the sandbox).
        let processes = sysctlProcesses()
        let uid = getuid()
        let sample = processes.filter { $0.pid > 0 && $0.pid != ownPID }.prefix(sampleLimit)
        report.anyProcessSameUserCount = sample.filter { $0.uid == uid }.count
        for pid in sample.map(\.pid) {
            let usage = rusage(of: pid)
            report.anyProcessRusage.record(success: usage.info != nil, errorNumber: usage.errorNumber)
            let task = taskInfo(of: pid)
            report.anyProcessTaskInfo.record(success: task.ok, errorNumber: task.errorNumber)
        }
        return report
    }

    /// JSON line for stdout, e.g. in CI.
    @MainActor
    public static func runAndEncode() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(run())) ?? Data("{}".utf8)
        return outputPrefix + String(decoding: data, as: UTF8.self)
    }

    // MARK: APIs under test

    static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) * 2)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    static func sysctlProcessCount() -> Int {
        ProcessTable.entries().count
    }

    /// (pid, uid) for every process, via `sysctl(KERN_PROC_ALL)`.
    static func sysctlProcesses() -> [(pid: pid_t, uid: uid_t)] {
        ProcessTable.entries().map { ($0.pid, $0.uid) }
    }

    static func hostCPULoadReadable() -> Bool {
        ProcessTable.hostCPUTicks() != nil
    }

    static func rusage(of pid: pid_t) -> (info: rusage_info_v4?, errorNumber: Int32) {
        let info = ProcessTable.resourceUsage(of: pid)
        return (info, info == nil ? errno : 0)
    }

    static func taskInfo(of pid: pid_t) -> (ok: Bool, errorNumber: Int32) {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        return result == size ? (true, 0) : (false, errno)
    }

    static func bsdInfo(of pid: pid_t) -> (ok: Bool, errorNumber: Int32) {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        return result == size ? (true, 0) : (false, errno)
    }
}
