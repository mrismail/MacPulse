import MacPulseDomain
import SwiftUI

/// States whether a value is measured, estimated or unavailable.
///
/// Meaning is carried by the glyph and the text (primary/secondary label colors for
/// contrast); color only reinforces it.
public struct ProvenanceBadge: View {
    private let provenance: MetricProvenance

    public init(_ provenance: MetricProvenance) {
        self.provenance = provenance
    }

    public var body: some View {
        let kind = provenance.kind
        Label {
            Text(provenance.badgeTitle)
                .foregroundStyle(kind == .unavailable ? .secondary : .primary)
        } icon: {
            Image(systemName: kind.symbolName)
                .foregroundStyle(Palette.provenance(kind))
        }
        .font(.caption2.weight(.medium))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, Spacing.small - 2)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.badge))
        .help(provenance.explanation)
        .accessibilityHidden(true)  // MetricValueView reads provenance as part of the value
    }
}
