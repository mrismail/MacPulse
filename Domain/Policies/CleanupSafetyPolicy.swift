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

    /// Where a picked folder may be. Picking a folder allows the items inside it, so a pick
    /// must never be a system location, the home folder, a standard folder or a volume root.
    /// - Parameter allowsStandardFolders: `true` for searches that never move the folder's
    ///   direct contents as a whole (Empty Folders): the standard folders themselves stay
    ///   refused by `verdict(for:)`, so only empty folders inside them can be listed.
    public func verdict(forPick folder: String, allowsStandardFolders: Bool = false) -> Verdict {
        let path = ScanPathPolicy.comparable(folder)
        let home = ScanPathPolicy.comparable(homePath)
        let refusedExactly = ["/", "/applications", "/library", "/system", "/users", "/volumes", "/private", "/usr",
                              "/opt", "/bin", "/sbin", "/cores", "/etc", "/var", "/tmp", home]
        if refusedExactly.contains(path) {
            return .refused(String(localized: "Choose a folder inside your home folder or on an external drive, not a system location or your whole home folder."))
        }
        if let standard = Self.standardHomeFolders.first(where: { path == home + "/" + $0.lowercased() }),
           path != home + "/downloads", !allowsStandardFolders {
            return .refused(String(localized: "“\(standard)” is a standard folder of your account. Choose a folder inside it instead."))
        }
        let components = path.split(separator: "/")
        if path.hasPrefix("/volumes/") {
            // An external drive: any folder on it except the drive itself.
            guard components.count >= 3 else { return .refused(String(localized: "Choose a folder on the drive, not the whole drive.")) }
            return components.dropFirst(2).contains(where: { $0.hasPrefix(".") })
                ? .refused(String(localized: "Hidden folders can't be chosen."))
                : .allowed
        }
        guard ScanPathPolicy.path(path, isInside: home) else {
            return .refused(String(localized: "Choose a folder inside your home folder or on an external drive."))
        }
        if ScanPathPolicy.path(path, isInside: home + "/library") {
            return .refused(String(localized: "App data in your Library folder can't be chosen."))
        }
        if components.dropFirst(home.split(separator: "/").count).contains(where: { $0.hasPrefix(".") }) {
            return .refused(String(localized: "Hidden folders can't be chosen."))
        }
        return .allowed
    }

    public func verdict(for path: String) -> Verdict {
        // Compared case-insensitively (APFS is case-insensitive by default) after
        // normalizing `..` and the Data-volume prefix.
        let path = ScanPathPolicy.comparable(path)
        let home = ScanPathPolicy.comparable(homePath)
        let appDataPath = appDataPath.map(ScanPathPolicy.comparable)
        let excludedFolders = excludedFolders.map(ScanPathPolicy.comparable)
        let pickedFolders = pickedFolders.map(ScanPathPolicy.comparable).filter { verdict(forPick: $0) == .allowed }
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
        if Self.standardHomeFolders.contains(where: { path == home + "/" + $0.lowercased() }) {
            return .refused(String(localized: "A standard folder of your account"))
        }
        // Hidden items (".ssh", ".config", …) hold settings and keys, never clutter.
        let base = inHome ? home : (pickedFolders.first { ScanPathPolicy.path(path, isInside: $0) } ?? home)
        let relative = path.split(separator: "/").dropFirst(base.split(separator: "/").count)
        if relative.contains(where: { $0.hasPrefix(".") }) {
            return .refused(String(localized: "A hidden item"))
        }
        if inHome, ScanPathPolicy.path(path, isInside: home + "/library") {
            let cleanable = Self.cleanableLibraryFolders.map { home + "/" + $0.lowercased() }
            guard let root = cleanable.first(where: { ScanPathPolicy.path(path, isInside: $0) }), path != root else {
                return .refused(String(localized: "App data in your Library folder"))
            }
            // Apple's own caches and logs belong to macOS.
            let first = String(path.dropFirst(root.count + 1).split(separator: "/").first ?? "")
            if first.hasPrefix("com.apple.") || first == "cloudkit" || first == "familycircle" || first == "diagnosticreports" {
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
