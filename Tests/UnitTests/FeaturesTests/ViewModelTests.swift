import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseFeatures

/// Test double with a configurable result and a call counter.
final class StubSystemInfoRepository: SystemInfoRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    private let result: Result<SystemInfo, any Error>

    init(result: Result<SystemInfo, any Error>) {
        self.result = result
    }

    var callCount: Int {
        lock.withLock { _callCount }
    }

    func currentSystemInfo() async throws -> SystemInfo {
        lock.withLock { _callCount += 1 }
        return try result.get()
    }
}

let sampleInfo = SystemInfo(
    macOSVersion: "14.6.1",
    hardwareModel: "MacBookPro16,1",
    architecture: .intel,
    processorCount: 8,
    physicalMemoryBytes: 16 * 1_073_741_824,
    appVersion: "0.1.0",
    appBuild: "7"
)

@Suite("OverviewViewModel")
@MainActor
struct OverviewViewModelTests {
    @Test func startsIdleWithUnavailablePlaceholders() {
        let model = OverviewViewModel(systemInfoRepository: StubSystemInfoRepository(result: .success(sampleInfo)), batteryMonitor: PreviewBatteryMonitor())
        #expect(model.systemInfo == .idle)
        #expect(!model.batteryCharge.isAvailable)
        #expect(!model.estimatedRuntimeMinutes.isAvailable)
        #expect(!model.storageAvailableBytes.isAvailable)
        #expect(!model.reclaimableBytes.isAvailable)
        #expect(model.batteryCharge.provenance == .unavailable(.notYetSampled))
        #expect(model.storageAvailableBytes.provenance == .unavailable(.notYetImplemented))
    }

    @Test func loadsSystemInfo() async {
        let repo = StubSystemInfoRepository(result: .success(sampleInfo))
        let model = OverviewViewModel(systemInfoRepository: repo, batteryMonitor: PreviewBatteryMonitor())
        await model.load()
        #expect(model.systemInfo == .loaded(sampleInfo))
        #expect(repo.callCount == 1)
    }

    @Test func mapsFailureToAppError() async {
        let repo = StubSystemInfoRepository(result: .failure(POSIXError(.EACCES)))
        let model = OverviewViewModel(systemInfoRepository: repo, batteryMonitor: PreviewBatteryMonitor())
        await model.load()
        #expect(model.systemInfo.error?.kind == .permissionDenied)
        #expect(model.systemInfo.error?.userMessage == "Couldn't read information about this Mac.")
    }

    @Test func listsUpcomingFeaturesInPhaseOrder() {
        let model = OverviewViewModel(systemInfoRepository: StubSystemInfoRepository(result: .success(sampleInfo)), batteryMonitor: PreviewBatteryMonitor())
        let phases = model.upcomingFeatures.map(\.phase)
        #expect(phases == phases.sorted())
        #expect(phases.count == 3)
        #expect(!model.upcomingFeatures.contains { $0.title == "Battery" || $0.title == "Energy" })
    }
}

@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {
    @Test func diagnosticsAreNilBeforeLoading() {
        let model = SettingsViewModel(systemInfoRepository: StubSystemInfoRepository(result: .success(sampleInfo)), batteryMonitor: PreviewBatteryMonitor())
        #expect(model.diagnosticsText == nil)
    }

    @Test func diagnosticsContainSystemFactsOnly() async throws {
        let model = SettingsViewModel(systemInfoRepository: StubSystemInfoRepository(result: .success(sampleInfo)), batteryMonitor: PreviewBatteryMonitor())
        await model.load()
        let text = try #require(model.diagnosticsText)
        #expect(text.contains("MacPulse 0.1.0 (7)"))
        #expect(text.contains("macOS 14.6.1"))
        #expect(text.contains("MacBookPro16,1"))
        #expect(text.contains("Intel, 8 cores"))
        #expect(text.contains("16 GB"))
        #expect(!text.contains("/"))  // no file paths
    }

    @Test func failureLeavesNoDiagnostics() async {
        let repo = StubSystemInfoRepository(result: .failure(CocoaError(.fileReadUnknown)))
        let model = SettingsViewModel(systemInfoRepository: repo, batteryMonitor: PreviewBatteryMonitor())
        await model.load()
        #expect(model.systemInfo.error != nil)
        #expect(model.diagnosticsText == nil)
    }
}

@Suite("SystemInfo display")
struct SystemInfoDisplayTests {
    @Test func versionDescriptionCombinations() {
        func info(_ version: String?, _ build: String?) -> SystemInfo {
            SystemInfo(
                macOSVersion: "14.0.0", hardwareModel: nil, architecture: .unknown,
                processorCount: 1, physicalMemoryBytes: 0, appVersion: version, appBuild: build
            )
        }
        #expect(info("1.0", "3").appVersionDescription == "1.0 (3)")
        #expect(info("1.0", nil).appVersionDescription == "1.0")
        #expect(info(nil, "3").appVersionDescription == "Build 3")
        #expect(info(nil, nil).appVersionDescription == "Unknown")
    }

    @Test func memoryUsesBinaryGigabytes() {
        #expect(sampleInfo.memoryDescription == "16 GB")
    }

    @Test func architectureNames() {
        #expect(sampleInfo.architectureDescription == "Intel")
    }
}
