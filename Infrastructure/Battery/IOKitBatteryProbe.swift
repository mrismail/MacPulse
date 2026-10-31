import Foundation
import IOKit
import IOKit.ps
import MacPulseDomain

/// Copies raw values out of IOPowerSources and the AppleSmartBattery registry entry.
/// Performs no interpretation — see `BatteryReadingBuilder`.
///
/// Both interfaces are read-only, need no entitlement and no administrator access.
enum IOKitBatteryProbe {
    // Keys from IOKit/ps/IOPSKeys.h. String literals are used so the mapping is explicit.
    enum PSKey {
        static let type = "Type"
        static let internalBatteryType = "InternalBattery"
        static let isPresent = "Is Present"
        static let currentCapacity = "Current Capacity"
        static let maxCapacity = "Max Capacity"
        static let isCharging = "Is Charging"
        static let isCharged = "Is Charged"
        static let powerSourceState = "Power Source State"
        static let timeToEmpty = "Time to Empty"
        static let timeToFullCharge = "Time to Full Charge"
        static let batteryHealth = "BatteryHealth"
        static let batteryHealthCondition = "BatteryHealthCondition"
        static let adapterWatts = "Watts"
    }

    static func read() -> RawBatteryData {
        var raw = RawBatteryData(hasInternalBattery: false)

        if let description = internalBatteryDescription() {
            raw.hasInternalBattery = true
            raw.isPresent = description[PSKey.isPresent] as? Bool
            raw.currentCapacity = int(description[PSKey.currentCapacity])
            raw.maxCapacity = int(description[PSKey.maxCapacity])
            raw.isCharging = description[PSKey.isCharging] as? Bool
            raw.isCharged = description[PSKey.isCharged] as? Bool
            raw.powerSourceState = description[PSKey.powerSourceState] as? String
            raw.timeToEmptyMinutes = int(description[PSKey.timeToEmpty])
            raw.timeToFullMinutes = int(description[PSKey.timeToFullCharge])
            raw.batteryHealth = description[PSKey.batteryHealth] as? String
            raw.batteryHealthCondition = description[PSKey.batteryHealthCondition] as? String
            raw.registry = registryValues()
        }
        raw.adapterWatts = adapterWatts()
        return raw
    }

    private static func internalBatteryDescription() -> [String: Any]? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as NSArray?
        else {
            return nil
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source as CFTypeRef)?
                .takeUnretainedValue() as? [String: Any]
            else { continue }
            if description[PSKey.type] as? String == PSKey.internalBatteryType {
                return description
            }
        }
        return nil
    }

    private static func adapterWatts() -> Int? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return int(details[PSKey.adapterWatts])
    }

    private static func registryValues() -> RawBatteryData.RegistryValues? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }
        return RawBatteryData.RegistryValues(
            cycleCount: int(dictionary["CycleCount"]),
            designCapacity: int(dictionary["DesignCapacity"]),
            appleRawMaxCapacity: int(dictionary["AppleRawMaxCapacity"]),
            nominalChargeCapacity: int(dictionary["NominalChargeCapacity"]),
            maxCapacity: int(dictionary["MaxCapacity"]),
            temperatureCentiCelsius: int(dictionary["Temperature"]),
            voltageMillivolts: int(dictionary["Voltage"]),
            amperageMilliamps: int(dictionary["InstantAmperage"]) ?? int(dictionary["Amperage"])
        )
    }

    /// Reads an integer, treating values stored as unsigned 64-bit two's complement
    /// (as `Amperage` is while discharging) as signed.
    static func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        return Int(truncatingIfNeeded: number.int64Value)
    }
}
