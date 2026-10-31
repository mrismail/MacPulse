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
        guard environment[environmentKey] == "1" else { return false }
        if arguments.contains(ProcessAccessProbe.launchArgument) {
            write(ProcessAccessProbe.runAndEncode())
            return true
        }
        if arguments.contains(OverheadBenchmark.launchArgument) {
            write(OverheadBenchmark.encode(runToCompletion { await OverheadBenchmark.run() }))
            return true
        }
        return false
    }

    private static func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    /// Runs async work from the synchronous app initializer. The main run loop keeps
    /// spinning so work that hops to the main actor can still run.
    @MainActor
    private static func runToCompletion<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> T {
        let box = ResultBox<T>()
        Task.detached { box.set(await work()) }
        while box.value == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return box.value!
    }
}

private final class ResultBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    var value: T? { lock.withLock { stored } }
    func set(_ value: T) { lock.withLock { stored = value } }
}
