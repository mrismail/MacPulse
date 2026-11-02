import Foundation

/// Where a volume lives, for grouping and icons.
public enum VolumeKind: String, Sendable, Equatable, Codable {
    /// The startup disk (the Data volume users see as "Macintosh HD").
    case startup
    case `internal`
    case external
    case network
    case diskImage
}

/// A mounted volume and the capacity the filesystem reports for it.
public struct VolumeInfo: Identifiable, Sendable, Equatable {
    /// Volume UUID when available, otherwise the mount path.
    public let id: String
    public let name: String
    /// Mount point, e.g. `/` or `/Volumes/Backup`.
    public let mountPath: String
    public let kind: VolumeKind
    public let fileSystem: String?
    public let isReadOnly: Bool
    public let isEjectable: Bool
    /// Filesystem-reported capacity, bytes.
    public let totalBytes: Metric<Int64>
    /// Filesystem-reported free space, bytes (excludes purgeable space).
    public let availableBytes: Metric<Int64>
    /// Free space including what macOS can purge for important use (caches, local
    /// snapshots, optimised storage), bytes.
    public let availableForImportantUsageBytes: Metric<Int64>

    public init(
        id: String,
        name: String,
        mountPath: String,
        kind: VolumeKind,
        fileSystem: String? = nil,
        isReadOnly: Bool = false,
        isEjectable: Bool = false,
        totalBytes: Metric<Int64>,
        availableBytes: Metric<Int64>,
        availableForImportantUsageBytes: Metric<Int64>
    ) {
        self.id = id
        self.name = name
        self.mountPath = mountPath
        self.kind = kind
        self.fileSystem = fileSystem
        self.isReadOnly = isReadOnly
        self.isEjectable = isEjectable
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.availableForImportantUsageBytes = availableForImportantUsageBytes
    }

    /// Total minus available, as the filesystem reports them.
    public var usedBytes: Metric<Int64> {
        guard let total = totalBytes.value, let available = availableBytes.value else {
            return .unavailable(.notSupportedOnThisMac)
        }
        return .measured(max(0, total - available))
    }

    /// Space macOS can free on demand: important-usage availability minus plain availability.
    public var purgeableBytes: Metric<Int64> {
        guard let important = availableForImportantUsageBytes.value, let available = availableBytes.value else {
            return .unavailable(.notSupportedOnThisMac)
        }
        return .measured(max(0, important - available))
    }

    /// Used fraction (0–1), or `nil` when capacity is unknown.
    public var usedFraction: Double? {
        guard let total = totalBytes.value, total > 0, let used = usedBytes.value else { return nil }
        return Double(used) / Double(total)
    }
}
