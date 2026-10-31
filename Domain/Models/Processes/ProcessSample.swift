import Foundation

/// Identifies one process instance. pids are reused by macOS, so the start time is
/// part of the identity: two processes with the same pid are never merged.
public struct ProcessIdentity: Hashable, Sendable, Codable {
    public let pid: Int32
    /// Process start time, microseconds since 1970.
    public let startTime: UInt64

    public init(pid: Int32, startTime: UInt64) {
        self.pid = pid
        self.startTime = startTime
    }
}

/// Cumulative counters for one process at one moment, as read from macOS.
///
/// Counters are totals since the process started; activity is derived from the
/// difference between two samples. Optional fields are `nil` when macOS did not
/// provide them (for example energy accounting on some Macs).
public struct ProcessSample: Sendable, Equatable {
    public let identity: ProcessIdentity
    public let name: String
    public let parentPID: Int32
    /// Full executable path; used only to group helper processes under their app.
    public let executablePath: String?
    /// Outermost `.app` bundle containing the executable, if any.
    public let appBundlePath: String?

    /// User + system CPU time, nanoseconds.
    public let cpuTimeNanoseconds: UInt64
    public let residentBytes: UInt64?
    /// Memory footprint (what Activity Monitor calls "Memory").
    public let footprintBytes: UInt64?
    public let threadCount: Int?
    /// Energy macOS has attributed to the process, nanojoules.
    public let billedEnergyNanojoules: UInt64?
    public let diskReadBytes: UInt64?
    public let diskWrittenBytes: UInt64?
    /// Interrupt plus package-idle wake-ups.
    public let wakeups: UInt64?

    public init(
        identity: ProcessIdentity,
        name: String,
        parentPID: Int32 = 1,
        executablePath: String? = nil,
        appBundlePath: String? = nil,
        cpuTimeNanoseconds: UInt64,
        residentBytes: UInt64? = nil,
        footprintBytes: UInt64? = nil,
        threadCount: Int? = nil,
        billedEnergyNanojoules: UInt64? = nil,
        diskReadBytes: UInt64? = nil,
        diskWrittenBytes: UInt64? = nil,
        wakeups: UInt64? = nil
    ) {
        self.identity = identity
        self.name = name
        self.parentPID = parentPID
        self.executablePath = executablePath
        self.appBundlePath = appBundlePath
        self.cpuTimeNanoseconds = cpuTimeNanoseconds
        self.residentBytes = residentBytes
        self.footprintBytes = footprintBytes
        self.threadCount = threadCount
        self.billedEnergyNanojoules = billedEnergyNanojoules
        self.diskReadBytes = diskReadBytes
        self.diskWrittenBytes = diskWrittenBytes
        self.wakeups = wakeups
    }
}

/// System-wide CPU tick counters (`HOST_CPU_LOAD_INFO`).
public struct SystemCPUTicks: Sendable, Equatable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public var busy: UInt64 { user + system + nice }
    public var total: UInt64 { busy + idle }
}

/// Everything read in one sampling pass.
public struct ProcessSnapshot: Sendable, Equatable {
    public let timestamp: Date
    /// The current user's processes that could be read.
    public let processes: [ProcessSample]
    /// Processes of other users (root, system daemons) that macOS does not let a normal
    /// app read. Reported so the UI can say what is not included.
    public let unreadableProcessCount: Int
    public let systemCPU: SystemCPUTicks?
    public let logicalCPUCount: Int
    /// MacPulse's own pid, to report its overhead.
    public let ownPID: Int32
    /// Display names for app bundle paths, e.g. "/Applications/Safari.app" → "Safari".
    public let appDisplayNames: [String: String]

    public init(
        timestamp: Date,
        processes: [ProcessSample],
        unreadableProcessCount: Int = 0,
        systemCPU: SystemCPUTicks? = nil,
        logicalCPUCount: Int = 1,
        ownPID: Int32 = -1,
        appDisplayNames: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.processes = processes
        self.unreadableProcessCount = unreadableProcessCount
        self.systemCPU = systemCPU
        self.logicalCPUCount = logicalCPUCount
        self.ownPID = ownPID
        self.appDisplayNames = appDisplayNames
    }
}
