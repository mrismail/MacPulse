import MacPulseDomain
import SwiftUI

/// Small capsule stating whether a value is measured, estimated or unavailable.
public struct ProvenanceBadge: View {
    private let provenance: MetricProvenance

    public init(_ provenance: MetricProvenance) {
        self.provenance = provenance
    }

    public var body: some View {
        let color = Palette.provenance(provenance.kind)
        Text(provenance.badgeTitle)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Spacing.small - 2)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.badge))
            .help(provenance.explanation)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(provenance.badgeTitle)
            .accessibilityHint(provenance.explanation)
    }
}
