import MacPulseDomain
import SwiftUI

/// Displays a titled metric with its provenance badge.
/// Unavailable metrics show an em dash and the reason, never a fabricated value.
public struct MetricValueView<Value: Sendable & Equatable>: View {
    private let title: String
    private let metric: Metric<Value>
    private let format: (Value) -> String

    public init(_ title: String, metric: Metric<Value>, format: @escaping (Value) -> String) {
        self.title = title
        self.metric = metric
        self.format = format
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack(spacing: Spacing.small) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProvenanceBadge(metric.provenance)
            }
            Text(metric.value.map(format) ?? "—")
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(metric.isAvailable ? Color.primary : Color.secondary)
            if case .unavailable = metric.provenance {
                Text(metric.provenance.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
