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

    /// Deterministic fake services. Used by previews and UI tests.
    public static func preview() -> AppDependencies {
        AppDependencies(
            systemInfo: PreviewSystemInfoRepository(),
            battery: PreviewBatteryMonitor()
        )
    }

    /// Chooses the container from launch arguments. UI tests launch the app with
    /// `-MacPulseUseFakeServices` so they never depend on the test machine's hardware.
    public static func forLaunch(arguments: [String]) -> AppDependencies {
        arguments.contains(LaunchArgument.useFakeServices) ? .preview() : .live()
    }

    private static func makeLiveBatteryMonitor() -> BatteryMonitor {
        let logger = Log.logger(.battery)
        let history: any BatteryHistoryRepository
        do {
            let directory = try JSONLinesBatteryHistoryStore.defaultDirectory()
            history = JSONLinesBatteryHistoryStore(directory: directory)
        } catch {
            logger.error("Battery history unavailable, keeping it in memory: \(String(describing: error), privacy: .public)")
            history = InMemoryBatteryHistoryRepository()
        }
        return BatteryMonitor(
            source: IOKitBatteryReadingSource(),
            history: history,
            powerEvents: IOKitPowerSourceEvents(),
            // Tolerance lets macOS coalesce the wake-up with other timers to save energy.
            sleep: { try await Task.sleep(for: $0, tolerance: .seconds(10)) },
            reportError: { error in
                Log.logger(.battery).error("\(error.description, privacy: .public)")
            }
        )
    }
}

public enum LaunchArgument {
    public static let useFakeServices = "-MacPulseUseFakeServices"
}
