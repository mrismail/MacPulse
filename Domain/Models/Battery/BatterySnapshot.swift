import Foundation

/// One stored history sample. Plain values (not `Metric`) because this is what is
/// persisted; only measured charge is recorded, never an estimate of it.
///
/// `percentage` and `healthPercentage` are on a 0–100 scale.
public struct BatterySnapshot: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let percentage: Double?
    public let isCharging: Bool?
    public let isPluggedIn: Bool?
    public let healthPercentage: Double?
    public let cycleCount: Int?
    public let estimatedRuntimeMinutes: Int?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        percentage: Double?,
        isCharging: Bool?,
        isPluggedIn: Bool?,
        healthPercentage: Double? = nil,
        cycleCount: Int? = nil,
        estimatedRuntimeMinutes: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.percentage = percentage
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.healthPercentage = healthPercentage
        self.cycleCount = cycleCount
        self.estimatedRuntimeMinutes = estimatedRuntimeMinutes
    }

    public init(reading: BatteryReading, estimatedRuntimeMinutes: Int?) {
        self.init(
            timestamp: reading.timestamp,
            percentage: reading.charge.isMeasured ? reading.charge.value : nil,
            isCharging: reading.isCharging,
            isPluggedIn: reading.isOnExternalPower,
            healthPercentage: reading.healthPercentage.value,
            cycleCount: reading.cycleCount.value,
            estimatedRuntimeMinutes: estimatedRuntimeMinutes
        )
    }
}
