import MacPulseDomain
import MacPulseFeatures
import Observation

/// App-wide state, created once per launch and held by `MacPulseApp`.
///
/// Owns navigation and every screen's view model, so they are created exactly once and
/// shared by the main window, the Settings window and menu commands.
@MainActor
@Observable
public final class AppModel {
    public let coordinator: AppCoordinator
    public let dependencies: AppDependencies
    public let overview: OverviewViewModel
    public let battery: BatteryViewModel
    public let settings: SettingsViewModel

    public init(dependencies: AppDependencies, coordinator: AppCoordinator = AppCoordinator()) {
        self.dependencies = dependencies
        self.coordinator = coordinator
        overview = OverviewViewModel(
            systemInfoRepository: dependencies.systemInfo,
            batteryMonitor: dependencies.battery
        )
        battery = BatteryViewModel(monitor: dependencies.battery)
        settings = SettingsViewModel(
            systemInfoRepository: dependencies.systemInfo,
            batteryMonitor: dependencies.battery
        )
    }

    /// Starts background services. Battery sampling runs for the life of the app,
    /// whichever section is shown.
    public func start() async {
        await dependencies.battery.start()
    }
}
