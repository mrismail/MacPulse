import Foundation

/// A value paired with its provenance.
///
/// Invariant: an `.unavailable` metric never carries a value, and a `.measured` or
/// `.estimated` metric always does. The memberwise initializer is not public, so the
/// only way to build a `Metric` is through the factory methods, which enforce this.
public struct Metric<Value: Sendable & Equatable>: Sendable, Equatable {
    public let value: Value?
    public let provenance: MetricProvenance

    fileprivate init(value: Value?, provenance: MetricProvenance) {
        self.value = value
        self.provenance = provenance
    }

    public static func measured(_ value: Value) -> Metric<Value> {
        Metric(value: value, provenance: .measured)
    }

    public static func estimated(_ value: Value, basis: String) -> Metric<Value> {
        Metric(value: value, provenance: .estimated(basis: basis))
    }

    public static func unavailable(_ reason: UnavailabilityReason) -> Metric<Value> {
        Metric(value: nil, provenance: .unavailable(reason))
    }

    /// `true` when the metric carries a value (measured or estimated).
    public var isAvailable: Bool { value != nil }

    /// `true` only for values read directly from the system.
    public var isMeasured: Bool { provenance == .measured }

    /// Transforms the value while keeping its provenance.
    public func map<Output: Sendable & Equatable>(_ transform: (Value) -> Output) -> Metric<Output> {
        Metric<Output>(value: value.map(transform), provenance: provenance)
    }
}
