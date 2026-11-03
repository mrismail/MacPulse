import Foundation
import MacPulseDomain
import MacPulseFeatures
import MacPulseInfrastructure
import MacPulseShared

/// The dependency container and composition root.
///
/// Features receive only the Domain protocols they need, through their view model
/// initializers. This is the one place that knows which concrete implementation backs
/// each protocol.
public struct AppDependencies: Sendable {
    public let systemInfo: any SystemInfoRepository
    public let battery: any BatteryMonitoring
    public let energy: any EnergyMonitoring
    public let volumes: any VolumeRepository
    public let scanner: any FileSystemScanning
    public let scanHistory: any ScanHistoryRepository
    public let scanSettings: any ScanSettingsStore
    public let duplicates: any DuplicateScanning
    public let cleanupSource: any CleanupCandidateSource
    public let trash: any TrashService
    public let cleanupHistory: any CleanupHistoryRepository

    public init(
        systemInfo: any SystemInfoRepository,
        battery: any BatteryMonitoring,
        energy: any EnergyMonitoring,
        volumes: any VolumeRepository,
        scanner: any FileSystemScanning,
        scanHistory: any ScanHistoryRepository = InMemoryScanHistory(),
        scanSettings: any ScanSettingsStore = InMemoryScanSettingsStore(),
        duplicates: any DuplicateScanning,
        cleanupSource: any CleanupCandidateSource,
        trash: any TrashService,
        cleanupHistory: any CleanupHistoryRepository = InMemoryCleanupHistory()
    ) {
        self.systemInfo = systemInfo
        self.battery = battery
        self.energy = energy
        self.volumes = volumes
        self.scanner = scanner
        self.scanHistory = scanHistory
        self.scanSettings = scanSettings
        self.duplicates = duplicates
        self.cleanupSource = cleanupSource
        self.trash = trash
        self.cleanupHistory = cleanupHistory
    }

    /// Real system services. Used by the shipping app.
    public static func live() -> AppDependencies {
        let battery = makeLiveBatteryMonitor()
        return AppDependencies(
            systemInfo: LiveSystemInfoRepository(),
            battery: battery,
            energy: makeLiveProcessMonitor(battery: battery),
            volumes: LiveVolumeRepository(),
            scanner: FileSystemScanner(),
            scanHistory: makeLiveScanHistory(),
            scanSettings: UserDefaultsScanSettingsStore(),
            duplicates: DuplicateFinder(),
            cleanupSource: LiveCleanupCandidateSource(),
            trash: FileManagerTrashService(),
            cleanupHistory: makeLiveCleanupHistory()
        )
    }

    /// Chooses the container from launch arguments. In Debug builds, UI tests launch the
    /// app with `-MacPulseUseFakeServices` so they never depend on the test machine's
    /// hardware. Release builds always use live services.
    public static func forLaunch(arguments: [String]) -> AppDependencies {
        #if DEBUG
            if arguments.contains(LaunchArgument.useFakeServices) {
                return .preview()
            }
        #endif
        return .live()
    }

    private static func makeLiveCleanupHistory() -> any CleanupHistoryRepository {
        do {
            return JSONLinesCleanupHistoryStore(directory: try JSONLinesCleanupHistoryStore.defaultDirectory())
        } catch {
            Log.logger(.persistence).log(
                AppError.wrapping(error, userMessage: "Cleanup history can't be saved."),
                context: "Cleanup history store"
            )
            return InMemoryCleanupHistory()
        }
    }

    private static func makeLiveScanHistory() -> any ScanHistoryRepository {
        do {
            return JSONLinesScanHistoryStore(directory: try JSONLinesScanHistoryStore.defaultDirectory())
        } catch {
            Log.logger(.persistence).log(
                AppError.wrapping(error, userMessage: "Scan history can't be saved."),
                context: "Scan history store"
            )
            return InMemoryScanHistory()
        }
    }

    private static func makeLiveBatteryMonitor() -> BatteryMonitor {
        let logger = Log.logger(.battery)
        let history: any BatteryHistoryRepository
        var isPersistent = true
        do {
            let directory = try JSONLinesBatteryHistoryStore.defaultDirectory()
            history = JSONLinesBatteryHistoryStore(directory: directory)
        } catch {
            logger.log(
                AppError.wrapping(error, userMessage: "Battery history can't be saved."),
                context: "Battery history store"
            )
            history = InMemoryBatteryHistoryRepository()
            isPersistent = false
        }
        return BatteryMonitor(
            source: IOKitBatteryReadingSource(),
            history: history,
            powerEvents: IOKitPowerSourceEvents(),
            configuration: .init(historyIsPersistent: isPersistent),
            // Tolerance lets macOS coalesce the wake-up with other timers to save energy.
            sleep: { try await Task.sleep(for: $0, tolerance: .seconds(10)) },
            reportError: { error in
                Log.logger(.battery).log(error, context: "Battery monitor")
            }
        )
    }
}

#if DEBUG
    extension AppDependencies {
        /// Deterministic fake services. Used by previews and UI tests (Debug only).
        public static func preview() -> AppDependencies {
            AppDependencies(
                systemInfo: PreviewSystemInfoRepository(),
                battery: PreviewBatteryMonitor(),
                energy: PreviewEnergyMonitor(),
                volumes: PreviewVolumeRepository(),
                scanner: PreviewScanner(),
                duplicates: PreviewDuplicateFinder(),
                cleanupSource: PreviewCleanupSource(),
                trash: PreviewTrashService()
            )
        }
    }
#endif

extension AppDependencies {
    fileprivate static func makeLiveProcessMonitor(battery: BatteryMonitor) -> ProcessMonitor {
        let history: any AppUsageHistoryRepository
        var configuration = ProcessMonitor.Configuration()
        do {
            history = JSONLinesAppUsageStore(directory: try JSONLinesAppUsageStore.defaultDirectory())
        } catch {
            Log.logger(.energy).log(
                AppError.wrapping(error, userMessage: "App usage history can't be saved."),
                context: "Usage history store"
            )
            history = InMemoryAppUsageHistory()
            configuration.historyIsPersistent = false
        }
        return ProcessMonitor(
            source: LiveProcessSnapshotSource(),
            history: history,
            settingsStore: UserDefaultsDrainAlertSettingsStore(),
            notifier: UserNotificationDrainNotifier(),
            powerState: {
                await battery.latestStatus?.reading.powerSource.value.map { $0 == .battery }
            },
            configuration: configuration,
            // Tolerance lets macOS coalesce the wake-up with other timers to save energy.
            sleep: { try await Task.sleep(for: $0, tolerance: .seconds(5)) },
            reportError: { error in
                Log.logger(.energy).log(error, context: "Process monitor")
            }
        )
    }
}

public enum LaunchArgument {
    public static let useFakeServices = "-MacPulseUseFakeServices"
}
