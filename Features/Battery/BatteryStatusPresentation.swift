import MacPulseDomain

/// Wording shared by every screen that shows battery state, so the Overview and the
/// Battery screen can never disagree.
public enum BatteryStatusPresentation {
    public static func stateDescription(_ reading: BatteryReading?) -> String {
        guard let reading else { return String(localized: "Reading battery…") }
        guard reading.hasBattery else { return String(localized: "No battery") }
        switch reading.chargingState.value {
        case .charging: return String(localized: "Charging")
        case .discharging: return String(localized: "On battery")
        case .notCharging: return String(localized: "Plugged in, not charging")
        case .fullyCharged: return String(localized: "Fully charged")
        case nil: return String(localized: "Status unknown")
        }
    }

    public static func condition(_ reading: BatteryReading?) -> Metric<String> {
        guard let reading else { return .unavailable(.notYetSampled) }
        return reading.condition.map { condition in
            switch condition {
            case .normal: String(localized: "Normal")
            case .serviceRecommended(let text): text
            }
        }
    }

    /// The one "Estimated runtime" figure used everywhere. Not applicable while on power.
    public static func estimatedRuntime(_ status: BatteryStatus?) -> Metric<Int> {
        guard let status else { return .unavailable(.notYetSampled) }
        guard status.reading.hasBattery else { return .unavailable(.notSupportedOnThisMac) }
        guard status.reading.powerSource.value == .battery else {
            return .unavailable(.notApplicable(String(localized: "Connected to power.")))
        }
        return status.bestRuntimeEstimate
    }
}
