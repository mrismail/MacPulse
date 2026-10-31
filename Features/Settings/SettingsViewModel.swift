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
    public private(set) var clearUsageHistoryState: ClearHistoryState = .idle

    /// How long hourly app usage is kept before it is removed automatically.
    public let usageHistoryRetentionDays = ProcessMonitor.Configuration.defaultHistoryRetentionDays

    /// `false` when no app-usage monitor is available (the button is hidden).
    public var canClearUsageHistory: Bool { energyMonitor != nil }

    /// How long battery history is kept before it is removed automatically.
    public let batteryHistoryRetentionDays = BatteryMonitor.Configuration.defaultHistoryRetentionDays

    /// How long the "History cleared" confirmation stays visible.
    @ObservationIgnored private let confirmationDuration: Duration

    @ObservationIgnored private let systemInfoRepository: any SystemInfoRepository
    @ObservationIgnored private let batteryMonitor: any BatteryMonitoring
    @ObservationIgnored private let energyMonitor: (any EnergyMonitoring)?

    public init(
        systemInfoRepository: any SystemInfoRepository,
        batteryMonitor: any BatteryMonitoring,
        energyMonitor: (any EnergyMonitoring)? = nil,
        confirmationDuration: Duration = .seconds(3)
    ) {
        self.systemInfoRepository = systemInfoRepository
        self.batteryMonitor = batteryMonitor
        self.energyMonitor = energyMonitor
        self.confirmationDuration = confirmationDuration
    }

    private func hideClearedConfirmation() {
        if clearBatteryHistoryState == .cleared {
            clearBatteryHistoryState = .idle
        }
        if clearUsageHistoryState == .cleared {
            clearUsageHistoryState = .idle
        }
    }

    private func scheduleConfirmationHide() {
        let duration = confirmationDuration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            self?.hideClearedConfirmation()
        }
    }

    /// Deletes all stored hourly app usage. The view asks for confirmation first.
    public func clearUsageHistory() async {
        guard let energyMonitor, clearUsageHistoryState != .clearing else { return }
        clearUsageHistoryState = .clearing
        do {
            try await energyMonitor.clearHistory()
            clearUsageHistoryState = .cleared
            Log.logger(.persistence).info("App usage history cleared by the user")
            scheduleConfirmationHide()
        } catch {
            let appError = AppError.wrapping(error, userMessage: String(localized: "Couldn't clear app usage history."))
            Log.logger(.persistence).log(appError, context: "Clear usage history")
            clearUsageHistoryState = .failed(appError)
        }
    }

    /// Deletes all stored battery history. The view asks for confirmation first.

    public func clearBatteryHistory() async {
        guard clearBatteryHistoryState != .clearing else { return }
        clearBatteryHistoryState = .clearing
        do {
            try await batteryMonitor.clearHistory()
            clearBatteryHistoryState = .cleared
            Log.logger(.persistence).info("Battery history cleared by the user")
            scheduleConfirmationHide()
        } catch {
            let appError = AppError.wrapping(error, userMessage: "Couldn't clear battery history.")
            Log.logger(.persistence).log(appError, context: "Clear battery history")
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
            Log.logger(.system).log(appError, context: "Settings diagnostics")
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
