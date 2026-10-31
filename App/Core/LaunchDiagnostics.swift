import Foundation
import MacPulseInfrastructure

/// Command-line diagnostics that run instead of the UI and exit.
///
/// `MACPULSE_DIAGNOSTICS=1 MacPulse --macpulse-process-access-probe` prints one JSON line
/// describing which process-information APIs work in this build — counts and error codes
/// only, no process names (ADR-009/010). Requiring both the environment variable and the
/// argument keeps it out of normal launches.
public enum LaunchDiagnostics {
    public static let environmentKey = "MACPULSE_DIAGNOSTICS"

    /// Returns `true` if a diagnostic ran and the app should exit.
    @MainActor
    public static func runIfRequested(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard environment[environmentKey] == "1",
              arguments.contains(ProcessAccessProbe.launchArgument)
        else { return false }
        let line = ProcessAccessProbe.runAndEncode() + "\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        return true
    }
}
