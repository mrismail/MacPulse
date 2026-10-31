import SwiftUI

/// Placeholder for a section whose feature arrives in a later phase.
public struct ComingSoonView: View {
    private let title: String
    private let systemImage: String
    private let summary: String
    private let plannedCapabilities: [String]
    private let phase: Int

    public init(
        title: String,
        systemImage: String,
        summary: String,
        plannedCapabilities: [String],
        phase: Int
    ) {
        self.title = title
        self.systemImage = systemImage
        self.summary = summary
        self.plannedCapabilities = plannedCapabilities
        self.phase = phase
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
                Text("Planned for development phase \(phase).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, Spacing.small)
            }
        }
    }
}
