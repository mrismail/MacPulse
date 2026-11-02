import AppKit
import Foundation
import MacPulseDomain

/// Mounted volumes from `FileManager.mountedVolumeURLs` with capacity from
/// `URLResourceValues`. Read-only; never mounts, unmounts or ejects anything.
public struct LiveVolumeRepository: VolumeRepository {
    static let keys: [URLResourceKey] = [
        .volumeLocalizedNameKey,
        .volumeUUIDStringKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsInternalKey,
        .volumeIsLocalKey,
        .volumeIsRootFileSystemKey,
        .volumeIsReadOnlyKey,
        .volumeIsEjectableKey,
        .volumeIsBrowsableKey,
        .volumeLocalizedFormatDescriptionKey,
    ]

    public init() {}

    public func volumes() async throws -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Self.keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.compactMap(Self.volume(at:)).sorted(by: Self.startupFirst)
    }

    static func volume(at url: URL) -> VolumeInfo? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        if values.volumeIsBrowsable == false { return nil }
        let isRoot = values.volumeIsRootFileSystem ?? (url.path == "/")
        let kind: VolumeKind
        if isRoot {
            kind = .startup
        } else if values.volumeIsLocal == false {
            kind = .network
        } else if values.volumeIsInternal == true {
            kind = .internal
        } else {
            kind = .external
        }
        func bytes(_ value: Int?) -> Metric<Int64> {
            value.map { .measured(Int64($0)) } ?? .unavailable(.notSupportedOnThisMac)
        }
        return VolumeInfo(
            id: values.volumeUUIDString ?? url.path,
            name: values.volumeLocalizedName ?? url.lastPathComponent,
            mountPath: url.path,
            kind: kind,
            fileSystem: values.volumeLocalizedFormatDescription,
            isReadOnly: values.volumeIsReadOnly ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            totalBytes: bytes(values.volumeTotalCapacity),
            availableBytes: bytes(values.volumeAvailableCapacity),
            availableForImportantUsageBytes: values.volumeAvailableCapacityForImportantUsage
                .map { .measured($0) } ?? .unavailable(.notSupportedOnThisMac)
        )
    }

    static func startupFirst(_ lhs: VolumeInfo, _ rhs: VolumeInfo) -> Bool {
        if (lhs.kind == .startup) != (rhs.kind == .startup) { return lhs.kind == .startup }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    public func changes() async -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observers = ObserverBox()
        await MainActor.run {
            let center = NSWorkspace.shared.notificationCenter
            let names = [
                NSWorkspace.didMountNotification,
                NSWorkspace.didUnmountNotification,
                NSWorkspace.didRenameVolumeNotification,
            ]
            for name in names {
                observers.add(center.addObserver(forName: name, object: nil, queue: nil) { _ in
                    continuation.yield(())
                })
            }
        }
        continuation.onTermination = { _ in
            Task { @MainActor in
                observers.removeAll(from: NSWorkspace.shared.notificationCenter)
            }
        }
        return stream
    }
}

/// Holds notification tokens so they can be removed when the stream ends.
private final class ObserverBox: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) {
        lock.withLock { tokens.append(token) }
    }

    func removeAll(from center: NotificationCenter) {
        let removed = lock.withLock { () -> [NSObjectProtocol] in
            defer { tokens.removeAll() }
            return tokens
        }
        for token in removed { center.removeObserver(token) }
    }
}
