import Foundation
import MacPulseInfrastructure

/// Command-line diagnostics that run instead of the UI and exit.
///
/// `MacPulse --macpulse-process-access-probe` prints one JSON line describing which
/// process-information APIs work in this (sandboxed) build — counts and error codes
/// only, no process names. Used by CI and for the Phase 3 sandbox spike (ADR-009).
public enum LaunchDiagnostics {
    /// Returns `true` if a diagnostic ran and the app should exit.
    @MainActor
    public static func runIfRequested(arguments: [String]) -> Bool {
        guard arguments.contains(ProcessAccessProbe.launchArgument) else { return false }
        let line = ProcessAccessProbe.runAndEncode() + "\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        return true
    }
}
