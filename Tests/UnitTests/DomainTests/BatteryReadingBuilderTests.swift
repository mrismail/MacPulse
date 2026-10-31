import Foundation
import Testing
@testable import MacPulseDomain

@Suite("BatteryReadingBuilder")
struct BatteryReadingBuilderTests {
    private let date = BatteryFixtures.date

    @Test func intelMacOnBattery() throws {
        let reading = BatteryReadingBuilder.build(from: BatteryFixtures.intelOnBattery, at: date)

        #expect(reading.hasBattery)
        #expect(reading.timestamp == date)
        #expect(reading.charge == .measured(64))
        #expect(reading.powerSource == .measured(.battery))
        #expect(reading.chargingState == .measured(.discharging))
        #expect(reading.systemTimeToEmptyMinutes == .estimated(248, basis: BatteryReadingBuilder.estimateBasisSystem))
        #expect(reading.systemTimeToFullMinutes.provenance == .unavailable(.notApplicable("Not charging.")))
        #expect(reading.cycleCount == .measured(512))
        #expect(reading.condition == .measured(.normal))
        #expect(reading.temperatureCelsius == .measured(30.45))
        #expect(reading.voltageVolts == .measured(12.21))
        #expect(reading.chargingPowerWatts.provenance == .unavailable(.notApplicable("Not charging.")))
        #expect(reading.adapterWatts.provenance == .unavailable(.notApplicable("No power adapter connected.")))

        // Intel: no AppleRawMaxCapacity, so NominalChargeCapacity is used.
        #expect(reading.fullChargeCapacityMAh == .measured(7_480))
        #expect(reading.designCapacityMAh == .measured(8_790))
        let health = try #require(reading.healthPercentage.value)
        #expect(abs(health - 7_480.0 / 8_790.0 * 100) < 0.0001)
        guard case .estimated(let basis) = reading.healthPercentage.provenance else {
            Issue.record("Health must be labeled as an estimate")
            return
        }
        #expect(basis.contains("7480 mAh"))
        #expect(basis.contains("8790 mAh"))
    }

    @Test func realIntelMacBookPro16() throws {
        let reading = BatteryReadingBuilder.build(from: BatteryFixtures.realIntelMacBookPro16, at: date)

        #expect(reading.charge == .measured(98))
        #expect(reading.powerSource == .measured(.battery))
        // The stale fully-charged flag must not override "on battery".
        #expect(reading.chargingState == .measured(.discharging))
        #expect(reading.cycleCount == .measured(425))
        #expect(reading.fullChargeCapacityMAh == .measured(7_232))
        #expect(reading.designCapacityMAh == .measured(8_790))
        let health = try #require(reading.healthPercentage.value)
        #expect(abs(health - 82.27) < 0.01)  // 7232 / 8790
        #expect(reading.condition == .measured(.normal))
        #expect(reading.temperatureCelsius == .measured(30.72))
        #expect(reading.voltageVolts == .measured(12.031))
        #expect(reading.systemTimeToEmptyMinutes.value == 213)
    }

    @Test func chargedFlagCountsOnlyOnExternalPower() {
        var raw = BatteryFixtures.realIntelMacBookPro16
        raw.powerSourceState = "AC Power"
        #expect(BatteryReadingBuilder.build(from: raw, at: date).chargingState == .measured(.fullyCharged))
    }

    @Test func appleSiliconCharging() {
        let reading = BatteryReadingBuilder.build(from: BatteryFixtures.appleSiliconCharging, at: date)

        #expect(reading.charge == .measured(41))
        #expect(reading.powerSource == .measured(.externalPower))
        #expect(reading.chargingState == .measured(.charging))
        #expect(reading.systemTimeToFullMinutes == .estimated(74, basis: BatteryReadingBuilder.estimateBasisSystem))
        #expect(reading.systemTimeToEmptyMinutes.provenance == .unavailable(.notApplicable("Connected to power.")))
        #expect(reading.adapterWatts == .measured(96))
        // MaxCapacity = 100 is a percentage on Apple silicon and must not be read as mAh.
        #expect(reading.fullChargeCapacityMAh == .measured(5_830))
        #expect(reading.chargingPowerWatts.value.map { abs($0 - 12.85 * 3.2) < 0.0001 } == true)
        #expect(reading.chargingPowerWatts.isMeasured == false)
        #expect(reading.isCharging == true)
        #expect(reading.isOnExternalPower == true)
    }

    @Test func desktopMacHasNoBattery() {
        let reading = BatteryReadingBuilder.build(from: BatteryFixtures.desktop, at: date)
        #expect(!reading.hasBattery)
        #expect(reading.charge.provenance == .unavailable(.notSupportedOnThisMac))
        #expect(reading.cycleCount.provenance == .unavailable(.notSupportedOnThisMac))
        #expect(reading.healthPercentage.value == nil)
    }

    @Test func batteryReportedAbsentIsTreatedAsNoBattery() {
        var raw = BatteryFixtures.intelOnBattery
        raw.isPresent = false
        #expect(!BatteryReadingBuilder.build(from: raw, at: date).hasBattery)
    }

    @Test func missingRegistryLeavesIOPSValuesIntact() {
        var raw = BatteryFixtures.intelOnBattery
        raw.registry = nil
        let reading = BatteryReadingBuilder.build(from: raw, at: date)
        #expect(reading.charge == .measured(64))
        #expect(reading.cycleCount.provenance == .unavailable(.notSupportedOnThisMac))
        #expect(reading.healthPercentage.provenance == .unavailable(.notSupportedOnThisMac))
        #expect(reading.temperatureCelsius.provenance == .unavailable(.notSupportedOnThisMac))
    }

    @Test func fullyChargedTakesPriority() {
        var raw = BatteryFixtures.appleSiliconCharging
        raw.isCharging = false
        raw.isCharged = true
        let reading = BatteryReadingBuilder.build(from: raw, at: date)
        #expect(reading.chargingState == .measured(.fullyCharged))
        #expect(reading.chargingPowerWatts.provenance == .unavailable(.notApplicable("Not charging.")))
    }

    @Test func pluggedInButNotCharging() {
        var raw = BatteryFixtures.appleSiliconCharging
        raw.isCharging = false
        #expect(BatteryReadingBuilder.build(from: raw, at: date).chargingState == .measured(.notCharging))
    }

    @Test func calculatingTimeIsNotYetSampled() {
        var raw = BatteryFixtures.intelOnBattery
        raw.timeToEmptyMinutes = -1
        let reading = BatteryReadingBuilder.build(from: raw, at: date)
        #expect(reading.systemTimeToEmptyMinutes.provenance == .unavailable(.notYetSampled))
    }

    @Test func serviceConditionIsReported() {
        var raw = BatteryFixtures.intelOnBattery
        raw.batteryHealthCondition = "Service Recommended"
        let reading = BatteryReadingBuilder.build(from: raw, at: date)
        #expect(reading.condition == .measured(.serviceRecommended("Service Recommended")))
    }

    @Test(arguments: ["Fair", "Poor"])
    func degradedHealthIsNotNormal(health: String) {
        var raw = BatteryFixtures.intelOnBattery
        raw.batteryHealth = health
        let reading = BatteryReadingBuilder.build(from: raw, at: date)
        #expect(reading.condition == .measured(.serviceRecommended(health)))
    }

    @Test func desktopPowerSourceIsInferredNotMeasured() {
        let reading = BatteryReadingBuilder.build(from: BatteryFixtures.desktop, at: date)
        #expect(reading.powerSource.value == .externalPower)
        #expect(!reading.powerSource.isMeasured)
    }

    @Test func implausibleValuesBecomeSourceErrors() {
        var raw = BatteryFixtures.intelOnBattery
        raw.currentCapacity = 140
        raw.registry?.designCapacity = 0
        raw.registry?.temperatureCentiCelsius = 25_000
        raw.registry?.voltageMillivolts = 0
        raw.registry?.cycleCount = -3
        let reading = BatteryReadingBuilder.build(from: raw, at: date)

        func isSourceError<T: Sendable & Equatable>(_ metric: Metric<T>) -> Bool {
            if case .unavailable(.sourceError) = metric.provenance { return true }
            return false
        }
        #expect(isSourceError(reading.charge))
        #expect(isSourceError(reading.designCapacityMAh))
        #expect(isSourceError(reading.healthPercentage))
        #expect(isSourceError(reading.temperatureCelsius))
        #expect(isSourceError(reading.voltageVolts))
        #expect(isSourceError(reading.cycleCount))
    }

    @Test func implausibleHealthRatioIsRejected() {
        var raw = BatteryFixtures.intelOnBattery
        raw.registry?.nominalChargeCapacity = 2_000  // 23% of design: implausible
        let reading = BatteryReadingBuilder.build(from: raw, at: date)
        #expect(reading.healthPercentage.value == nil)
    }

    @Test func unknownPowerSourceState() {
        var raw = BatteryFixtures.intelOnBattery
        raw.powerSourceState = "UPS Power"
        raw.isCharging = false
        let reading = BatteryReadingBuilder.build(from: raw, at: date)
        #expect(reading.powerSource.value == nil)
        #expect(reading.chargingState.value == nil)
    }

    @Test func snapshotRecordsOnlyMeasuredCharge() {
        let reading = BatteryReadingBuilder.build(from: BatteryFixtures.intelOnBattery, at: date)
        let snapshot = BatterySnapshot(reading: reading, estimatedRuntimeMinutes: 200)
        #expect(snapshot.percentage == 64)
        #expect(snapshot.isPluggedIn == false)
        #expect(snapshot.isCharging == false)
        #expect(snapshot.cycleCount == 512)
        #expect(snapshot.estimatedRuntimeMinutes == 200)
        #expect(snapshot.timestamp == date)
    }

    @Test func snapshotRoundTripsThroughJSON() throws {
        let snapshot = BatterySnapshot(
            timestamp: date, percentage: 55.0, isCharging: true, isPluggedIn: true,
            healthPercentage: 91.2, cycleCount: 10, estimatedRuntimeMinutes: nil
        )
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(BatterySnapshot.self, from: data) == snapshot)
    }
}
