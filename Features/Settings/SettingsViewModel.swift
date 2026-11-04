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
    public private(set) var clearScanHistoryState: ClearHistoryState = .idle
    public private(set) var clearCleanupHistoryState: ClearHistoryState = .idle

    /// Saved preferences. Intervals and retention take effect at the next launch.
    public private(set) var preferences: AppPreferences
    /// What the running app uses (read at launch), to say when a restart is needed.
    public let preferencesAtLaunch: AppPreferences
    public private(set) var opensAtLogin = false
    public private(set) var loginItemError: AppError?

    /// `true` when a setting that applies at launch was changed.
    public var needsRestart: Bool {
        preferences.batteryInterval != preferencesAtLaunch.batteryInterval
            || preferences.activityInterval != preferencesAtLaunch.activityInterval
            || preferences.batteryRetentionDays != preferencesAtLaunch.batteryRetentionDays
            || preferences.usageRetentionDays != preferencesAtLaunch.usageRetentionDays
    }

    /// How long hourly app usage is kept before it is removed automatically.
    public var usageHistoryRetentionDays: Int { preferencesAtLaunch.usageRetentionDays }

    /// `false` when no app-usage monitor is available (the button is hidden).
    public var canClearUsageHistory: Bool { energyMonitor != nil }

    /// How long battery history is kept before it is removed automatically.
    public var batteryHistoryRetentionDays: Int { preferencesAtLaunch.batteryRetentionDays }

    public var canClearScanHistory: Bool { scanHistory != nil }
    public var canClearCleanupHistory: Bool { cleanupHistory != nil }

    /// How long the "History cleared" confirmation stays visible.
    @ObservationIgnored private let confirmationDuration: Duration

    @ObservationIgnored private let systemInfoRepository: any SystemInfoRepository
    @ObservationIgnored private let batteryMonitor: any BatteryMonitoring
    @ObservationIgnored private let energyMonitor: (any EnergyMonitoring)?
    @ObservationIgnored private let preferencesStore: any PreferencesStore
    @ObservationIgnored private let loginItem: any LoginItemControlling
    @ObservationIgnored private let scanHistory: (any ScanHistoryRepository)?
    @ObservationIgnored private let cleanupHistory: (any CleanupHistoryRepository)?

    public init(
        systemInfoRepository: any SystemInfoRepository,
        batteryMonitor: any BatteryMonitoring,
        energyMonitor: (any EnergyMonitoring)? = nil,
        preferences: any PreferencesStore = InMemoryPreferencesStore(),
        loginItem: any LoginItemControlling = InMemoryLoginItem(),
        scanHistory: (any ScanHistoryRepository)? = nil,
        cleanupHistory: (any CleanupHistoryRepository)? = nil,
        confirmationDuration: Duration = .seconds(3)
    ) {
        self.systemInfoRepository = systemInfoRepository
        self.batteryMonitor = batteryMonitor
        self.energyMonitor = energyMonitor
        preferencesStore = preferences
        self.loginItem = loginItem
        self.scanHistory = scanHistory
        self.cleanupHistory = cleanupHistory
        self.confirmationDuration = confirmationDuration
        let loaded = preferences.load()
        self.preferences = loaded
        preferencesAtLaunch = loaded
    }

    // MARK: Preferences

    /// Changes and saves preferences.
    public func update(_ change: (inout AppPreferences) -> Void) {
        var updated = preferences
        change(&updated)
        updated = updated.validated()
        guard updated != preferences else { return }
        preferences = updated
        preferencesStore.save(updated)
    }

    public func loadLoginItem() async {
        opensAtLogin = await loginItem.isEnabled()
    }

    /// Asks macOS to open MacPulse at login (or stop). macOS may ask the user to approve it.
    public func setOpensAtLogin(_ enabled: Bool) async {
        do {
            opensAtLogin = try await loginItem.setEnabled(enabled)
            loginItemError = nil
            if enabled, !opensAtLogin {
                loginItemError = AppError(
                    kind: .permissionDenied,
                    userMessage: String(localized: "macOS needs your approval: turn MacPulse on in System Settings > General > Login Items.")
                )
            }
        } catch {
            let appError = AppError.wrapping(error, userMessage: String(localized: "Couldn't change opening at login."))
            Log.logger(.app).log(appError, context: "Login item")
            loginItemError = appError
            opensAtLogin = await loginItem.isEnabled()
        }
    }

    // MARK: Scan and cleanup history

    public func clearScanHistory() async {
        guard let scanHistory, clearScanHistoryState != .clearing else { return }
        clearScanHistoryState = .clearing
        do {
            try await scanHistory.deleteAll()
            clearScanHistoryState = .cleared
            scheduleConfirmationHide()
        } catch {
            let appError = AppError.wrapping(error, userMessage: String(localized: "Couldn't clear scan history."))
            Log.logger(.persistence).log(appError, context: "Clear scan history")
            clearScanHistoryState = .failed(appError)
        }
    }

    /// Removes the record of past cleanups. Items already in the Trash stay there.
    public func clearCleanupHistory() async {
        guard let cleanupHistory, clearCleanupHistoryState != .clearing else { return }
        clearCleanupHistoryState = .clearing
        do {
            try await cleanupHistory.deleteAll()
            clearCleanupHistoryState = .cleared
            scheduleConfirmationHide()
        } catch {
            let appError = AppError.wrapping(error, userMessage: String(localized: "Couldn't clear cleanup history."))
            Log.logger(.persistence).log(appError, context: "Clear cleanup history")
            clearCleanupHistoryState = .failed(appError)
        }
    }

    private func hideClearedConfirmation() {
        if clearBatteryHistoryState == .cleared {
            clearBatteryHistoryState = .idle
        }
        if clearUsageHistoryState == .cleared {
            clearUsageHistoryState = .idle
        }
        if clearScanHistoryState == .cleared { clearScanHistoryState = .idle }
        if clearCleanupHistoryState == .cleared { clearCleanupHistoryState = .idle }
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
            let appError = AppError.wrapping(error, userMessage: String(localized: "Couldn't clear battery history."))
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
            let appError = AppError.wrapping(error, userMessage: String(localized: "Couldn't read diagnostics."))
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
