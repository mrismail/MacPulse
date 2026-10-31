import AppKit
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
    public let energy: EnergyViewModel
    public let settings: SettingsViewModel

    public init(dependencies: AppDependencies, coordinator: AppCoordinator = AppCoordinator()) {
        self.dependencies = dependencies
        self.coordinator = coordinator
        overview = OverviewViewModel(
            systemInfoRepository: dependencies.systemInfo,
            batteryMonitor: dependencies.battery,
            energyMonitor: dependencies.energy
        )
        battery = BatteryViewModel(monitor: dependencies.battery)
        energy = EnergyViewModel(monitor: dependencies.energy)
        settings = SettingsViewModel(
            systemInfoRepository: dependencies.systemInfo,
            batteryMonitor: dependencies.battery,
            energyMonitor: dependencies.energy
        )
    }

    /// Starts background services. Battery and process sampling run for the life of
    /// the app, whichever section is shown.
    public func start() async {
        await dependencies.battery.start()
        await dependencies.energy.start()
        observeLifecycle()
    }

    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []

    /// Saves in-memory usage when the app quits or the Mac goes to sleep.
    private func observeLifecycle() {
        guard lifecycleObservers.isEmpty else { return }
        let energy = dependencies.energy
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            // Termination doesn't wait for async work; give the save up to one second.
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await energy.flush()
                done.signal()
            }
            _ = done.wait(timeout: .now() + 1)
        })
        lifecycleObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { _ in
            Task { await energy.flush() }
        })
    }
}
