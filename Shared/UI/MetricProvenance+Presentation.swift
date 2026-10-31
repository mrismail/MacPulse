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
        case .measured: "Measured"
        case .estimated: "Estimate"
        case .unavailable: "Unavailable"
        }
    }

    /// One-sentence explanation shown as a tooltip and read by VoiceOver.
    public var explanation: String {
        switch self {
        case .measured:
            "Read directly from macOS."
        case .estimated(let basis):
            "Estimated. \(basis)"
        case .unavailable(let reason):
            reason.explanation
        }
    }
}

extension UnavailabilityReason {
    public var explanation: String {
        switch self {
        case .notSupportedOnThisMac:
            "This Mac or macOS version doesn't report this value."
        case .permissionRequired:
            "MacPulse needs your permission to read this value."
        case .notYetSampled:
            "Not enough data collected yet."
        case .notYetImplemented:
            "Coming in a later version of MacPulse."
        case .sourceError(let detail):
            "macOS returned an unexpected value (\(detail))."
        case .notApplicable(let detail):
            detail
        }
    }
}
