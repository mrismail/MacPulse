/// Top-level destinations in the sidebar.
public enum SidebarSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case overview
    case battery
    case energy
    case spaceAnalyzer
    case duplicateFinder
    case cleaner
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .battery: "Battery"
        case .energy: "Energy"
        case .spaceAnalyzer: "Space Analyzer"
        case .duplicateFinder: "Duplicate Finder"
        case .cleaner: "Cleaner"
        case .settings: "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .battery: "battery.75percent"
        case .energy: "bolt.horizontal.circle"
        case .spaceAnalyzer: "chart.pie"
        case .duplicateFinder: "doc.on.doc"
        case .cleaner: "trash"
        case .settings: "gearshape"
        }
    }

    public var group: SidebarGroup {
        switch self {
        case .overview: .general
        case .battery, .energy: .power
        case .spaceAnalyzer, .duplicateFinder, .cleaner: .storage
        case .settings: .app
        }
    }

    /// Digit for the ⌘-number shortcut in the Go menu (⌘1 … ⌘7).
    public var shortcutDigit: Character {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return Character(String(index + 1))
    }

    /// Stable identifier for UI automation.
    public var accessibilityIdentifier: String { "sidebar.\(rawValue)" }
}

/// Sidebar sections are grouped under headings.
public enum SidebarGroup: String, CaseIterable, Identifiable, Sendable {
    case general
    case power
    case storage
    case app

    public var id: String { rawValue }

    /// Heading text, or `nil` for groups shown without a heading.
    public var title: String? {
        switch self {
        case .general: nil
        case .power: "Power"
        case .storage: "Storage"
        case .app: nil
        }
    }

    public var sections: [SidebarSection] {
        SidebarSection.allCases.filter { $0.group == self }
    }
}
