import Foundation

/// History kept in memory only. Used in tests, previews, and as a fallback when the
/// on-disk store cannot be created.
public actor InMemoryBatteryHistoryRepository: BatteryHistoryRepository {
    private var storage: [BatterySnapshot]

    public init(_ snapshots: [BatterySnapshot] = []) {
        storage = snapshots
    }

    public func append(_ snapshot: BatterySnapshot) {
        storage.append(snapshot)
    }

    public func snapshots(from: Date, to: Date) -> [BatterySnapshot] {
        storage
            .filter { $0.timestamp >= from && $0.timestamp <= to }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func prune(olderThan date: Date) {
        storage.removeAll { $0.timestamp < date }
    }

    public func deleteAll() {
        storage.removeAll()
    }

    public var count: Int { storage.count }
}
