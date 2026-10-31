import MacPulseDomain
import MacPulseShared
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public private(set) var systemInfo: LoadState<SystemInfo> = .idle

    public enum ClearHistoryState: Equatable, Sendable {
        case idle
        case clearing
        case cleared
        case failed(AppError)
    }

    public private(set) var clearBatteryHistoryState: ClearHistoryState = .idle

    /// How long battery history is kept before it is removed automatically.
    public let batteryHistoryRetentionDays = 30

    @ObservationIgnored private let systemInfoRepository: any SystemInfoRepository
    @ObservationIgnored private let batteryMonitor: any BatteryMonitoring

    public init(systemInfoRepository: any SystemInfoRepository, batteryMonitor: any BatteryMonitoring) {
        self.systemInfoRepository = systemInfoRepository
        self.batteryMonitor = batteryMonitor
    }

    /// Deletes all stored battery history. The view asks for confirmation first.
    public func clearBatteryHistory() async {
        guard clearBatteryHistoryState != .clearing else { return }
        clearBatteryHistoryState = .clearing
        do {
            try await batteryMonitor.clearHistory()
            clearBatteryHistoryState = .cleared
            Log.logger(.persistence).info("Battery history cleared by the user")
        } catch {
            let appError = AppError.wrapping(error, userMessage: "Couldn't clear battery history.")
            Log.logger(.persistence).error("\(appError.description, privacy: .public)")
            clearBatteryHistoryState = .failed(appError)
        }
    }

    public func load() async {
        guard !systemInfo.isLoading else { return }
        systemInfo = .loading
        do {
            systemInfo = .loaded(try await systemInfoRepository.currentSystemInfo())
        } catch {
            let appError = AppError.wrapping(error, userMessage: "Couldn't read diagnostics.")
            Log.logger(.system).error("Settings diagnostics failed: \(appError.description, privacy: .public)")
            systemInfo = .failed(appError)
        }
    }

    /// Plain-text diagnostics the user can copy into a support request.
    /// Contains no file names, paths or personal data.
    public var diagnosticsText: String? {
        guard let info = systemInfo.value else { return nil }
        return """
            MacPulse \(info.appVersionDescription)
            macOS \(info.macOSVersion)
            Model \(info.hardwareModel ?? "Unknown")
            Processor \(info.architectureDescription), \(info.processorCount) cores
            Memory \(info.memoryDescription)
            """
    }
}
