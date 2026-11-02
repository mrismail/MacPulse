import Foundation

/// Mounted volumes and their filesystem-reported capacity.
public protocol VolumeRepository: Sendable {
    /// Volumes the user can browse (startup disk, external and network drives, disk images).
    func volumes() async throws -> [VolumeInfo]
    /// Yields whenever a volume is mounted or unmounted.
    func changes() async -> AsyncStream<Void>
}

/// Walks a folder tree, read-only.
///
/// Implementations must: never follow symbolic links; never visit a folder twice
/// (device + inode); stay on the starting volume; apply the request's `ScanPathPolicy`
/// before descending; count hard-linked files once; size packages as one item; stop
/// promptly when the calling task is cancelled, returning what it found so far with
/// `isComplete == false`.
public protocol FileSystemScanning: Sendable {
    /// - Parameter progress: called at most every `limits.progressInterval` seconds, off
    ///   the main actor.
    func scan(_ request: ScanRequest, progress: @escaping @Sendable (ScanProgress) -> Void) async -> ScanResult
}

/// Past scan summaries (no file names). Kept 180 days.
public protocol ScanHistoryRepository: Sendable {
    func append(_ summary: ScanSummary) async throws
    func summaries() async throws -> [ScanSummary]
    func deleteAll() async throws
}

/// The user's excluded folders.
public protocol ScanSettingsStore: Sendable {
    func loadExclusions() -> [String]
    func saveExclusions(_ paths: [String])
}

/// Keeps scan history for the session only (fallback and previews).
public actor InMemoryScanHistory: ScanHistoryRepository {
    private var stored: [ScanSummary]

    public init(_ summaries: [ScanSummary] = []) {
        stored = summaries
    }

    public func append(_ summary: ScanSummary) { stored.append(summary) }
    public func summaries() -> [ScanSummary] { stored }
    public func deleteAll() { stored.removeAll() }
}

/// Keeps exclusions for the session only (fallback and previews).
public final class InMemoryScanSettingsStore: ScanSettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var exclusions: [String]

    public init(exclusions: [String] = []) {
        self.exclusions = exclusions
    }

    public func loadExclusions() -> [String] { lock.withLock { exclusions } }
    public func saveExclusions(_ paths: [String]) { lock.withLock { exclusions = paths } }
}
