import AppKit

/// Makes sure MacPulse's main window is shown when the app is opened.
///
/// CI showed that in a right-to-left layout (Arabic) macOS 15 can start a SwiftUI app with
/// a single `Window` scene and a menu bar extra without creating its window. Two paths open
/// it: the menu bar label (drawn at launch, uses SwiftUI's `openWindow`), and this fallback
/// from the app delegate, which works with the menu bar companion turned off and uses the
/// scene's item in the Window menu. Replace both with `.defaultLaunchBehavior(.presented)`
/// once macOS 15 is the minimum.
@MainActor
public enum MainWindowLauncher {
    /// The main window's title, as it appears in the Window menu.
    public static let windowTitle = "MacPulse"

    /// `true` when a visible window other than Settings is open.
    public static var hasMainWindow: Bool {
        NSApplication.shared.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled)
                && !(window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") ?? false)
        }
    }

    /// Opens the main window through its Window-menu item. Returns `false` if none was found.
    @discardableResult
    public static func openFromWindowMenu() -> Bool {
        let menus = [NSApplication.shared.windowsMenu].compactMap { $0 } + (NSApplication.shared.mainMenu?.items.compactMap(\.submenu) ?? [])
        for menu in menus {
            if let item = menu.items.first(where: { $0.title == windowTitle && $0.action != nil }), let action = item.action {
                return NSApplication.shared.sendAction(action, to: item.target, from: item)
            }
        }
        return false
    }
}
