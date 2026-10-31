import Foundation

/// Basic, non-sensitive facts about the Mac and the running app, shown on the
/// Overview and in Settings → Diagnostics.
public struct SystemInfo: Sendable, Equatable {
    public enum Architecture: String, Sendable, Equatable {
        case appleSilicon
        case intel
        case unknown
    }

    /// For example "14.5.0".
    public let macOSVersion: String
    /// Model identifier such as "MacBookPro16,1". `nil` if the system did not report one.
    public let hardwareModel: String?
    public let architecture: Architecture
    public let processorCount: Int
    public let physicalMemoryBytes: UInt64
    public let appVersion: String?
    public let appBuild: String?

    public init(
        macOSVersion: String,
        hardwareModel: String?,
        architecture: Architecture,
        processorCount: Int,
        physicalMemoryBytes: UInt64,
        appVersion: String?,
        appBuild: String?
    ) {
        self.macOSVersion = macOSVersion
        self.hardwareModel = hardwareModel
        self.architecture = architecture
        self.processorCount = processorCount
        self.physicalMemoryBytes = physicalMemoryBytes
        self.appVersion = appVersion
        self.appBuild = appBuild
    }

    /// Whether the model identifier indicates a portable Mac (MacBook family).
    /// Used only as a hint; battery presence is confirmed by the battery service.
    public var isLikelyPortable: Bool {
        hardwareModel?.hasPrefix("MacBook") ?? false
    }
}
