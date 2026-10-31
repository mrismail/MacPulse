import Foundation

/// Usage history kept in memory only: fallback when the on-disk store can't be created,
/// and for previews.
public actor InMemoryAppUsageHistory: AppUsageHistoryRepository {
    private var storage: [AppUsageRecord]

    public init(_ records: [AppUsageRecord] = []) {
        storage = records
    }

    public func append(_ records: [AppUsageRecord]) {
        storage += records
    }

    public func records(from: Date, to: Date) -> [AppUsageRecord] {
        storage.filter { $0.hourStart >= from && $0.hourStart <= to }.sorted { $0.hourStart < $1.hourStart }
    }

    public func prune(olderThan date: Date) {
        storage.removeAll { $0.hourStart < date }
    }

    public func deleteAll() {
        storage.removeAll()
    }
}
