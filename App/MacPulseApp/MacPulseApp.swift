import MacPulseAppCore
import MacPulseFeatures
import MacPulseShared
import SwiftUI

@main
struct MacPulseApp: App {
    @State private var model = AppModel(
        dependencies: AppDependencies.forLaunch(arguments: ProcessInfo.processInfo.arguments)
    )

    init() {
        if LaunchDiagnostics.runIfRequested(arguments: ProcessInfo.processInfo.arguments) {
            exit(0)
        }
        Log.logger(.app).info("MacPulse launched")
    }

    var body: some Scene {
        Window("MacPulse", id: "main") {
            RootView(model: model)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            MainCommands(coordinator: model.coordinator)
        }

        // ⌘, opens the same settings that are also in the sidebar.
        Settings {
            SettingsView(viewModel: model.settings)
                .frame(width: 560, height: 520)
        }
    }
}
