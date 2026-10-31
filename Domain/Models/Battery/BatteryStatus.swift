import Foundation

/// The latest battery reading plus MacPulse's own estimates derived from history.
public struct BatteryStatus: Sendable, Equatable {
    public let reading: BatteryReading
    /// MacPulse's runtime estimate from the recent discharge rate.
    public let runtimeFromRecentDischarge: Metric<Int>
    /// Average charge lost per hour over the recent discharge window (0–100 scale).
    public let dischargeRatePercentPerHour: Metric<Double>

    public init(
        reading: BatteryReading,
        runtimeFromRecentDischarge: Metric<Int>,
        dischargeRatePercentPerHour: Metric<Double>
    ) {
        self.reading = reading
        self.runtimeFromRecentDischarge = runtimeFromRecentDischarge
        self.dischargeRatePercentPerHour = dischargeRatePercentPerHour
    }

    /// The runtime to show when only one figure fits: MacPulse's own estimate when it
    /// has enough data, otherwise macOS's.
    public var bestRuntimeEstimate: Metric<Int> {
        runtimeFromRecentDischarge.isAvailable ? runtimeFromRecentDischarge : reading.systemTimeToEmptyMinutes
    }
}
