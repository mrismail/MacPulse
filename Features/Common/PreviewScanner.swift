import Foundation
import MacPulseDomain

#if DEBUG
/// A deterministic scan for previews and UI tests: a small home folder with a video
/// library, a cache and a protected folder that was skipped. Never touches the disk.
public struct PreviewScanner: FileSystemScanning {
    public init() {}

    public func scan(_ request: ScanRequest, progress: @escaping @Sendable (ScanProgress) -> Void) async -> ScanResult {
        let root = request.rootPath
        progress(ScanProgress(itemsScanned: 3, allocatedBytes: 1_000, currentFolder: root))
        return Self.result(root: root)
    }

    public static func result(root: String, date: Date = Date(timeIntervalSince1970: 1_793_448_000)) -> ScanResult {
        var builder = ScanTreeBuilder(rootPath: root)
        func add(_ relative: String, _ bytes: Int64, _ category: FileCategory, package: Bool = false) {
            let path = root + "/" + relative
            builder.add(ScannedFile(
                path: path, parentPath: (path as NSString).deletingLastPathComponent,
                logicalBytes: bytes, allocatedBytes: bytes, category: category, modified: date, isPackage: package
            ))
        }
        add("Movies/Holiday 2025.mov", 8_400_000_000, .video)
        add("Movies/Interview.mp4", 2_100_000_000, .video)
        add("Music/Library/Album.m4a", 95_000_000, .audio)
        add("Library/Caches/com.example.browser/cache.db", 1_300_000_000, .caches)
        add("Library/Logs/app.log", 40_000_000, .logs)
        add("Pictures/Scans/receipt.pdf", 2_500_000, .documents)
        add("Applications/Editor.app", 650_000_000, .applications, package: true)
        add(".Trash/old-installer.dmg", 900_000_000, .trash)
        builder.skip(SkippedLocation(path: root + "/Documents", reason: .protectedByPrivacy))
        builder.skip(SkippedLocation(path: root + "/Downloads", reason: .protectedByPrivacy))
        return builder.build(startedAt: date, finishedAt: date.addingTimeInterval(4), isComplete: true)
    }
}
#endif
