import Foundation

/// Provides basic information about the Mac and the app build.
public protocol SystemInfoRepository: Sendable {
    func currentSystemInfo() async throws -> SystemInfo
}
