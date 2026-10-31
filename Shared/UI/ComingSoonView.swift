import SwiftUI

/// Placeholder for a section whose feature is not available yet.
public struct ComingSoonView: View {
    private let title: String
    private let systemImage: String
    private let summary: String
    private let plannedCapabilities: [String]

    public init(
        title: String,
        systemImage: String,
        summary: String,
        plannedCapabilities: [String]
    ) {
        self.title = title
        self.systemImage = systemImage
        self.summary = summary
        self.plannedCapabilities = plannedCapabilities
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(summary)
        } actions: {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                ForEach(plannedCapabilities, id: \.self) { capability in
                    Label(capability, systemImage: "circle.dashed")
                        .foregroundStyle(.secondary)
                }
                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, Spacing.small)
            }
        }
    }
}
