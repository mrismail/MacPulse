import Foundation

/// Reads the current battery state. Never throws: failures are expressed as
/// unavailable metrics inside the reading.
public protocol BatteryReadingSource: Sendable {
    func currentReading(at timestamp: Date) async -> BatteryReading
}

/// Emits a value whenever macOS reports a power-source change (plug/unplug, charge change).
public protocol PowerSourceEventSource: Sendable {
    func events() -> AsyncStream<Void>
}

/// Stores battery history samples on this Mac.
public protocol BatteryHistoryRepository: Sendable {
    func append(_ snapshot: BatterySnapshot) async throws
    /// Samples with `from <= timestamp <= to`, oldest first.
    func snapshots(from: Date, to: Date) async throws -> [BatterySnapshot]
    /// Removes samples older than `date`.
    func prune(olderThan date: Date) async throws
    /// Removes all stored samples.
    func deleteAll() async throws
}

/// App-wide battery monitoring service used by the Battery screen, the Overview and Settings.
public protocol BatteryMonitoring: Sendable {
    /// Starts periodic sampling. Calling it again has no effect.
    func start() async
    /// Takes a sample immediately.
    func refresh() async
    /// The latest status (replayed immediately if known) and every subsequent update.
    func updates() async -> AsyncStream<BatteryStatus>
    func history(since date: Date) async throws -> [BatterySnapshot]
    func clearHistory() async throws
}
