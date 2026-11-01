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
    /// Retries when the table grows between the size query and the read (ENOMEM).
    static func entries() -> [ProcessTableEntry] {
        for _ in 0..<3 {
            if let entries = readTable() { return entries }
        }
        return []
    }

    private static func readTable() -> [ProcessTableEntry]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        // The table can grow between the two calls; leave headroom.
        size += size / 4
        var raw = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        let ok = raw.withUnsafeMutableBufferPointer { buffer in
            sysctl(&mib, u_int(mib.count), buffer.baseAddress, &size, nil, 0) == 0
        }
        guard ok else { return nil }  // ENOMEM: grew past the headroom; try again
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

    /// pids of one user's processes, filtered by the kernel (much cheaper than copying the
    /// whole process table, which is ~650 bytes per process).
    static func pids(ofUser uid: uid_t) -> [pid_t] {
        for _ in 0..<3 {
            let estimate = proc_listpids(UInt32(PROC_UID_ONLY), UInt32(uid), nil, 0)
            guard estimate > 0 else { return [] }
            // Headroom for processes started between the two calls.
            var buffer = [pid_t](repeating: 0, count: Int(estimate) / MemoryLayout<pid_t>.size + 64)
            let bytes = buffer.withUnsafeMutableBufferPointer { pointer in
                proc_listpids(UInt32(PROC_UID_ONLY), UInt32(uid), pointer.baseAddress, Int32(pointer.count * MemoryLayout<pid_t>.size))
            }
            guard bytes > 0 else { continue }
            let count = Int(bytes) / MemoryLayout<pid_t>.size
            if count < buffer.count {
                return buffer.prefix(count).filter { $0 > 0 }
            }
        }
        return []
    }

    /// Number of processes on the system (all users), without copying their details.
    static func totalProcessCount() -> Int {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        return bytes > 0 ? Int(bytes) / MemoryLayout<pid_t>.size : 0
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

    /// The host port is constant for the process; look it up once.
    private static let hostPort = mach_host_self()

    static func hostCPUTicks() -> host_cpu_load_info? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? load : nil
    }

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    static func memoryPressureLevel() -> Int32? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return nil }
        return level
    }

    /// `true` when this process runs under Rosetta 2.
    static var isTranslated: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &value, &size, nil, 0) == 0 && value == 1
    }
}

/// Converts Mach absolute-time ticks to nanoseconds.
///
/// `proc_taskinfo` and `rusage_info` CPU times are in Mach ticks: 1 tick = 1 ns on Intel
/// but not on Apple silicon (e.g. 125/3 ns per tick), so the timebase must be applied.
struct MachTimebase: Sendable, Equatable {
    let numerator: UInt64
    let denominator: UInt64

    /// Apple silicon's native timebase: 125/3 ns per tick (24 MHz).
    static let appleSiliconNative = MachTimebase(numerator: 125, denominator: 3)

    static let current: MachTimebase = {
        // Under Rosetta, mach_timebase_info reports 1/1 for the translated process, but
        // the kernel's per-process counters are still in native Apple silicon ticks.
        if ProcessTable.isTranslated {
            return appleSiliconNative
        }
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
