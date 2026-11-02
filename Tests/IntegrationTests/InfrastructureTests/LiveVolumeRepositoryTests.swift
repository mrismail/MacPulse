import Foundation
import MacPulseDomain
@testable import MacPulseInfrastructure
import Testing

@Suite("LiveVolumeRepository")
struct LiveVolumeRepositoryTests {
    @Test func startupDiskIsListedFirstWithMeasuredCapacity() async throws {
        let volumes = try await LiveVolumeRepository().volumes()
        let startup = try #require(volumes.first)
        #expect(startup.kind == .startup)
        #expect(startup.mountPath == "/")
        #expect((startup.totalBytes.value ?? 0) > 0)
        #expect(startup.totalBytes.isMeasured)
        #expect(startup.availableBytes.isAvailable)
        #expect((startup.usedFraction ?? -1) > 0)
        #expect(volumes.filter { $0.kind == .startup }.count == 1)
    }
}
