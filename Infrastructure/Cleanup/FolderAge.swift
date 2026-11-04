import Foundation

/// How recently anything inside a folder changed.
enum FolderAge: Equatable {
    /// The newest modification date found (`nil` for an empty folder).
    case newest(Date?)
    /// Something inside changed at or after the cutoff.
    case changedSince
    /// Too many items to check, or some couldn't be read: never treated as old.
    case unknown

    static let itemLimit = 20_000

    /// Looks inside `folder` without following links, stopping as soon as something
    /// changed at or after `cutoff`.
    static func of(_ folder: String, cutoff: Date, itemLimit: Int = FolderAge.itemLimit) -> FolderAge {
        final class ErrorFlag: @unchecked Sendable { var hit = false }
        let flag = ErrorFlag()
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: folder, isDirectory: true),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [],
            errorHandler: { _, _ in
                flag.hit = true
                return false
            }
        ) else { return .unknown }
        var newest: Date?
        var seen = 0
        while let url = enumerator.nextObject() as? URL {
            seen += 1
            if seen > itemLimit { return .unknown }
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                return .unknown
            }
            if date >= cutoff { return .changedSince }
            if date > (newest ?? .distantPast) { newest = date }
        }
        return flag.hit ? .unknown : .newest(newest)
    }

    /// `true` when the folder and everything inside it is older than `cutoff`.
    static func isOld(_ folder: String, modified: Date?, cutoff: Date) -> Bool {
        guard let modified, modified < cutoff, case .newest = of(folder, cutoff: cutoff) else { return false }
        return true
    }
}
