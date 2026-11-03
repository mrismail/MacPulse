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
    /// The main window's scene identifier.
    public static let mainWindowID = "main"
    public let coordinator: AppCoordinator
    public let dependencies: AppDependencies
    public let overview: OverviewViewModel
    public let battery: BatteryViewModel
    public let energy: EnergyViewModel
    public let settings: SettingsViewModel
    public let spaceAnalyzer: SpaceAnalyzerViewModel
    public let duplicateFinder: DuplicateFinderViewModel
    public let cleaner: CleanerViewModel

    public init(dependencies: AppDependencies, coordinator: AppCoordinator = AppCoordinator()) {
        self.dependencies = dependencies
        self.coordinator = coordinator
        overview = OverviewViewModel(
            systemInfoRepository: dependencies.systemInfo,
            batteryMonitor: dependencies.battery,
            energyMonitor: dependencies.energy,
            volumes: dependencies.volumes,
            scanHistory: dependencies.scanHistory,
            cleanupHistory: dependencies.cleanupHistory
        )
        battery = BatteryViewModel(monitor: dependencies.battery)
        energy = EnergyViewModel(monitor: dependencies.energy)
        spaceAnalyzer = SpaceAnalyzerViewModel(
            volumes: dependencies.volumes,
            scanner: dependencies.scanner,
            history: dependencies.scanHistory,
            settings: dependencies.scanSettings
        )
        let scanSettings = dependencies.scanSettings
        duplicateFinder = DuplicateFinderViewModel(
            finder: dependencies.duplicates,
            exclusions: { scanSettings.loadExclusions() }
        )
        cleaner = CleanerViewModel(
            source: dependencies.cleanupSource,
            trash: dependencies.trash,
            history: dependencies.cleanupHistory
        )
        settings = SettingsViewModel(
            systemInfoRepository: dependencies.systemInfo,
            batteryMonitor: dependencies.battery,
            energyMonitor: dependencies.energy,
            preferences: dependencies.preferences,
            loginItem: dependencies.loginItem,
            scanHistory: dependencies.scanHistory,
            cleanupHistory: dependencies.cleanupHistory
        )
        let spaceAnalyzer = self.spaceAnalyzer
        let duplicateFinder = self.duplicateFinder
        let overview = self.overview
        let settings = self.settings
        cleaner.connect(
            largeFiles: { spaceAnalyzer.largeFilesForCleanup },
            duplicates: { duplicateFinder.markedCopies },
            exclusions: { scanSettings.loadExclusions() },
            ageDays: (
                get: { settings.preferences.cleanupDownloadsAgeDays },
                set: { days in settings.update { $0.cleanupDownloadsAgeDays = days } }
            ),
            didClean: { report in
                // Storage refresh: free space, history and the other screens' results.
                let moved = Set(report.moved.map(\.path))
                duplicateFinder.forget(moved)
                spaceAnalyzer.forget(moved)
                await spaceAnalyzer.loadVolumes()
                await overview.loadStorage()
            }
        )
    }

    /// Opens a screen from the menu bar companion.
    public func open(_ destination: MenuBarDestination) {
        switch destination {
        case .overview: coordinator.select(.overview)
        case .battery: coordinator.select(.battery)
        case .energy: coordinator.select(.energy)
        case .spaceAnalyzer: coordinator.select(.spaceAnalyzer)
        }
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
