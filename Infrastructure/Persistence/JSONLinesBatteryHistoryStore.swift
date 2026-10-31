import Foundation
import MacPulseDomain
import MacPulseShared

/// Battery history stored as one JSON object per line, one file per UTC day
/// (`battery-2026-10-31.jsonl`). See ADR-004.
///
/// - Appends are a single small write, so sampling stays cheap.
/// - Retention is enforced by removing whole day files.
/// - Files are created with owner-only permissions (0600) in the user's Application Support.
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

    /// `~/Library/Application Support/MacPulse/History/Battery`.
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
        // If a previous write was interrupted (crash, power loss), the file may end
        // mid-line. Start on a fresh line so only the damaged record is lost.
        if try endsWithoutNewline(url) {
            line.insert(0x0A, at: line.startIndex)
        }
        // O_APPEND makes each write land at the current end of file even if another
        // instance appends too; O_CREAT with 0600 creates the file atomically without
        // a separate exists/create race.
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: line)
    }

    private func endsWithoutNewline(_ url: URL) throws -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size > 0 else { return false }
        try handle.seek(toOffset: size - 1)
        return try handle.read(upToCount: 1) != Data([0x0A])
    }

    public func snapshots(from: Date, to: Date) throws -> [BatterySnapshot] {
        guard from <= to else { return [] }
        let firstDay = dayString(for: from)
        let lastDay = dayString(for: to)
        var result: [BatterySnapshot] = []
        var skipped = 0
        for (day, url) in try dayFiles() where day >= firstDay && day <= lastDay {
            let data = try Data(contentsOf: url)
            for line in data.split(separator: 0x0A) where !line.isEmpty {
                guard let snapshot = try? decoder.decode(BatterySnapshot.self, from: Data(line)) else {
                    skipped += 1
                    continue
                }
                if snapshot.timestamp >= from && snapshot.timestamp <= to {
                    result.append(snapshot)
                }
            }
        }
        if skipped > 0 {
            Log.logger(.persistence).notice("Skipped \(skipped, privacy: .public) unreadable battery history lines")
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    public func prune(olderThan date: Date) throws {
        let cutoffDay = dayString(for: date)
        try removeFiles(try dayFiles().filter { $0.day < cutoffDay }.map(\.url))
    }

    public func deleteAll() throws {
        try removeFiles(try dayFiles().map(\.url))
    }

    /// Removes every file it can, then rethrows the first failure, so one stuck file
    /// doesn't keep the rest of the user's history around.
    private func removeFiles(_ urls: [URL]) throws {
        var firstError: (any Error)?
        for url in urls {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
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
