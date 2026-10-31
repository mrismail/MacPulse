import Foundation
import MacPulseDomain
import MacPulseShared

/// Hourly app usage records, one JSON object per line, one file per UTC day
/// (`usage-YYYY-MM-DD.jsonl`) in `~/Library/Application Support/MacPulse/History/Usage`.
///
/// Stores app bundle paths and display names (needed to show trends), never process
/// arguments, file names or window titles.
public actor JSONLinesAppUsageStore: AppUsageHistoryRepository {
    private let files: DailyJSONLinesFiles
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        files = DailyJSONLinesFiles(directory: directory, prefix: "usage-")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
    }

    public static func defaultDirectory() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MacPulse", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("Usage", isDirectory: true)
    }

    public func append(_ records: [AppUsageRecord]) throws {
        let byDay = Dictionary(grouping: records) { files.dayString(for: $0.hourStart) }
        for (day, dayRecords) in byDay {
            try files.append(lines: try dayRecords.map { try encoder.encode($0) }, toDay: day)
        }
    }

    public func records(from: Date, to: Date) throws -> [AppUsageRecord] {
        guard from <= to else { return [] }
        let lines = try files.lines(fromDay: files.dayString(for: from), toDay: files.dayString(for: to))
        var skipped = 0
        let records = lines.compactMap { line -> AppUsageRecord? in
            guard let record = try? decoder.decode(AppUsageRecord.self, from: line) else {
                skipped += 1
                return nil
            }
            return record
        }
        if skipped > 0 {
            Log.logger(.persistence).notice("Skipped \(skipped, privacy: .public) unreadable usage history lines")
        }
        return records
            .filter { $0.hourStart >= from && $0.hourStart <= to }
            .sorted { $0.hourStart < $1.hourStart }
    }

    public func prune(olderThan date: Date) throws {
        try files.removeDays(before: files.dayString(for: date))
    }

    public func deleteAll() throws {
        try files.removeAll()
    }
}
