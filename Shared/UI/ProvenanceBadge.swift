import MacPulseDomain
import SwiftUI

/// States whether a value is measured, estimated or unavailable.
///
/// Meaning is carried by the glyph shape and the text, both in label colors so they meet
/// contrast requirements in light and dark mode; a thin colored edge only reinforces it.
public struct ProvenanceBadge: View {
    private let provenance: MetricProvenance

    public init(_ provenance: MetricProvenance) {
        self.provenance = provenance
    }

    public var body: some View {
        let kind = provenance.kind
        Label(provenance.badgeTitle, systemImage: kind.symbolName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(kind == .unavailable ? Color.secondary : Color.primary)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, Spacing.small - 2)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.badge)
                    .strokeBorder(Palette.provenance(kind), lineWidth: 1)
            )
        .help(provenance.explanation)
        .accessibilityHidden(true)  // MetricValueView reads provenance as part of the value
    }
}
