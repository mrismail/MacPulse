import SwiftUI

/// The standard container for a group of related information.
public struct Card<Content: View>: View {
    private let title: String?
    private let systemImage: String?
    private let content: Content

    public init(
        _ title: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            if let title {
                Group {
                    if let systemImage {
                        Label(title, systemImage: systemImage)
                    } else {
                        Text(title)
                    }
                }
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
        )
    }
}
