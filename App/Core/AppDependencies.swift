import MacPulseDomain
import MacPulseFeatures
import MacPulseInfrastructure

/// The dependency container and composition root.
///
/// Features receive only the Domain protocols they need, through their view model
/// initializers. This is the one place that knows which concrete implementation backs
/// each protocol. Later phases add battery, process, filesystem, duplicate, cleanup and
/// persistence services here.
public struct AppDependencies: Sendable {
    public let systemInfo: any SystemInfoRepository

    public init(systemInfo: any SystemInfoRepository) {
        self.systemInfo = systemInfo
    }

    /// Real system services. Used by the shipping app.
    public static func live() -> AppDependencies {
        AppDependencies(systemInfo: LiveSystemInfoRepository())
    }

    /// Deterministic fake services. Used by previews and UI tests.
    public static func preview() -> AppDependencies {
        AppDependencies(systemInfo: PreviewSystemInfoRepository())
    }

    /// Chooses the container from launch arguments. UI tests launch the app with
    /// `-MacPulseUseFakeServices` so they never depend on the test machine's hardware.
    public static func forLaunch(arguments: [String]) -> AppDependencies {
        arguments.contains(LaunchArgument.useFakeServices) ? .preview() : .live()
    }
}

public enum LaunchArgument {
    public static let useFakeServices = "-MacPulseUseFakeServices"
}
