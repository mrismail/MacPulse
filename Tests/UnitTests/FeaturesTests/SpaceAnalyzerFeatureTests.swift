import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseFeatures

private struct FailingVolumes: VolumeRepository {
    struct Failure: Error {}
    func volumes() async throws -> [VolumeInfo] { throw Failure() }
    func changes() async -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

@Suite("SpaceAnalyzerViewModel — volumes")
@MainActor
struct SpaceAnalyzerVolumeTests {
    @Test func loadsVolumesAndSelectsTheStartupDisk() async {
        let model = SpaceAnalyzerViewModel(volumes: PreviewVolumeRepository(), scanner: PreviewScanner())
        await model.observeVolumes()  // the preview stream ends at once
        #expect(model.volumes.count == 2)
        #expect(model.selectedVolume?.kind == .startup)
        #expect(model.hasLoadedVolumes)
        model.selectedVolumeID = PreviewVolumeRepository.external.id
        #expect(model.selectedVolume?.name == "Backup")
    }

    @Test func failureIsReported() async {
        let model = SpaceAnalyzerViewModel(volumes: FailingVolumes(), scanner: PreviewScanner())
        await model.loadVolumes()
        #expect(model.volumeError != nil)
        #expect(model.volumes.isEmpty)
        #expect(model.hasLoadedVolumes)
    }

    @Test func chartSegmentsShowPurgeableOnceAndAddUpToCapacity() throws {
        let volume = PreviewVolumeRepository.startup
        let segments = try #require(VolumePresentation.segments(volume))
        #expect(segments.map(\.bytes).reduce(0, +) == volume.totalBytes.value)
        #expect(segments[1].bytes == 38_000_000_000)  // important-usage minus available
        #expect(segments[2].bytes == 120_000_000_000)
    }

    @Test func noChartWithoutCapacity() {
        let volume = VolumeInfo(
            id: "n", name: "Share", mountPath: "/Volumes/Share", kind: .network,
            totalBytes: .unavailable(.notSupportedOnThisMac), availableBytes: .unavailable(.notSupportedOnThisMac),
            availableForImportantUsageBytes: .unavailable(.notSupportedOnThisMac)
        )
        #expect(VolumePresentation.segments(volume) == nil)
    }
}

/// Records requests; returns the preview result.
private actor RecordingScanner: FileSystemScanning {
    private(set) var requests: [ScanRequest] = []
    nonisolated func scan(_ request: ScanRequest, progress: @escaping @Sendable (ScanProgress) -> Void) async -> ScanResult {
        await record(request)
        return PreviewScanner.result(root: request.rootPath)
    }
    private func record(_ request: ScanRequest) { requests.append(request) }
}

/// Runs until cancelled, then returns an incomplete result.
private struct SlowScanner: FileSystemScanning {
    func scan(_ request: ScanRequest, progress: @escaping @Sendable (ScanProgress) -> Void) async -> ScanResult {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let builder = ScanTreeBuilder(rootPath: request.rootPath)
        return builder.build(startedAt: Date(), finishedAt: Date(), isComplete: false)
    }
}

@Suite("SpaceAnalyzerViewModel — scanning")
@MainActor
struct SpaceAnalyzerScanTests {
    let home = "/Users/preview"

    func scanned() async -> SpaceAnalyzerViewModel {
        let model = SpaceAnalyzerViewModel(volumes: PreviewVolumeRepository(), scanner: PreviewScanner(), homePath: home)
        model.scanHomeFolder()
        await model.waitForScan()
        return model
    }

    @Test func scanningTheHomeFolderShowsTheTree() async throws {
        let model = await scanned()
        let result = try #require(model.result)
        #expect(result.rootPath == home)
        #expect(model.folderContents.first?.name == "Movies")  // biggest first
        #expect(model.breadcrumb.map(\.id) == [home])
    }

    @Test func drillDownAndBackUp() async throws {
        let model = await scanned()
        model.open(home + "/Library")
        model.open(home + "/Library/Caches")
        #expect(model.breadcrumb.map(\.name) == ["preview", "Library", "Caches"])
        #expect(model.folderContents.map(\.name) == ["com.example.browser"])
        model.goUp()
        #expect(model.currentFolder?.id == home + "/Library")
        model.open(home + "/Movies/Holiday 2025.mov")  // files don't open
        #expect(model.currentFolder?.id == home + "/Library")
    }

    @Test func largestFilesCanBeFiltered() async {
        let model = await scanned()
        #expect(model.largestFiles.count == 8)
        model.categoryFilter = .video
        #expect(model.largestFiles.map(\.name) == ["Holiday 2025.mov", "Interview.mp4"])
        model.categoryFilter = nil
        model.sizeFilter = .over1GB
        #expect(model.largestFiles.count == 3)
        model.fileSortOrder = [KeyPathComparator(\ScanNode.allocatedBytes, order: .forward)]
        #expect(model.largestFiles.map(\.allocatedBytes) == model.largestFiles.map(\.allocatedBytes).sorted())
    }

    @Test func summaryReportsSkippedAndRecoverable() async throws {
        let model = await scanned()
        #expect(model.skippedSummary == [SkipCount(reason: .protectedByPrivacy, count: 2)])
        #expect(model.skippedProtectedFolders.count == 2)
        let result = try #require(model.result)
        let expected: Int64 = 1_300_000_000 + 40_000_000 + 900_000_000  // caches + logs + Trash
        #expect(result.recoverableBytes.value == expected)
        #expect(!result.recoverableBytes.isMeasured)
    }

    @Test func pickedFoldersAreApprovedAndExclusionsPassed() async throws {
        let scanner = RecordingScanner()
        let model = SpaceAnalyzerViewModel(volumes: PreviewVolumeRepository(), scanner: scanner, homePath: home)
        model.addExclusion(home + "/Movies")
        model.scanPickedFolder(home + "/Downloads/")
        await model.waitForScan()
        let request = try #require(await scanner.requests.last)
        #expect(request.rootPath == home + "/Downloads")
        #expect(request.policy.approvedRoots.contains(home + "/Downloads"))
        #expect(request.policy.userExclusions == [home + "/Movies"])
        #expect(request.policy.decision(forFolder: home + "/Downloads/x") == .scan)
    }

    @Test func scanningTheVolumeUsesItsMountPoint() async throws {
        let scanner = RecordingScanner()
        let model = SpaceAnalyzerViewModel(volumes: PreviewVolumeRepository(), scanner: scanner, homePath: home)
        await model.loadVolumes()
        model.selectedVolumeID = PreviewVolumeRepository.external.id
        model.scanSelectedVolume()
        await model.waitForScan()
        #expect(await scanner.requests.last?.rootPath == "/Volumes/Backup")
    }

    @Test func stoppingKeepsAPartialResult() async {
        let model = SpaceAnalyzerViewModel(volumes: PreviewVolumeRepository(), scanner: SlowScanner(), homePath: home)
        model.scanHomeFolder()
        #expect(model.isScanning)
        model.cancelScan()
        await model.waitForScan()
        #expect(model.result?.isComplete == false)
        #expect(!model.isScanning)
    }
}

@Suite("SpaceAnalyzerViewModel — exclusions and history")
@MainActor
struct SpaceAnalyzerHistoryTests {
    let home = "/Users/preview"

    @Test func exclusionsAreSavedAndLoaded() {
        let store = InMemoryScanSettingsStore()
        let model = SpaceAnalyzerViewModel(volumes: PreviewVolumeRepository(), scanner: PreviewScanner(), settings: store, homePath: home)
        model.addExclusion(home + "/Movies/")
        model.addExclusion(home + "/Movies")
        model.addExclusion(home + "/Archive")
        #expect(store.loadExclusions() == [home + "/Archive", home + "/Movies"])
        model.removeExclusion(home + "/Archive")
        let reloaded = SpaceAnalyzerViewModel(volumes: PreviewVolumeRepository(), scanner: PreviewScanner(), settings: store, homePath: home)
        #expect(reloaded.exclusions == [home + "/Movies"])
    }

    @Test func finishedScansAreRecordedWithTheChangeSinceLastTime() async throws {
        let history = InMemoryScanHistory()
        let model = SpaceAnalyzerViewModel(volumes: PreviewVolumeRepository(), scanner: PreviewScanner(), history: history, homePath: home)
        model.scanHomeFolder()
        await model.waitForScan()
        #expect(model.history.count == 1)
        let first = try #require(model.history.first)
        #expect(first.rootPath == home)
        #expect(first.topFolders.first?.name == "Movies")
        #expect(model.change(for: first) == nil)  // nothing to compare with yet
    }
}
