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
        let model = SpaceAnalyzerViewModel(volumes: PreviewVolumeRepository())
        await model.observeVolumes()  // the preview stream ends at once
        #expect(model.volumes.count == 2)
        #expect(model.selectedVolume?.kind == .startup)
        #expect(model.hasLoadedVolumes)
        model.selectedVolumeID = PreviewVolumeRepository.external.id
        #expect(model.selectedVolume?.name == "Backup")
    }

    @Test func failureIsReported() async {
        let model = SpaceAnalyzerViewModel(volumes: FailingVolumes())
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
