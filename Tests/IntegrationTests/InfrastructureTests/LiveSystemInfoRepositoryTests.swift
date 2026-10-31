import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseInfrastructure

/// Runs against the real machine (CI runner or developer Mac).
@Suite("LiveSystemInfoRepository (integration)")
struct LiveSystemInfoRepositoryTests {
    @Test func readsRealSystemInformation() async throws {
        let info = try await LiveSystemInfoRepository().currentSystemInfo()

        let os = ProcessInfo.processInfo.operatingSystemVersion
        #expect(info.macOSVersion == "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        #expect(os.majorVersion >= 14)
        #expect(info.processorCount > 0)
        #expect(info.physicalMemoryBytes > 0)
        #expect(info.architecture != .unknown)

        let model = try #require(info.hardwareModel)
        #expect(!model.isEmpty)
        #expect(!model.contains("\0"))
    }

    @Test func unknownSysctlNameReturnsNil() {
        #expect(LiveSystemInfoRepository.sysctlString("macpulse.does.not.exist") == nil)
    }

    @Test func readsKnownSysctlString() {
        let osType = LiveSystemInfoRepository.sysctlString("kern.ostype")
        #expect(osType == "Darwin")
    }
}
