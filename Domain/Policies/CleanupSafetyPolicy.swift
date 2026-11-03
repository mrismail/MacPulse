import Foundation

/// Decides whether the Cleaner may ever move an item. Applied when candidates are listed
/// and again immediately before each item is moved.
public struct CleanupSafetyPolicy: Sendable, Equatable {
    public enum Verdict: Sendable, Equatable {
        case allowed
        case refused(String)
    }

    public let homePath: String
    /// Folders the user picked (e.g. a Downloads folder or a folder to tidy); items inside
    /// them are allowed, the folders themselves are not.
    public var pickedFolders: [String]
    /// MacPulse's own data (Application Support/MacPulse), never offered.
    public var appDataPath: String?
    /// Folders the user excluded from scans; the Cleaner never touches anything in them
    /// either (one set of exclusions for every module).
    public var excludedFolders: [String]

    public init(homePath: String, pickedFolders: [String] = [], appDataPath: String? = nil, excludedFolders: [String] = []) {
        self.homePath = ScanPathPolicy.normalized(homePath)
        self.pickedFolders = pickedFolders.map(ScanPathPolicy.normalized)
        self.appDataPath = appDataPath.map(ScanPathPolicy.normalized)
        self.excludedFolders = excludedFolders.map(ScanPathPolicy.normalized)
    }

    /// Folders in the home folder that are never removed themselves.
    public static let standardHomeFolders = [
        "Desktop", "Documents", "Downloads", "Library", "Pictures", "Movies", "Music",
        "Applications", "Public", "Sites", ".Trash",
    ]

    /// Parts of `~/Library` the Cleaner may touch. Everything else there is app data.
    public static let cleanableLibraryFolders = ["Library/Caches", "Library/Logs"]

    public func verdict(for path: String) -> Verdict {
        let path = ScanPathPolicy.normalized(path)
        let home = homePath
        if let appDataPath, ScanPathPolicy.path(path, isInside: appDataPath) {
            return .refused(String(localized: "MacPulse's own data"))
        }
        if excludedFolders.contains(where: { ScanPathPolicy.path(path, isInside: $0) }) {
            return .refused(String(localized: "In a folder you excluded"))
        }
        let inHome = ScanPathPolicy.path(path, isInside: home)
        let inPicked = pickedFolders.contains { ScanPathPolicy.path(path, isInside: $0) && path != $0 }
        guard inHome || inPicked else {
            return .refused(String(localized: "Outside your home folder"))
        }
        if path == home || pickedFolders.contains(path) {
            return .refused(String(localized: "A folder you chose to clean, not an item in it"))
        }
        if Self.standardHomeFolders.contains(where: { path == home + "/" + $0 }) {
            return .refused(String(localized: "A standard folder of your account"))
        }
        if inHome, ScanPathPolicy.path(path, isInside: home + "/Library") {
            let cleanable = Self.cleanableLibraryFolders.map { home + "/" + $0 }
            guard let root = cleanable.first(where: { ScanPathPolicy.path(path, isInside: $0) }), path != root else {
                return .refused(String(localized: "App data in your Library folder"))
            }
            // Apple's own caches and logs belong to macOS.
            let first = String(path.dropFirst(root.count + 1).split(separator: "/").first ?? "")
            if first.hasPrefix("com.apple.") || first == "CloudKit" || first == "FamilyCircle" {
                return .refused(String(localized: "Used by macOS"))
            }
        }
        let ext = (path as NSString).pathExtension.lowercased()
        if ["photoslibrary", "musiclibrary", "tvlibrary", "photolibrary"].contains(ext) {
            return .refused(String(localized: "A media library; manage it in its app"))
        }
        if Self.isInsidePackage(path) {
            return .refused(String(localized: "Part of an app or another package"))
        }
        return .allowed
    }

    /// `true` for paths inside a bundle such as `X.app/Contents/...`.
    static func isInsidePackage(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        let packageExtensions = ["app", "bundle", "framework", "plugin", "kext", "photoslibrary", "musiclibrary", "tvlibrary"]
        return components.dropLast().contains { component in
            packageExtensions.contains((component as Substring).split(separator: ".").last.map(String.init)?.lowercased() ?? "")
                && component.contains(".")
        }
    }
}
