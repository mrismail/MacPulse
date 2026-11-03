import AppKit

/// Keeps MacPulse running in the menu bar after its window is closed, while the menu bar
/// companion is on (ADR-016).
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app once its model exists.
    public var keepsRunningWithoutWindows: () -> Bool = { false }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !keepsRunningWithoutWindows()
    }
}
