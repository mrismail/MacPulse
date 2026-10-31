import Foundation

/// Where a displayed value comes from.
///
/// MacPulse must never present an estimate as a measurement, or hide that a metric is
/// unsupported. Every value shown to the user carries one of these.
public enum MetricProvenance: Sendable, Hashable {
    /// Read directly from a supported system interface.
    case measured
    /// Derived from other values. `basis` explains how, in user-facing language
    /// (for example "Based on the last 15 minutes of discharge").
    case estimated(basis: String)
    /// No trustworthy value exists.
    case unavailable(UnavailabilityReason)
}

/// Why a metric has no value.
public enum UnavailabilityReason: Sendable, Hashable {
    /// The hardware or macOS version does not expose this metric (for example, no battery on a desktop Mac).
    case notSupportedOnThisMac
    /// The user has not granted a permission the metric needs.
    case permissionRequired
    /// Monitoring has not collected enough samples yet.
    case notYetSampled
    /// The feature that provides this metric has not been built yet.
    case notYetImplemented
    /// The system source returned an error or an implausible value.
    case sourceError(String)
}
