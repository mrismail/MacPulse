import Darwin
import Foundation

/// One row of the kernel process table (`sysctl(KERN_PROC_ALL)`).
struct ProcessTableEntry: Sendable, Equatable {
    let pid: pid_t
    let uid: uid_t
    let parentPID: pid_t
    /// Start time, microseconds since 1970.
    let startTimeMicroseconds: UInt64
    /// Short command name (up to 16 characters).
    let shortName: String
}

/// Low-level process APIs used by the process monitor and the access probe.
enum ProcessTable {
    /// Every process on the system. Works for any user without special rights.
    static func entries() -> [ProcessTableEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // The table can grow between the two calls; leave headroom.
        size += size / 8
        var raw = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        let ok = raw.withUnsafeMutableBufferPointer { buffer in
            sysctl(&mib, u_int(mib.count), buffer.baseAddress, &size, nil, 0) == 0
        }
        guard ok else { return [] }
        return raw.prefix(size / MemoryLayout<kinfo_proc>.stride).map { info in
            let start = info.kp_proc.p_un.__p_starttime
            return ProcessTableEntry(
                pid: info.kp_proc.p_pid,
                uid: info.kp_eproc.e_ucred.cr_uid,
                parentPID: info.kp_eproc.e_ppid,
                startTimeMicroseconds: UInt64(max(0, start.tv_sec)) * 1_000_000 + UInt64(max(0, start.tv_usec)),
                shortName: commandName(info.kp_proc.p_comm)
            )
        }
    }

    private static func commandName<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { bytes in
            let characters = bytes.prefix { $0 != 0 }
            return String(decoding: characters, as: UTF8.self)
        }
    }

    /// Full process name (longer than the 16-character command name), if readable.
    static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Executable path, if readable.
    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func taskInfo(of pid: pid_t) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size ? info : nil
    }

    static func resourceUsage(of pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info : nil
    }

    static func hostCPUTicks() -> host_cpu_load_info? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? load : nil
    }
}

/// Converts Mach absolute-time ticks to nanoseconds.
///
/// `proc_taskinfo` and `rusage_info` CPU times are in Mach ticks: 1 tick = 1 ns on Intel
/// but not on Apple silicon (e.g. 125/3 ns per tick), so the timebase must be applied.
struct MachTimebase: Sendable, Equatable {
    let numerator: UInt64
    let denominator: UInt64

    static let current: MachTimebase = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else {
            return MachTimebase(numerator: 1, denominator: 1)
        }
        return MachTimebase(numerator: UInt64(info.numer), denominator: UInt64(info.denom))
    }()

    func nanoseconds(fromTicks ticks: UInt64) -> UInt64 {
        guard numerator != denominator else { return ticks }
        let (high, low) = ticks.multipliedFullWidth(by: numerator)
        let (quotient, _) = denominator.dividingFullWidth((high, low))
        return quotient
    }
}
