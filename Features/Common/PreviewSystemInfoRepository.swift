import MacPulseDomain

/// Fixed system information for SwiftUI previews and UI tests.
public struct PreviewSystemInfoRepository: SystemInfoRepository {
    public init() {}

    public func currentSystemInfo() async throws -> SystemInfo {
        SystemInfo(
            macOSVersion: "14.5.0",
            hardwareModel: "MacBookPro18,3",
            architecture: .appleSilicon,
            processorCount: 10,
            physicalMemoryBytes: 16 * 1_073_741_824,
            appVersion: "0.1.0",
            appBuild: "1"
        )
    }
}
