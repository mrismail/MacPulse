import Foundation

/// Assigns a category from a file's path and extension. Never reads the file.
public enum FileCategorizer {
    public static func category(forPath path: String, isPackage: Bool = false) -> FileCategory {
        if let byLocation = category(forLocation: path) { return byLocation }
        let ext = (path as NSString).pathExtension.lowercased()
        if isPackage, ext == "app" { return .applications }
        return extensions[ext] ?? .other
    }

    /// Location rules win over the extension: a PNG in a cache folder is cache.
    static func category(forLocation path: String) -> FileCategory? {
        if path.contains("/.Trash/") || path.contains("/.Trashes/") { return .trash }
        if path.contains("/Library/Caches/") || (path.contains("/private/var/folders/") && path.contains("/C/")) {
            return .caches
        }
        if path.contains("/Library/Developer/Xcode/DerivedData/")
            || path.contains("/Library/Developer/CoreSimulator/Caches/") {
            return .caches
        }
        if path.contains("/Library/Logs/") || path.hasPrefix("/private/var/log/") || path.hasPrefix("/Library/Logs/") {
            return .logs
        }
        if path.hasPrefix("/private/tmp/") || path.hasPrefix("/tmp/")
            || (path.contains("/private/var/folders/") && path.contains("/T/")) {
            return .temporary
        }
        if path.hasPrefix("/Applications/") && path.contains(".app/") { return .applications }
        return nil
    }

    static let extensions: [String: FileCategory] = {
        var map: [String: FileCategory] = [:]
        func add(_ category: FileCategory, _ list: [String]) {
            for ext in list { map[ext] = category }
        }
        add(.applications, ["app", "appex", "pkg", "mpkg"])
        add(.documents, [
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf",
            "md", "csv", "odt", "ods", "odp", "epub", "html", "htm", "json", "xml",
        ])
        add(.images, [
            "jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "raw", "cr2",
            "cr3", "nef", "arw", "dng", "psd", "svg", "ai", "sketch", "fig",
        ])
        add(.video, ["mov", "mp4", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg", "3gp", "braw", "mxf"])
        add(.audio, ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "alac", "caf", "logicx", "band"])
        add(.archives, ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg", "iso", "sparseimage", "sparsebundle", "img"])
        add(.developer, [
            "swift", "m", "h", "c", "cc", "cpp", "java", "kt", "py", "js", "ts", "go", "rs", "rb", "o",
            "a", "dylib", "framework", "xcarchive", "ipa", "jar", "class", "pyc", "wasm",
        ])
        add(.logs, ["log", "crash", "ips", "diag"])
        add(.temporary, ["tmp", "temp", "part", "crdownload", "download"])
        return map
    }()
}
