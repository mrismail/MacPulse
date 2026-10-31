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

    public init(systemInfo: any SystemInfoRepository, battery: any BatteryMonitoring) {
        self.systemInfo = systemInfo
        self.battery = battery
    }

    /// Real system services. Used by the shipping app.
    public static func live() -> AppDependencies {
        AppDependencies(
            systemInfo: LiveSystemInfoRepository(),
            battery: makeLiveBatteryMonitor()
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
                battery: PreviewBatteryMonitor()
            )
        }
    }
#endif

public enum LaunchArgument {
    public static let useFakeServices = "-MacPulseUseFakeServices"
}
