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
