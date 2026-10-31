import Foundation
@testable import MacPulseDomain

/// Raw data shaped like what real Macs report.
enum BatteryFixtures {
    static let date = Date(timeIntervalSince1970: 1_793_400_000)

    /// Intel MacBook Pro (16-inch, 2019) on battery. `MaxCapacity` is in mAh.
    static let intelOnBattery = RawBatteryData(
        hasInternalBattery: true,
        isPresent: true,
        currentCapacity: 64,
        maxCapacity: 100,
        isCharging: false,
        isCharged: false,
        powerSourceState: "Battery Power",
        timeToEmptyMinutes: 248,
        timeToFullMinutes: -1,
        batteryHealth: "Good",
        registry: .init(
            cycleCount: 512,
            designCapacity: 8_790,
            nominalChargeCapacity: 7_480,
            maxCapacity: 7_380,
            temperatureCentiCelsius: 3_045,
            voltageMillivolts: 12_210,
            amperageMilliamps: -1_480
        )
    )

    /// Apple silicon MacBook Pro charging. `MaxCapacity` is a percentage there.
    static let appleSiliconCharging = RawBatteryData(
        hasInternalBattery: true,
        isPresent: true,
        currentCapacity: 41,
        maxCapacity: 100,
        isCharging: true,
        isCharged: false,
        powerSourceState: "AC Power",
        timeToEmptyMinutes: -1,
        timeToFullMinutes: 74,
        batteryHealth: "Good",
        adapterWatts: 96,
        registry: .init(
            cycleCount: 88,
            designCapacity: 6_075,
            appleRawMaxCapacity: 5_830,
            nominalChargeCapacity: 5_900,
            maxCapacity: 100,
            temperatureCentiCelsius: 3_310,
            voltageMillivolts: 12_850,
            amperageMilliamps: 3_200
        )
    )

    /// Captured from the owner's Intel MacBook Pro (16-inch, 2019) with
    /// `ioreg -rc AppleSmartBattery -a` on 2026-10-31, unplugged right after a full
    /// charge. Identifiers (serial numbers) intentionally omitted.
    /// Notable: `MaxCapacity` is mAh here, there is no `NominalChargeCapacity`, and the
    /// fully-charged flag is still set although the Mac is on battery.
    static let realIntelMacBookPro16 = RawBatteryData(
        hasInternalBattery: true,
        isPresent: true,
        currentCapacity: 98,  // IOPS percentage: 7057 / 7232 mAh
        maxCapacity: 100,
        isCharging: false,
        isCharged: true,
        powerSourceState: "Battery Power",
        timeToEmptyMinutes: 213,
        timeToFullMinutes: -1,
        batteryHealth: "Good",
        registry: .init(
            cycleCount: 425,
            designCapacity: 8_790,
            appleRawMaxCapacity: 7_232,
            nominalChargeCapacity: nil,
            maxCapacity: 7_232,
            temperatureCentiCelsius: 3_072,
            voltageMillivolts: 12_031,
            amperageMilliamps: -2_435
        )
    )

    /// Desktop Mac: no internal battery.
    static let desktop = RawBatteryData(hasInternalBattery: false, adapterWatts: nil)
}
