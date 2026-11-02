import Foundation
import MacPulseDomain

#if DEBUG
/// Two deterministic volumes for previews and UI tests: the startup disk and an
/// external drive.
public struct PreviewVolumeRepository: VolumeRepository {
    public init() {}

    public static let startup = VolumeInfo(
        id: "preview-startup", name: "Macintosh HD", mountPath: "/", kind: .startup, fileSystem: "APFS",
        totalBytes: .measured(494_384_795_648),
        availableBytes: .measured(120_000_000_000),
        availableForImportantUsageBytes: .measured(158_000_000_000)
    )

    public static let external = VolumeInfo(
        id: "preview-external", name: "Backup", mountPath: "/Volumes/Backup", kind: .external,
        fileSystem: "APFS", isEjectable: true,
        totalBytes: .measured(2_000_000_000_000),
        availableBytes: .measured(1_400_000_000_000),
        availableForImportantUsageBytes: .measured(1_400_000_000_000)
    )

    public func volumes() async throws -> [VolumeInfo] { [Self.startup, Self.external] }

    public func changes() async -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
#endif
