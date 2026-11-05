import AppKit
import MacPulseShared

/// Keeps MacPulse running in the menu bar after its window is closed, while the menu bar
/// companion is on (ADR-016).
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app once its model exists.
    public var keepsRunningWithoutWindows: () -> Bool = { false }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !keepsRunningWithoutWindows()
    }

    /// Fallback for launches where macOS doesn't create the main window (see
    /// `MainWindowLauncher`); runs after the menu bar label had its chance.
    public func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !MainWindowLauncher.hasMainWindow else { return }
            if !MainWindowLauncher.openFromWindowMenu() {
                Log.logger(.app).error("No main window at launch and no Window menu item to open it")
            }
        }
    }
}
