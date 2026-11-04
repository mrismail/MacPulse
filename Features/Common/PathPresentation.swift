import Foundation
import MacPulseDomain

enum PathPresentation {
    /// `path` relative to `folder` when inside it ("Movies/Holiday.mov"), else the full path.
    static func relative(_ path: String, to folder: String) -> String {
        let folder = ScanPathPolicy.normalized(folder)
        let path = ScanPathPolicy.normalized(path)
        guard ScanPathPolicy.path(path, isInside: folder), path != folder else { return path }
        return String(path.dropFirst(folder.count + (folder.hasSuffix("/") ? 0 : 1)))
    }
}
