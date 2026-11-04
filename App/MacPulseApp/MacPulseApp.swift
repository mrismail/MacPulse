import MacPulseAppCore
import MacPulseFeatures
import MacPulseShared
import SwiftUI

@main
struct MacPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        // Diagnostics run before any live service (monitors, stores) is created.
        if LaunchDiagnostics.runIfRequested(arguments: ProcessInfo.processInfo.arguments) {
            exit(0)
        }
        _model = State(initialValue: AppModel(
            dependencies: AppDependencies.forLaunch(arguments: ProcessInfo.processInfo.arguments)
        ))
        Log.logger(.app).info("MacPulse launched")
    }

    var body: some Scene {
        Window("MacPulse", id: AppModel.mainWindowID) {
            RootView(model: model)
                .frame(minWidth: 860, minHeight: 560)
                .environment(\.layoutDirection, AppLanguage.layoutDirection)
                .task {
                    let settings = model.settings
                    appDelegate.keepsRunningWithoutWindows = { settings.preferences.showsMenuBarExtra }
                }
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            MainCommands(coordinator: model.coordinator)
        }

        // ⌘, opens the same settings that are also in the sidebar.
        Settings {
            SettingsView(viewModel: model.settings, energy: model.energy, spaceAnalyzer: model.spaceAnalyzer)
                .frame(width: 600, height: 640)
                .environment(\.layoutDirection, AppLanguage.layoutDirection)
        }

        // The menu bar companion (ADR-016); turned on or off in Settings.
        MenuBarExtra(isInserted: Binding(
            get: { model.settings.preferences.showsMenuBarExtra },
            set: { shown in model.settings.update { $0.showsMenuBarExtra = shown } }
        )) {
            MenuBarContent(model: model)
                .environment(\.layoutDirection, AppLanguage.layoutDirection)
        } label: {
            MenuBarLabel(overview: model.overview)
                .modifier(OpenMainWindowAtLaunch())
        }
        .menuBarExtraStyle(.window)
    }
}

/// Opens the main window on the chosen screen.
private struct MenuBarContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarView(overview: model.overview) { destination in
            model.open(destination)
            openWindow(id: AppModel.mainWindowID)
            NSApplication.shared.activate()
        }
    }
}

/// Makes sure the main window is shown at launch. CI showed that in a right-to-left
/// layout (Arabic) macOS 15 starts MacPulse with no window at all, only the menu bar item;
/// the menu bar label is drawn at launch, so it opens the window if none is visible.
private struct OpenMainWindowAtLaunch: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @MainActor private static var checked = false

    func body(content: Content) -> some View {
        content.task {
            guard !Self.checked else { return }
            Self.checked = true
            try? await Task.sleep(for: .milliseconds(500))
            let hasWindow = NSApplication.shared.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
            if !hasWindow {
                openWindow(id: AppModel.mainWindowID)
            }
        }
    }
}

/// The language MacPulse shows (the first of the user's languages it is localized in) and
/// its writing direction. CI showed the window laid out left to right in Arabic, although
/// the text was Arabic, so the direction is set from the app's language explicitly.
enum AppLanguage {
    static let layoutDirection: LayoutDirection = {
        let language = Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }()
}
