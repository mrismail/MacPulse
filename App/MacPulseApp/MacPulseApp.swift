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
        }

        // The menu bar companion (ADR-016); turned on or off in Settings.
        MenuBarExtra(isInserted: Binding(
            get: { model.settings.preferences.showsMenuBarExtra },
            set: { shown in model.settings.update { $0.showsMenuBarExtra = shown } }
        )) {
            MenuBarContent(model: model)
        } label: {
            MenuBarLabel(overview: model.overview)
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
