import Foundation

/// Whether the Mac is running from its battery or from external power.
public enum PowerSource: String, Sendable, Equatable, Codable {
    case battery
    case externalPower
}

/// What the battery is doing right now.
public enum ChargingState: String, Sendable, Equatable, Codable {
    case charging
    case discharging
    /// On external power but not charging (for example Optimized Battery Charging is holding the charge).
    case notCharging
    case fullyCharged
}

/// The battery condition macOS reports.
public enum BatteryCondition: Sendable, Equatable {
    case normal
    /// macOS recommends service. The associated text is what macOS reported.
    case serviceRecommended(String)
}

/// A complete, provenance-tagged view of the battery at one moment.
///
/// Percentages are on a 0–100 scale. Capacities are milliampere-hours.
public struct BatteryReading: Sendable, Equatable {
    public let timestamp: Date
    /// `false` on Macs without an internal battery. All metrics are then unavailable.
    public let hasBattery: Bool

    public let charge: Metric<Double>
    public let powerSource: Metric<PowerSource>
    public let chargingState: Metric<ChargingState>
    /// macOS's own time-to-empty estimate, in minutes.
    public let systemTimeToEmptyMinutes: Metric<Int>
    /// macOS's own time-to-full estimate, in minutes.
    public let systemTimeToFullMinutes: Metric<Int>

    public let healthPercentage: Metric<Double>
    public let fullChargeCapacityMAh: Metric<Int>
    public let designCapacityMAh: Metric<Int>
    public let cycleCount: Metric<Int>
    public let condition: Metric<BatteryCondition>

    public let temperatureCelsius: Metric<Double>
    public let voltageVolts: Metric<Double>
    public let chargingPowerWatts: Metric<Double>
    public let adapterWatts: Metric<Int>

    public init(
        timestamp: Date,
        hasBattery: Bool,
        charge: Metric<Double>,
        powerSource: Metric<PowerSource>,
        chargingState: Metric<ChargingState>,
        systemTimeToEmptyMinutes: Metric<Int>,
        systemTimeToFullMinutes: Metric<Int>,
        healthPercentage: Metric<Double>,
        fullChargeCapacityMAh: Metric<Int>,
        designCapacityMAh: Metric<Int>,
        cycleCount: Metric<Int>,
        condition: Metric<BatteryCondition>,
        temperatureCelsius: Metric<Double>,
        voltageVolts: Metric<Double>,
        chargingPowerWatts: Metric<Double>,
        adapterWatts: Metric<Int>
    ) {
        self.timestamp = timestamp
        self.hasBattery = hasBattery
        self.charge = charge
        self.powerSource = powerSource
        self.chargingState = chargingState
        self.systemTimeToEmptyMinutes = systemTimeToEmptyMinutes
        self.systemTimeToFullMinutes = systemTimeToFullMinutes
        self.healthPercentage = healthPercentage
        self.fullChargeCapacityMAh = fullChargeCapacityMAh
        self.designCapacityMAh = designCapacityMAh
        self.cycleCount = cycleCount
        self.condition = condition
        self.temperatureCelsius = temperatureCelsius
        self.voltageVolts = voltageVolts
        self.chargingPowerWatts = chargingPowerWatts
        self.adapterWatts = adapterWatts
    }

    /// A reading for a Mac with no internal battery.
    public static func noBattery(at timestamp: Date) -> BatteryReading {
        let reason = UnavailabilityReason.notSupportedOnThisMac
        return BatteryReading(
            timestamp: timestamp,
            hasBattery: false,
            charge: .unavailable(reason),
            powerSource: .measured(.externalPower),
            chargingState: .unavailable(reason),
            systemTimeToEmptyMinutes: .unavailable(reason),
            systemTimeToFullMinutes: .unavailable(reason),
            healthPercentage: .unavailable(reason),
            fullChargeCapacityMAh: .unavailable(reason),
            designCapacityMAh: .unavailable(reason),
            cycleCount: .unavailable(reason),
            condition: .unavailable(reason),
            temperatureCelsius: .unavailable(reason),
            voltageVolts: .unavailable(reason),
            chargingPowerWatts: .unavailable(reason),
            adapterWatts: .unavailable(reason)
        )
    }

    /// `true` when on external power; `nil` when unknown.
    public var isOnExternalPower: Bool? {
        powerSource.value.map { $0 == .externalPower }
    }

    /// `true` when charging; `nil` when unknown.
    public var isCharging: Bool? {
        chargingState.value.map { $0 == .charging }
    }
}
