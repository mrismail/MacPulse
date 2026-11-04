import MacPulseDomain

/// User-facing wording for provenance. Kept out of the views so it can be unit-tested.
public enum ProvenanceKind: Sendable, Equatable {
    case measured
    case estimated
    case unavailable

    /// Shape carries the meaning, so the badge never relies on color alone.
    public var symbolName: String {
        switch self {
        case .measured: "checkmark.seal.fill"
        case .estimated: "function"
        case .unavailable: "minus.circle"
        }
    }
}

extension MetricProvenance {
    public var kind: ProvenanceKind {
        switch self {
        case .measured: .measured
        case .estimated: .estimated
        case .unavailable: .unavailable
        }
    }

    /// Short label for the badge next to a value.
    public var badgeTitle: String {
        switch self {
        case .measured: String(localized: "Measured")
        case .estimated: String(localized: "Estimate")
        case .unavailable: String(localized: "Unavailable")
        }
    }

    /// One-sentence explanation shown as a tooltip and read by VoiceOver.
    public var explanation: String {
        switch self {
        case .measured:
            String(localized: "Read directly from macOS.")
        case .estimated(let basis):
            String(localized: "Estimated. \(basis)")
        case .unavailable(let reason):
            reason.explanation
        }
    }
}

extension UnavailabilityReason {
    public var explanation: String {
        switch self {
        case .notSupportedOnThisMac:
            String(localized: "This Mac or macOS version doesn't report this value.")
        case .permissionRequired:
            String(localized: "MacPulse needs your permission to read this value.")
        case .notYetSampled:
            String(localized: "Not enough data collected yet.")
        case .notYetImplemented:
            String(localized: "Coming in a later version of MacPulse.")
        case .sourceError(let detail):
            String(localized: "macOS returned an unexpected value (\(detail)).")
        case .notApplicable(let detail):
            detail
        }
    }
}
