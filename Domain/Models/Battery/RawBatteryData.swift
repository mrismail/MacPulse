import Foundation

/// Unprocessed values read from macOS power interfaces.
///
/// The infrastructure layer only copies values into this struct; all interpretation
/// (units, plausibility checks, provenance) happens in `BatteryReadingBuilder`, so it
/// can be unit-tested with fixtures from different Mac models.
public struct RawBatteryData: Sendable, Equatable {
    // MARK: IOPowerSources (documented, IOPSKeys.h)

    /// An `InternalBattery` power source was found.
    public var hasInternalBattery: Bool
    /// `Is Present`.
    public var isPresent: Bool?
    /// `Current Capacity` — on Macs this is a percentage of `Max Capacity`.
    public var currentCapacity: Int?
    /// `Max Capacity` — normally 100 on Macs.
    public var maxCapacity: Int?
    /// `Is Charging`.
    public var isCharging: Bool?
    /// `Is Charged`.
    public var isCharged: Bool?
    /// `Power Source State` — "AC Power" or "Battery Power".
    public var powerSourceState: String?
    /// `Time to Empty` in minutes; -1 while macOS is still calculating.
    public var timeToEmptyMinutes: Int?
    /// `Time to Full Charge` in minutes; -1 while macOS is still calculating.
    public var timeToFullMinutes: Int?
    /// `BatteryHealth` — e.g. "Good".
    public var batteryHealth: String?
    /// `BatteryHealthCondition` — e.g. "Check Battery", "Service Recommended". Absent when normal.
    public var batteryHealthCondition: String?
    /// `Watts` from `IOPSCopyExternalPowerAdapterDetails`.
    public var adapterWatts: Int?

    // MARK: AppleSmartBattery IORegistry entry (best-effort, not formally documented)

    public var registry: RegistryValues?

    public struct RegistryValues: Sendable, Equatable {
        public var cycleCount: Int?
        public var designCapacity: Int?
        /// `AppleRawMaxCapacity` (mAh). Present on Apple silicon and recent Intel Macs.
        public var appleRawMaxCapacity: Int?
        /// `NominalChargeCapacity` (mAh).
        public var nominalChargeCapacity: Int?
        /// `MaxCapacity` — mAh on older Intel Macs, a percentage (≤ 100) on Apple silicon.
        public var maxCapacity: Int?
        /// `Temperature` in hundredths of a degree Celsius.
        public var temperatureCentiCelsius: Int?
        /// `Voltage` in millivolts.
        public var voltageMillivolts: Int?
        /// `Amperage` in milliamps; positive while charging, negative while discharging.
        public var amperageMilliamps: Int?

        public init(
            cycleCount: Int? = nil,
            designCapacity: Int? = nil,
            appleRawMaxCapacity: Int? = nil,
            nominalChargeCapacity: Int? = nil,
            maxCapacity: Int? = nil,
            temperatureCentiCelsius: Int? = nil,
            voltageMillivolts: Int? = nil,
            amperageMilliamps: Int? = nil
        ) {
            self.cycleCount = cycleCount
            self.designCapacity = designCapacity
            self.appleRawMaxCapacity = appleRawMaxCapacity
            self.nominalChargeCapacity = nominalChargeCapacity
            self.maxCapacity = maxCapacity
            self.temperatureCentiCelsius = temperatureCentiCelsius
            self.voltageMillivolts = voltageMillivolts
            self.amperageMilliamps = amperageMilliamps
        }
    }

    public init(
        hasInternalBattery: Bool,
        isPresent: Bool? = nil,
        currentCapacity: Int? = nil,
        maxCapacity: Int? = nil,
        isCharging: Bool? = nil,
        isCharged: Bool? = nil,
        powerSourceState: String? = nil,
        timeToEmptyMinutes: Int? = nil,
        timeToFullMinutes: Int? = nil,
        batteryHealth: String? = nil,
        batteryHealthCondition: String? = nil,
        adapterWatts: Int? = nil,
        registry: RegistryValues? = nil
    ) {
        self.hasInternalBattery = hasInternalBattery
        self.isPresent = isPresent
        self.currentCapacity = currentCapacity
        self.maxCapacity = maxCapacity
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.powerSourceState = powerSourceState
        self.timeToEmptyMinutes = timeToEmptyMinutes
        self.timeToFullMinutes = timeToFullMinutes
        self.batteryHealth = batteryHealth
        self.batteryHealthCondition = batteryHealthCondition
        self.adapterWatts = adapterWatts
        self.registry = registry
    }
}
