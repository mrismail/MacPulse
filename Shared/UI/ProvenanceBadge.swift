import MacPulseDomain
import SwiftUI

/// States whether a value is measured, estimated or unavailable.
///
/// Meaning is carried by the glyph shape and the text, in label colors so they meet
/// contrast requirements in light and dark mode. The border is neutral: color alone never
/// says whether a value is measured or estimated.
public struct ProvenanceBadge: View {
    private let provenance: MetricProvenance

    public init(_ provenance: MetricProvenance) {
        self.provenance = provenance
    }

    public var body: some View {
        let kind = provenance.kind
        Label(provenance.badgeTitle, systemImage: kind.symbolName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(kind == .unavailable ? Palette.secondaryText : Color.primary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize()  // never wrap or hyphenate ("Mea-sured") in narrow columns
            .padding(.horizontal, Spacing.small - 2)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.badge)
                    // Neutral border: the badge's text and symbol carry the meaning, and a
                    // green or orange outline was flagged by the contrast audit.
                    .strokeBorder(Palette.secondaryText, lineWidth: 1)
            )
        .help(provenance.explanation)
        .accessibilityHidden(true)  // MetricValueView reads provenance as part of the value
    }
}
