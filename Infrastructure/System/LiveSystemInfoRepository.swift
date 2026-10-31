import Darwin
import Foundation
import MacPulseDomain
import MacPulseShared

/// Reads system information through documented, sandbox-compatible APIs:
/// `ProcessInfo` and `sysctlbyname("hw.model")`. No special permissions required.
public struct LiveSystemInfoRepository: SystemInfoRepository {
    private let appVersion: String?
    private let appBuild: String?

    public init(bundle: Bundle = .main) {
        appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        appBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    public func currentSystemInfo() async throws -> SystemInfo {
        let processInfo = ProcessInfo.processInfo
        let os = processInfo.operatingSystemVersion
        let model = Self.sysctlString("hw.model")
        if model == nil {
            Log.logger(.system).notice("hw.model was not available from sysctl")
        }
        return SystemInfo(
            macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            hardwareModel: model,
            architecture: Self.currentArchitecture,
            processorCount: processInfo.processorCount,
            physicalMemoryBytes: processInfo.physicalMemory,
            appVersion: appVersion,
            appBuild: appBuild
        )
    }

    static var currentArchitecture: SystemInfo.Architecture {
        #if arch(arm64)
            return .appleSilicon
        #elseif arch(x86_64)
            // An x86_64 build can still run under Rosetta on Apple silicon.
            return isTranslated ? .appleSilicon : .intel
        #else
            return .unknown
        #endif
    }

    /// `true` when running under Rosetta 2.
    static var isTranslated: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("sysctl.proc_translated", &value, &size, nil, 0) == 0 else {
            return false
        }
        return value == 1
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let bytes = buffer.prefix { $0 != 0 }
        let string = String(decoding: bytes, as: UTF8.self)
        return string.isEmpty ? nil : string
    }
}
