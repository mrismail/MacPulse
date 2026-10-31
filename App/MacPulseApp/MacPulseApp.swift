import MacPulseAppCore
import MacPulseShared
import SwiftUI

@main
struct MacPulseApp: App {
    @State private var coordinator = AppCoordinator()
    private let dependencies = AppDependencies.forLaunch(arguments: ProcessInfo.processInfo.arguments)

    init() {
        Log.logger(.app).info("MacPulse launched")
    }

    var body: some Scene {
        Window("MacPulse", id: "main") {
            RootView(coordinator: coordinator, dependencies: dependencies)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            MainCommands(coordinator: coordinator)
        }
    }
}
