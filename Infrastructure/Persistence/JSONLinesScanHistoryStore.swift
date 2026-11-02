import Foundation
import MacPulseDomain
import MacPulseShared

/// Scan summaries in daily JSON-lines files (`scans-YYYY-MM-DD.jsonl`) in
/// Application Support/MacPulse. Files are private to the user (0600).
public actor JSONLinesScanHistoryStore: ScanHistoryRepository {
    public static let retentionDays = 180

    private let files: DailyJSONLinesFiles
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let now: @Sendable () -> Date

    public init(directory: URL, now: @escaping @Sendable () -> Date = Date.init) {
        files = DailyJSONLinesFiles(directory: directory, prefix: "scans-")
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
            .appendingPathComponent("Scans", isDirectory: true)
    }

    public func append(_ summary: ScanSummary) throws {
        try files.append(lines: [try encoder.encode(summary)], toDay: files.dayString(for: summary.finishedAt))
        let cutoff = now().addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        try files.removeDays(before: files.dayString(for: cutoff))
    }

    public func summaries() throws -> [ScanSummary] {
        let days = try files.days()
        guard let first = days.first, let last = days.last else { return [] }
        var skipped = 0
        let summaries = try files.lines(fromDay: first, toDay: last).compactMap { line -> ScanSummary? in
            if let summary = try? decoder.decode(ScanSummary.self, from: line) { return summary }
            skipped += 1
            return nil
        }
        if skipped > 0 {
            Log.logger(.persistence).notice("Skipped \(skipped, privacy: .public) unreadable scan history lines")
        }
        return summaries
    }

    public func deleteAll() throws {
        try files.removeAll()
    }
}

/// Excluded folders in user defaults.
public final class UserDefaultsScanSettingsStore: ScanSettingsStore, @unchecked Sendable {
    static let exclusionsKey = "spaceAnalyzer.exclusions"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadExclusions() -> [String] {
        defaults.stringArray(forKey: Self.exclusionsKey) ?? []
    }

    public func saveExclusions(_ paths: [String]) {
        defaults.set(paths, forKey: Self.exclusionsKey)
    }
}
