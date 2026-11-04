import Foundation

/// Where a folder picked for cleaning really is.
public enum PickResolution: Equatable, Sendable {
    /// The folder's real path, with symbolic links resolved.
    case resolved(String)
    /// A path under `/Volumes` that leads back to the startup disk.
    case startupDisk
    /// The folder doesn't exist or can't be read.
    case unreadable

    /// Resolves links with `realpath` and refuses `/Volumes/…` paths on the startup
    /// disk's volumes (its System and Data volumes), whose rules are written for the
    /// real paths.
    public static func resolve(_ path: String) -> PickResolution {
        guard let pointer = realpath(path, nil) else { return .unreadable }
        defer { free(pointer) }
        let real = String(cString: pointer)
        if real.lowercased().hasPrefix("/volumes/") {
            var pick = stat()
            guard stat(real, &pick) == 0 else { return .unreadable }
            let startup = ["/", "/System/Volumes/Data", NSHomeDirectory()].compactMap { folder -> dev_t? in
                var info = stat()
                return stat(folder, &info) == 0 ? info.st_dev : nil
            }
            if startup.contains(pick.st_dev) { return .startupDisk }
        }
        return .resolved(real)
    }
}
