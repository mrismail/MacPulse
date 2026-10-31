import Foundation

/// Turns raw power-source values into a provenance-tagged `BatteryReading`.
///
/// Rules:
/// - Values from documented IOPowerSources keys are `.measured`.
/// - Values computed from other values (health %, charging power) are `.estimated`
///   with a basis the user can read.
/// - Missing or implausible values become `.unavailable`, never a guess.
public enum BatteryReadingBuilder {
    public static let estimateBasisSystem = "macOS's own estimate."

    /// Plausible ranges. Values outside them are treated as sensor/firmware errors.
    static let plausibleHealthRatio = 0.3...1.3
    static let plausibleTemperature = 0.0...80.0
    static let plausibleVoltage = 5.0...30.0
    static let plausibleCapacityMAh = 500...30_000

    public static func build(from raw: RawBatteryData, at timestamp: Date) -> BatteryReading {
        guard raw.hasInternalBattery, raw.isPresent != false else {
            return .noBattery(at: timestamp)
        }
        let registry = raw.registry
        let powerSource = powerSourceMetric(raw)
        let chargingState = chargingStateMetric(raw, powerSource: powerSource.value)
        let fullCharge = fullChargeCapacity(registry)
        let design = designCapacity(registry)
        let voltage = voltageMetric(registry)

        return BatteryReading(
            timestamp: timestamp,
            hasBattery: true,
            charge: chargeMetric(raw),
            powerSource: powerSource,
            chargingState: chargingState,
            systemTimeToEmptyMinutes: timeToEmpty(raw, powerSource: powerSource.value),
            systemTimeToFullMinutes: timeToFull(raw, chargingState: chargingState.value),
            healthPercentage: health(fullCharge: fullCharge.value, design: design.value, registry: registry),
            fullChargeCapacityMAh: fullCharge,
            designCapacityMAh: design,
            cycleCount: cycleCountMetric(registry),
            condition: conditionMetric(raw),
            temperatureCelsius: temperatureMetric(registry),
            voltageVolts: voltage,
            chargingPowerWatts: chargingPower(registry, voltage: voltage.value, chargingState: chargingState.value),
            adapterWatts: adapterMetric(raw, powerSource: powerSource.value)
        )
    }

    // MARK: - Charge and state

    static func chargeMetric(_ raw: RawBatteryData) -> Metric<Double> {
        guard let current = raw.currentCapacity, let max = raw.maxCapacity else {
            return .unavailable(.sourceError("capacity not reported"))
        }
        guard max > 0, current >= 0, current <= max else {
            return .unavailable(.sourceError("capacity \(current)/\(max)"))
        }
        return .measured(Double(current) * 100 / Double(max))
    }

    static func powerSourceMetric(_ raw: RawBatteryData) -> Metric<PowerSource> {
        switch raw.powerSourceState {
        case "AC Power"?: .measured(.externalPower)
        case "Battery Power"?: .measured(.battery)
        case nil: .unavailable(.sourceError("power source state not reported"))
        case let other?: .unavailable(.sourceError("unknown power source \(other)"))
        }
    }

    static func chargingStateMetric(_ raw: RawBatteryData, powerSource: PowerSource?) -> Metric<ChargingState> {
        if raw.isCharged == true {
            return .measured(.fullyCharged)
        }
        guard let isCharging = raw.isCharging else {
            return .unavailable(.sourceError("charging state not reported"))
        }
        if isCharging {
            return .measured(.charging)
        }
        switch powerSource {
        case .externalPower: return .measured(.notCharging)
        case .battery: return .measured(.discharging)
        case nil: return .unavailable(.sourceError("power source unknown"))
        }
    }

    static func timeToEmpty(_ raw: RawBatteryData, powerSource: PowerSource?) -> Metric<Int> {
        guard powerSource == .battery else {
            return .unavailable(.notApplicable("Connected to power."))
        }
        guard let minutes = raw.timeToEmptyMinutes else {
            return .unavailable(.notSupportedOnThisMac)
        }
        guard minutes > 0 else {
            return .unavailable(.notYetSampled)
        }
        return .estimated(minutes, basis: estimateBasisSystem)
    }

    static func timeToFull(_ raw: RawBatteryData, chargingState: ChargingState?) -> Metric<Int> {
        guard chargingState == .charging else {
            return .unavailable(.notApplicable("Not charging."))
        }
        guard let minutes = raw.timeToFullMinutes else {
            return .unavailable(.notSupportedOnThisMac)
        }
        guard minutes > 0 else {
            return .unavailable(.notYetSampled)
        }
        return .estimated(minutes, basis: estimateBasisSystem)
    }

    // MARK: - Health

    static func fullChargeCapacity(_ registry: RawBatteryData.RegistryValues?) -> Metric<Int> {
        guard let registry else { return .unavailable(.notSupportedOnThisMac) }
        // MaxCapacity is a percentage (≤ 100) on Apple silicon, so it only counts as mAh when larger.
        let legacyMax = registry.maxCapacity.flatMap { $0 > 100 ? $0 : nil }
        guard let value = registry.appleRawMaxCapacity ?? registry.nominalChargeCapacity ?? legacyMax else {
            return .unavailable(.notSupportedOnThisMac)
        }
        guard plausibleCapacityMAh.contains(value) else {
            return .unavailable(.sourceError("full-charge capacity \(value) mAh"))
        }
        return .measured(value)
    }

    static func designCapacity(_ registry: RawBatteryData.RegistryValues?) -> Metric<Int> {
        guard let value = registry?.designCapacity else {
            return .unavailable(.notSupportedOnThisMac)
        }
        guard plausibleCapacityMAh.contains(value) else {
            return .unavailable(.sourceError("design capacity \(value) mAh"))
        }
        return .measured(value)
    }

    static func health(
        fullCharge: Int?,
        design: Int?,
        registry: RawBatteryData.RegistryValues?
    ) -> Metric<Double> {
        guard let fullCharge, let design else {
            return registry == nil ? .unavailable(.notSupportedOnThisMac) : .unavailable(.sourceError("capacity values missing"))
        }
        let ratio = Double(fullCharge) / Double(design)
        guard plausibleHealthRatio.contains(ratio) else {
            return .unavailable(.sourceError("capacity ratio \(String(format: "%.2f", ratio))"))
        }
        return .estimated(
            ratio * 100,
            basis: "Full-charge capacity (\(fullCharge) mAh) divided by design capacity (\(design) mAh). "
                + "The Maximum Capacity shown in System Settings may differ slightly."
        )
    }

    static func cycleCountMetric(_ registry: RawBatteryData.RegistryValues?) -> Metric<Int> {
        guard let count = registry?.cycleCount else {
            return .unavailable(.notSupportedOnThisMac)
        }
        guard count >= 0, count < 100_000 else {
            return .unavailable(.sourceError("cycle count \(count)"))
        }
        return .measured(count)
    }

    static func conditionMetric(_ raw: RawBatteryData) -> Metric<BatteryCondition> {
        if let condition = raw.batteryHealthCondition?.trimmingCharacters(in: .whitespaces), !condition.isEmpty {
            return .measured(.serviceRecommended(condition))
        }
        switch raw.batteryHealth?.trimmingCharacters(in: .whitespaces) {
        case "Good"?:
            // macOS omits BatteryHealthCondition when the battery is normal.
            return .measured(.normal)
        case let health? where !health.isEmpty:
            // "Fair", "Poor" (IOPSKeys.h) or any other non-good value.
            return .measured(.serviceRecommended(health))
        default:
            return .unavailable(.notSupportedOnThisMac)
        }
    }

    // MARK: - Electrical

    static func temperatureMetric(_ registry: RawBatteryData.RegistryValues?) -> Metric<Double> {
        guard let centi = registry?.temperatureCentiCelsius else {
            return .unavailable(.notSupportedOnThisMac)
        }
        let celsius = Double(centi) / 100
        guard plausibleTemperature.contains(celsius), centi != 0 else {
            return .unavailable(.sourceError("temperature \(centi)"))
        }
        return .measured(celsius)
    }

    static func voltageMetric(_ registry: RawBatteryData.RegistryValues?) -> Metric<Double> {
        guard let millivolts = registry?.voltageMillivolts else {
            return .unavailable(.notSupportedOnThisMac)
        }
        let volts = Double(millivolts) / 1_000
        guard plausibleVoltage.contains(volts) else {
            return .unavailable(.sourceError("voltage \(millivolts) mV"))
        }
        return .measured(volts)
    }

    static func chargingPower(
        _ registry: RawBatteryData.RegistryValues?,
        voltage: Double?,
        chargingState: ChargingState?
    ) -> Metric<Double> {
        guard chargingState == .charging else {
            return .unavailable(.notApplicable("Not charging."))
        }
        guard let voltage, let amperage = registry?.amperageMilliamps else {
            return .unavailable(.notSupportedOnThisMac)
        }
        guard amperage > 0 else {
            return .unavailable(.notApplicable("The battery reports no charging current right now."))
        }
        let watts = voltage * Double(amperage) / 1_000
        return .estimated(watts, basis: "Battery voltage × charging current, as reported by the battery.")
    }

    static func adapterMetric(_ raw: RawBatteryData, powerSource: PowerSource?) -> Metric<Int> {
        guard powerSource == .externalPower else {
            return .unavailable(.notApplicable("No power adapter connected."))
        }
        guard let watts = raw.adapterWatts, watts > 0 else {
            return .unavailable(.notSupportedOnThisMac)
        }
        return .measured(watts)
    }
}
