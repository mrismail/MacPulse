import AppKit
import SwiftUI

/// Spacing scale used across all screens.
public enum Spacing {
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 20
    public static let xLarge: CGFloat = 32
}

/// Corner radii.
public enum Radius {
    public static let card: CGFloat = 12
    public static let badge: CGFloat = 6
}

/// Semantic colors. Built on system colors so light/dark mode and
/// "Increase contrast" are handled by macOS.
public enum Palette {
    public static let cardBackground = Color(nsColor: .controlBackgroundColor)
    public static let cardBorder = Color(nsColor: .separatorColor)

    public static func provenance(_ kind: ProvenanceKind) -> Color {
        switch kind {
        case .measured: .green
        case .estimated: .orange
        case .unavailable: .secondary
        }
    }
}
