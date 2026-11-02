import Foundation
import MacPulseDomain
import MacPulseShared
import Observation

@MainActor
@Observable
public final class SpaceAnalyzerViewModel {
    public private(set) var volumes: [VolumeInfo] = []
    public var selectedVolumeID: String?
    public private(set) var volumeError: AppError?
    public private(set) var hasLoadedVolumes = false

    @ObservationIgnored private let volumeRepository: any VolumeRepository

    public init(volumes: any VolumeRepository) {
        volumeRepository = volumes
    }

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
}
