import Foundation

/// Decides, before descending, whether the scanner may enter a folder.
///
/// Protected locations are those where macOS shows a privacy prompt (or that need Full
/// Disk Access). They are skipped unless they are inside a folder the user picked in the
/// folder panel (an `approvedRoots` entry), so a scan never surprises the user with a
/// prompt.
public struct ScanPathPolicy: Sendable, Equatable {
    public enum Decision: Sendable, Equatable {
        case scan
        case skip(SkipReason)
    }

    /// Folders the user excluded.
    public var userExclusions: [String]
    /// Folders the user picked in the folder panel; protected locations inside them are scanned.
    public var approvedRoots: [String]
    public let homePath: String

    public init(homePath: String, userExclusions: [String] = [], approvedRoots: [String] = []) {
        self.homePath = Self.normalized(homePath)
        self.userExclusions = userExclusions.map(Self.normalized)
        self.approvedRoots = approvedRoots.map(Self.normalized)
    }

    /// System locations never scanned: OS files, virtual memory, devices, indexes and
    /// Time Machine data. Sizes there aren't actionable and some are huge or virtual.
    public static let systemLocations: [String] = [
        "/System",
        "/dev",
        "/private/var/vm",
        "/private/var/db",
        "/Volumes",
        "/.Spotlight-V100",
        "/.fseventsd",
        "/.DocumentRevisions-V100",
        "/.MobileBackups",
        "/.Trashes",
        "/.vol",
        "/Network",
        "/cores",
    ]

    /// Home-relative locations where macOS asks for permission or that need Full Disk
    /// Access (macOS 14+).
    public static let protectedHomeLocations: [String] = [
        "Desktop",
        "Documents",
        "Downloads",
        "Library/Mobile Documents",  // iCloud Drive
        "Library/CloudStorage",      // File Provider (Dropbox, OneDrive, Google Drive)
        "Library/Containers",        // other apps' data
        "Library/Group Containers",
        "Library/Mail",
        "Library/Messages",
        "Library/Safari",
        "Library/Calendars",
        "Library/Reminders",
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/com.apple.TCC",
        "Library/Application Support/MobileSync",
        "Library/Cookies",
        "Library/HomeKit",
        "Library/IdentityServices",
        "Library/Metadata/CoreSpotlight",
        "Library/Suggestions",
        "Pictures/Photos Library.photoslibrary",
    ]

    public func decision(forFolder path: String) -> Decision {
        let path = Self.normalized(path)
        if userExclusions.contains(where: { Self.path(path, isInside: $0) }) {
            return .skip(.excludedByUser)
        }
        if let location = Self.systemLocations.first(where: { Self.path(path, isInside: $0) }),
           !isApproved(path, within: location) {
            return .skip(.systemLocation)
        }
        if let location = protectedLocation(containing: path), !isApproved(path, within: location) {
            return .skip(.protectedByPrivacy)
        }
        return .scan
    }

    /// The protected location containing `path`, if any.
    public func protectedLocation(containing path: String) -> String? {
        let path = Self.normalized(path)
        return Self.protectedHomeLocations
            .map { homePath + "/" + $0 }
            .first { Self.path(path, isInside: $0) }
    }

    /// `true` for a protected location or anything inside one.
    public func isProtected(_ path: String) -> Bool {
        protectedLocation(containing: path) != nil
    }

    /// Picking a folder approves what is inside it, but only as deep as the pick:
    /// approving `/` (or the home folder) does not approve Documents. The approved root
    /// must be inside the protected location itself.
    func isApproved(_ path: String, within location: String) -> Bool {
        approvedRoots.contains { root in
            Self.path(path, isInside: root) && Self.path(root, isInside: location)
        }
    }

    /// `true` when `path` equals `folder` or is inside it (component-wise, so
    /// `/a/bc` is not inside `/a/b`).
    public static func path(_ path: String, isInside folder: String) -> Bool {
        if folder == "/" { return path.hasPrefix("/") }
        return path == folder || path.hasPrefix(folder + "/")
    }

    /// Removes duplicate and trailing slashes and resolves `.` and `..`, without touching
    /// the filesystem (`standardizingPath` would strip `/private` when the result exists,
    /// so `/private/var/vm` and `/var/vm` would compare differently from run to run).
    public static func normalized(_ path: String) -> String {
        var components: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }
}
