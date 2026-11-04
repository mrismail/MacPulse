import Foundation
import MacPulseDomain
import MacPulseShared

/// Cleanup reports in daily JSON-lines files (`cleanup-YYYY-MM-DD.jsonl`), owner-only,
/// kept 30 days. They hold original and Trash paths so items can be found and put back;
/// they never leave this Mac and paths are never logged.
public actor JSONLinesCleanupHistoryStore: CleanupHistoryRepository {
    public static let retentionDays = 30

    private let files: DailyJSONLinesFiles
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let now: @Sendable () -> Date

    public init(directory: URL, now: @escaping @Sendable () -> Date = Date.init) {
        files = DailyJSONLinesFiles(directory: directory, prefix: "cleanup-")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
        self.now = now
    }

    public static func defaultDirectory() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MacPulse", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("Cleanup", isDirectory: true)
    }

    public func append(_ report: CleanupReport) throws {
        try files.append(lines: [try encoder.encode(report)], toDay: files.dayString(for: report.finishedAt))
        // The report is stored; a failed retention clean-up must not make the caller think
        // it wasn't (and write it twice).
        let cutoff = now().addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        do {
            try files.removeDays(before: files.dayString(for: cutoff))
        } catch {
            Log.logger(.persistence).log(AppError.wrapping(error, userMessage: String(localized: "Couldn't remove old cleanup history.")), context: "Cleanup history retention")
        }
    }

    /// Rewrites the day file holding `report` with the new version.
    public func replace(_ report: CleanupReport) throws {
        let day = files.dayString(for: report.finishedAt)
        let lines = try files.lines(fromDay: day, toDay: day)
        var found = false
        let updated = try lines.map { line -> Data in
            guard let stored = try? decoder.decode(CleanupReport.self, from: line), stored.id == report.id else { return line }
            found = true
            return try encoder.encode(report)
        }
        guard found else { throw CleanupHistoryError.reportNotFound }
        try files.replace(day: day, with: updated)
    }

    public func deleteAll() throws {
        try files.removeAll()
    }

    public func reports() throws -> [CleanupReport] {
        let days = try files.days()
        guard let first = days.first, let last = days.last else { return [] }
        var skipped = 0
        let reports = try files.lines(fromDay: first, toDay: last).compactMap { line -> CleanupReport? in
            if let report = try? decoder.decode(CleanupReport.self, from: line) { return report }
            skipped += 1
            return nil
        }
        if skipped > 0 {
            Log.logger(.persistence).notice("Skipped \(skipped, privacy: .public) unreadable cleanup history lines")
        }
        return reports
    }
}
