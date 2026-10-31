import Foundation
import MacPulseDomain
import MacPulseShared

/// Battery history stored as one JSON object per line, one file per UTC day
/// (`battery-2026-10-31.jsonl`). See ADR-004.
///
/// - Appends are a single small write, so sampling stays cheap.
/// - Retention is enforced by removing whole day files.
/// - Files are created with owner-only permissions (0600) inside the app's sandbox container.
/// - Unreadable lines are skipped rather than failing the whole read.
public actor JSONLinesBatteryHistoryStore: BatteryHistoryRepository {
    public static let filePrefix = "battery-"
    public static let fileExtension = "jsonl"

    private let directory: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let calendar: Calendar

    public init(directory: URL) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        calendar = utc
    }

    /// `~/Library/Containers/com.mrismail.MacPulse/Data/Library/Application Support/MacPulse/History/Battery`
    /// when sandboxed.
    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base
            .appendingPathComponent("MacPulse", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("Battery", isDirectory: true)
    }

    // MARK: BatteryHistoryRepository

    public func append(_ snapshot: BatterySnapshot) throws {
        try ensureDirectory()
        var line = try encoder.encode(snapshot)
        line.append(0x0A)  // "\n"

        let url = fileURL(for: snapshot.timestamp)
        if !fileManager.fileExists(atPath: url.path) {
            guard fileManager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    public func snapshots(from: Date, to: Date) throws -> [BatterySnapshot] {
        guard from <= to else { return [] }
        let firstDay = dayString(for: from)
        let lastDay = dayString(for: to)
        var result: [BatterySnapshot] = []
        for (day, url) in try dayFiles() where day >= firstDay && day <= lastDay {
            let data = try Data(contentsOf: url)
            for line in data.split(separator: 0x0A) where !line.isEmpty {
                guard let snapshot = try? decoder.decode(BatterySnapshot.self, from: Data(line)) else {
                    Log.logger(.persistence).notice("Skipped an unreadable battery history line")
                    continue
                }
                if snapshot.timestamp >= from && snapshot.timestamp <= to {
                    result.append(snapshot)
                }
            }
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    public func prune(olderThan date: Date) throws {
        let cutoffDay = dayString(for: date)
        for (day, url) in try dayFiles() where day < cutoffDay {
            try fileManager.removeItem(at: url)
        }
    }

    public func deleteAll() throws {
        for (_, url) in try dayFiles() {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: Files

    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    func fileURL(for date: Date) -> URL {
        directory.appendingPathComponent("\(Self.filePrefix)\(dayString(for: date)).\(Self.fileExtension)")
    }

    func dayString(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Day files in the directory as (yyyy-MM-dd, url), sorted by day. Other files are ignored.
    private func dayFiles() throws -> [(day: String, url: URL)] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .compactMap { url -> (day: String, url: URL)? in
                let name = url.deletingPathExtension().lastPathComponent
                guard url.pathExtension == Self.fileExtension, name.hasPrefix(Self.filePrefix) else { return nil }
                let day = String(name.dropFirst(Self.filePrefix.count))
                guard day.count == 10 else { return nil }
                return (day, url)
            }
            .sorted { $0.day < $1.day }
    }
}
