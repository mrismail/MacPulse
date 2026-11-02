import Foundation
import MacPulseDomain
import MacPulseShared
import Observation

/// What the scan is doing.
public enum ScanState: Equatable, Sendable {
    case idle
    case scanning(ScanProgress)
    case finished(ScanResult)
}

/// Size filter for the largest-files list.
public enum FileSizeFilter: Int64, CaseIterable, Identifiable, Sendable {
    case any = 0
    case over10MB = 10_000_000
    case over100MB = 100_000_000
    case over1GB = 1_000_000_000

    public var id: Int64 { rawValue }

    public var title: String {
        switch self {
        case .any: String(localized: "Any size")
        case .over10MB: String(localized: "Over 10 MB")
        case .over100MB: String(localized: "Over 100 MB")
        case .over1GB: String(localized: "Over 1 GB")
        }
    }
}

/// How many locations were skipped for one reason.
public struct SkipCount: Identifiable, Equatable, Sendable {
    public var id: SkipReason { reason }
    public let reason: SkipReason
    public let count: Int
}

@MainActor
@Observable
public final class SpaceAnalyzerViewModel {
    // Volumes
    public private(set) var volumes: [VolumeInfo] = []
    public var selectedVolumeID: String?
    public private(set) var volumeError: AppError?
    public private(set) var hasLoadedVolumes = false

    // Scan
    public private(set) var state: ScanState = .idle
    /// The folder shown in the tree (drill-down); `nil` means the scan root.
    public private(set) var currentFolderID: String?
    public var folderSortOrder: [KeyPathComparator<ScanNode>] = [KeyPathComparator(\ScanNode.allocatedBytes, order: .reverse)]
    public var fileSortOrder: [KeyPathComparator<ScanNode>] = [KeyPathComparator(\ScanNode.allocatedBytes, order: .reverse)]
    public var categoryFilter: FileCategory?
    public var sizeFilter: FileSizeFilter = .any
    /// Folders the user picked in the folder panel; protected locations inside them are scanned.
    public private(set) var approvedRoots: [String] = []
    public var exclusions: [String] = []

    @ObservationIgnored private let volumeRepository: any VolumeRepository
    @ObservationIgnored private let scanner: any FileSystemScanning
    @ObservationIgnored private let homePath: String
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    public init(volumes: any VolumeRepository, scanner: any FileSystemScanning, homePath: String = NSHomeDirectory()) {
        volumeRepository = volumes
        self.scanner = scanner
        self.homePath = homePath
    }

    // MARK: Volumes

    public var selectedVolume: VolumeInfo? {
        volumes.first { $0.id == selectedVolumeID } ?? volumes.first
    }

    public func loadVolumes() async {
        do {
            volumes = try await volumeRepository.volumes()
            volumeError = nil
            if selectedVolumeID == nil || !volumes.contains(where: { $0.id == selectedVolumeID }) {
                selectedVolumeID = volumes.first?.id
            }
        } catch {
            let appError = AppError.wrapping(error, userMessage: String(localized: "Couldn't read the mounted volumes."))
            Log.logger(.fileSystem).log(appError, context: "Volumes")
            volumeError = appError
        }
        hasLoadedVolumes = true
    }

    /// Reloads volumes whenever one is mounted, unmounted or renamed, until cancelled.
    public func observeVolumes() async {
        await loadVolumes()
        for await _ in await volumeRepository.changes() {
            await loadVolumes()
        }
    }

    // MARK: Scanning

    public var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    public var result: ScanResult? {
        if case .finished(let result) = state { return result }
        return nil
    }

    public var homeFolder: String { homePath }

    /// Scans the selected volume (the whole startup disk, or an external drive).
    public func scanSelectedVolume() {
        guard let volume = selectedVolume else { return }
        scan(volume.mountPath)
    }

    public func scanHomeFolder() {
        scan(homePath)
    }

    /// Scans a folder the user picked in the folder panel. Picking approves protected
    /// locations inside it (macOS may still ask once).
    public func scanPickedFolder(_ path: String) {
        let path = ScanPathPolicy.normalized(path)
        if !approvedRoots.contains(path) { approvedRoots.append(path) }
        scan(path)
    }

    public func scan(_ rootPath: String) {
        scanTask?.cancel()
        let root = ScanPathPolicy.normalized(rootPath)
        let policy = ScanPathPolicy(
            homePath: homePath,
            userExclusions: exclusions,
            approvedRoots: approvedRoots + [root]
        )
        let request = ScanRequest(rootPath: root, policy: policy)
        currentFolderID = nil
        state = .scanning(ScanProgress(itemsScanned: 0, allocatedBytes: 0, currentFolder: root))
        let scanner = scanner
        // The view model lives as long as the app; holding it during a scan is fine.
        let report: @Sendable (ScanProgress) -> Void = { progress in
            Task { @MainActor in self.update(progress) }
        }
        scanTask = Task {
            let result = await scanner.scan(request, progress: report)
            self.finish(result)
        }
    }

    public func cancelScan() {
        scanTask?.cancel()
    }

    /// Waits for the running scan to finish (used by tests and diagnostics).
    public func waitForScan() async {
        await scanTask?.value
    }

    private func update(_ progress: ScanProgress) {
        guard isScanning else { return }
        state = .scanning(progress)
    }

    private func finish(_ result: ScanResult) {
        state = .finished(result)
        scanTask = nil
    }

    // MARK: Tree

    /// The folder shown in the tree.
    public var currentFolder: ScanNode? {
        guard let root = result?.root else { return nil }
        guard let currentFolderID else { return root }
        return root.node(withID: currentFolderID) ?? root
    }

    /// The current folder's contents in the chosen order.
    public var folderContents: [ScanNode] {
        (currentFolder?.children ?? []).sorted(using: folderSortOrder)
    }

    /// From the scan root down to the current folder.
    public var breadcrumb: [ScanNode] {
        guard let root = result?.root, let current = currentFolder else { return [] }
        var trail: [ScanNode] = [root]
        var node = root
        while node.id != current.id, let next = node.children?.first(where: { $0.kind == .folder && ScanPathPolicy.path(current.id, isInside: $0.id) }) {
            trail.append(next)
            node = next
        }
        return trail
    }

    /// Opens a folder in the tree. Files, packages and "smaller files" don't open.
    public func open(_ nodeID: ScanNode.ID) {
        guard let node = result?.root.node(withID: nodeID), node.kind == .folder else { return }
        currentFolderID = node.id
    }

    public func goUp() {
        let trail = breadcrumb
        guard trail.count > 1 else { return }
        currentFolderID = trail[trail.count - 2].id
    }

    // MARK: Largest files and categories

    public var largestFiles: [ScanNode] {
        (result?.largestFiles ?? [])
            .filter { categoryFilter == nil || $0.category == categoryFilter }
            .filter { $0.allocatedBytes >= sizeFilter.rawValue }
            .sorted(using: fileSortOrder)
    }

    /// Skipped locations by reason, most first.
    public var skippedSummary: [SkipCount] {
        let skipped = result?.skipped ?? []
        return Dictionary(grouping: skipped, by: \.reason)
            .map { SkipCount(reason: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : "\($0.reason)" < "\($1.reason)" }
    }

    /// Protected folders the scan skipped, so the view can offer to pick them.
    public var skippedProtectedFolders: [String] {
        (result?.skipped ?? []).filter { $0.reason == .protectedByPrivacy }.map(\.path)
    }
}
