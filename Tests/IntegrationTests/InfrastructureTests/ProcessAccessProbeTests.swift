import Foundation
import Testing
@testable import MacPulseInfrastructure

/// Runs unsandboxed (swift test), so it checks the probe itself works; the sandboxed
/// answer comes from running the signed app in CI (ADR-009).
@Suite("ProcessAccessProbe (integration)")
@MainActor
struct ProcessAccessProbeTests {
    @Test func reportsProcessAccessCounts() {
        let report = ProcessAccessProbe.run(sampleLimit: 50)
        #expect(report.listedProcessCount > 1)
        #expect(report.sysctlProcessCount > 1)
        #expect(report.hostCPULoadReadable)
        #expect(report.ownRusage.succeeded == 1)
        #expect(report.anyProcessRusage.tried > 0)
        #expect(!report.isSandboxed)
    }

    @Test func encodesOneLineWithoutProcessNames() throws {
        let line = ProcessAccessProbe.runAndEncode()
        #expect(line.hasPrefix(ProcessAccessProbe.outputPrefix))
        #expect(!line.contains("\n"))
        let json = Data(line.dropFirst(ProcessAccessProbe.outputPrefix.count).utf8)
        let decoded = try JSONDecoder().decode(ProcessAccessReport.self, from: json)
        #expect(decoded.listedProcessCount > 0)
        #expect(!line.contains("Finder"))
        #expect(!line.contains("/System/"))
    }
}
