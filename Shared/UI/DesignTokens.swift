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
    /// Supporting text on cards. The system's secondary label color measures below
    /// 4.5:1 on a card background in the accessibility audit, and CI's audit rated 72 % of
    /// the primary color "nearly passed"; 85 % keeps text visibly secondary.
    public static let secondaryText = Color.primary.opacity(0.85)

    public static func provenance(_ kind: ProvenanceKind) -> Color {
        switch kind {
        case .measured: .green
        case .estimated: .orange
        case .unavailable: .secondary
        }
    }
}
