import MacPulseDomain
import SwiftUI

/// Displays a titled metric with its provenance badge.
/// Unavailable metrics show an em dash and the reason, never a fabricated value.
///
/// VoiceOver reads one label, "<title>: <value>, <Measured|Estimate|Unavailable>",
/// with the explanation as the hint. (On macOS a combined element's AXValue is not
/// exposed reliably, so everything that matters is in the label.)
public struct MetricValueView<Value: Sendable & Equatable>: View {
    public enum Prominence: Sendable {
        case standard
        case hero
    }

    private let title: String
    private let metric: Metric<Value>
    private let prominence: Prominence
    private let format: (Value) -> String

    public init(
        _ title: String,
        metric: Metric<Value>,
        prominence: Prominence = .standard,
        format: @escaping (Value) -> String
    ) {
        self.title = title
        self.metric = metric
        self.prominence = prominence
        self.format = format
    }

    private var valueText: String? { metric.value.map(format) }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack(spacing: Spacing.small) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProvenanceBadge(metric.provenance)
            }
            Text(valueText ?? "—")
                .font(valueFont)
                .foregroundStyle(metric.isAvailable ? Color.primary : Color.secondary)
            if case .unavailable = metric.provenance {
                Text(metric.provenance.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(metric.provenance.explanation)
        // Expose one static-text element (a known role) instead of a role-less group.
        .accessibilityRepresentation {
            Text(accessibilityText)
        }
        .accessibilityHint(metric.provenance.explanation)
    }

    private var valueFont: Font {
        switch prominence {
        case .standard: .title2.monospacedDigit().weight(.semibold)
        case .hero: .system(size: 44, weight: .bold, design: .rounded).monospacedDigit()
        }
    }

    private var accessibilityText: String {
        let value = valueText ?? String(localized: "Not available")
        return "\(title): \(value), \(metric.provenance.badgeTitle)"
    }
}
