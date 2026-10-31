import MacPulseDomain
import MacPulseShared

/// Display strings for `SystemInfo`, shared by Overview and Settings.
extension SystemInfo {
    public var architectureDescription: String {
        switch architecture {
        case .appleSilicon: "Apple silicon"
        case .intel: "Intel"
        case .unknown: "Unknown"
        }
    }

    /// Memory is shown in binary units, the way "About This Mac" does ("16 GB" for 16 GiB).
    public var memoryDescription: String {
        let gibibytes = Double(physicalMemoryBytes) / 1_073_741_824
        return "\(Int(gibibytes.rounded())) GB"
    }

    public var appVersionDescription: String {
        switch (appVersion, appBuild) {
        case let (version?, build?): "\(version) (\(build))"
        case let (version?, nil): version
        case let (nil, build?): "Build \(build)"
        case (nil, nil): "Unknown"
        }
    }
}
