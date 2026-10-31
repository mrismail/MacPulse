import Darwin
import Foundation

/// Reusable storage for JSON-lines records in one file per UTC day
/// (`<prefix>YYYY-MM-DD.jsonl`), with the same safety rules as the battery history
/// (ADR-004): owner-only permissions, crash-safe appends, corrupt lines skipped.
///
/// Not thread-safe by itself; owned by an actor.
struct DailyJSONLinesFiles {
    let directory: URL
    let prefix: String
    private let fileManager = FileManager.default
    private let calendar: Calendar

    init(directory: URL, prefix: String) {
        self.directory = directory
        self.prefix = prefix
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        calendar = utc
    }

    func dayString(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func fileURL(forDay day: String) -> URL {
        directory.appendingPathComponent("\(prefix)\(day).jsonl")
    }

    /// Appends complete lines to the file for `day`.
    func append(lines: [Data], toDay day: String) throws {
        guard !lines.isEmpty else { return }
        try ensureDirectory()
        let url = fileURL(forDay: day)
        var payload = Data()
        if try endsWithoutNewline(url) {
            payload.append(0x0A)
        }
        for line in lines {
            payload.append(line)
            payload.append(0x0A)
        }
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: payload)
    }

    /// Non-empty lines from every day file between the two days, inclusive.
    func lines(fromDay first: String, toDay last: String) throws -> [Data] {
        var result: [Data] = []
        for (day, url) in try dayFiles() where day >= first && day <= last {
            let data = try Data(contentsOf: url)
            result += data.split(separator: 0x0A).filter { !$0.isEmpty }.map { Data($0) }
        }
        return result
    }

    func removeDays(before day: String) throws {
        try remove(try dayFiles().filter { $0.day < day }.map(\.url))
    }

    func removeAll() throws {
        try remove(try dayFiles().map(\.url))
    }

    // MARK: Private

    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
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

    private func dayFiles() throws -> [(day: String, url: URL)] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return urls
            .compactMap { url -> (day: String, url: URL)? in
                let name = url.deletingPathExtension().lastPathComponent
                guard url.pathExtension == "jsonl", name.hasPrefix(prefix) else { return nil }
                let day = String(name.dropFirst(prefix.count))
                return day.count == 10 ? (day, url) : nil
            }
            .sorted { $0.day < $1.day }
    }

    private func remove(_ urls: [URL]) throws {
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
}
