import Foundation

/// What a file is, for the category breakdown. Decided from its path and extension only;
/// file contents are never read.
public enum FileCategory: String, CaseIterable, Sendable, Equatable, Codable, Identifiable {
    case applications
    case documents
    case images
    case video
    case audio
    case archives
    case developer
    case caches
    case logs
    case temporary
    case trash
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .applications: String(localized: "Applications")
        case .documents: String(localized: "Documents")
        case .images: String(localized: "Images")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .archives: String(localized: "Archives & disk images")
        case .developer: String(localized: "Developer")
        case .caches: String(localized: "Caches")
        case .logs: String(localized: "Logs")
        case .temporary: String(localized: "Temporary files")
        case .trash: String(localized: "Trash")
        case .other: String(localized: "Other")
        }
    }

    /// Categories whose files are usually safe to remove and that the Cleaner (Phase 6)
    /// will offer. Used for the "estimated recoverable" figure.
    public var isTypicallyRecoverable: Bool {
        switch self {
        case .caches, .logs, .temporary, .trash: true
        default: false
        }
    }
}
