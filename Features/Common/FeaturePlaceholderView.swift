import MacPulseShared
import SwiftUI

/// Placeholder screen for a feature scheduled for a later phase.
public struct FeaturePlaceholderView: View {
    private let feature: PlannedFeature

    public init(feature: PlannedFeature) {
        self.feature = feature
    }

    public var body: some View {
        ComingSoonView(
            title: feature.title,
            systemImage: feature.systemImage,
            summary: feature.summary,
            plannedCapabilities: feature.capabilities
        )
        .navigationTitle(feature.title)
    }
}
