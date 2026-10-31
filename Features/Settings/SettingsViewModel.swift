import MacPulseDomain
import MacPulseShared
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public private(set) var systemInfo: LoadState<SystemInfo> = .idle

    @ObservationIgnored private let systemInfoRepository: any SystemInfoRepository

    public init(systemInfoRepository: any SystemInfoRepository) {
        self.systemInfoRepository = systemInfoRepository
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
