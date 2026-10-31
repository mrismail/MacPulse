import Foundation

/// The latest battery reading plus MacPulse's own estimates derived from history.
public struct BatteryStatus: Sendable, Equatable {
    public let reading: BatteryReading
    /// MacPulse's runtime estimate from the recent discharge rate.
    public let runtimeFromRecentDischarge: Metric<Int>
    /// Average charge lost per hour over the recent discharge window (0–100 scale).
    public let dischargeRatePercentPerHour: Metric<Double>
    /// Set when battery history could not be read or saved, so the UI can say so
    /// instead of silently losing data.
    public let historyIssue: AppError?

    public init(
        reading: BatteryReading,
        runtimeFromRecentDischarge: Metric<Int>,
        dischargeRatePercentPerHour: Metric<Double>,
        historyIssue: AppError? = nil
    ) {
        self.reading = reading
        self.runtimeFromRecentDischarge = runtimeFromRecentDischarge
        self.dischargeRatePercentPerHour = dischargeRatePercentPerHour
        self.historyIssue = historyIssue
    }

    /// The single runtime figure shown everywhere as "Estimated runtime": MacPulse's own
    /// estimate when it has enough data, otherwise macOS's. Its provenance basis says which.
    public var bestRuntimeEstimate: Metric<Int> {
        runtimeFromRecentDischarge.isAvailable ? runtimeFromRecentDischarge : reading.systemTimeToEmptyMinutes
    }
}
