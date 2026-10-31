import Testing
@testable import MacPulseDomain

@Suite("SystemInfo")
struct SystemInfoTests {
    private func info(model: String?) -> SystemInfo {
        SystemInfo(
            macOSVersion: "14.5.0",
            hardwareModel: model,
            architecture: .intel,
            processorCount: 8,
            physicalMemoryBytes: 0,
            appVersion: nil,
            appBuild: nil
        )
    }

    @Test func macBookModelsAreLikelyPortable() {
        #expect(info(model: "MacBookPro16,1").isLikelyPortable)
        #expect(info(model: "MacBookAir10,1").isLikelyPortable)
    }

    @Test func desktopAndUnknownModelsAreNotPortable() {
        #expect(!info(model: "Macmini9,1").isLikelyPortable)
        #expect(!info(model: "iMac21,1").isLikelyPortable)
        #expect(!info(model: nil).isLikelyPortable)
    }
}
