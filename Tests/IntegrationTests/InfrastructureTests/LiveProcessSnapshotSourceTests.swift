import Darwin
import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseInfrastructure

/// Runs against the real machine (CI runner or developer Mac). Serialized because the
/// timing and CPU-burn tests would disturb each other in parallel.
@Suite("LiveProcessSnapshotSource (integration)", .serialized)
struct LiveProcessSnapshotSourceTests {
    @Test func readsOwnProcessAndSystemCPU() async throws {
        let source = LiveProcessSnapshotSource()
        let snapshot = await source.snapshot(at: Date())
        #expect(snapshot.ownPID == getpid())
        #expect(snapshot.processes.count > 1)
        #expect(snapshot.systemCPU != nil)
        #expect(snapshot.logicalCPUCount > 0)
        let own = try #require(snapshot.processes.first { $0.identity.pid == getpid() })
        #expect(own.cpuTimeNanoseconds > 0)
        #expect((own.residentBytes ?? 0) > 0)
        #expect(own.footprintBytes != nil)  // proc_pid_rusage works without the sandbox
        #expect(!own.name.isEmpty)
        #expect(snapshot.awakeUptime != nil)
        #expect(snapshot.memoryPressure != nil)
    }

    @Test func overheadBenchmarkProducesAReport() async {
        // The budget itself is checked in CI by running the Release app alone
        // (MACPULSE_DIAGNOSTICS=1 MacPulse --macpulse-overhead-benchmark): inside this
        // parallel test process other tests' CPU would be counted too.
        let report = await OverheadBenchmark.run(samples: 3)
        #expect(report.samples == 3)
        #expect(report.processCount > 0)
        #expect(report.cpuMillisecondsPerSample >= 0)
        #expect(OverheadBenchmark.encode(report).hasPrefix(OverheadBenchmark.outputPrefix))
    }

    @Test func cpuTimeGrowsWithWork() async throws {
        let source = LiveProcessSnapshotSource()
        let before = await source.snapshot(at: Date())
        // Burn ~100 ms of CPU.
        let deadline = Date().addingTimeInterval(0.1)
        var counter = 0.0
        while Date() < deadline { counter += sin(counter) + 1 }
        #expect(counter > 0)
        let after = await source.snapshot(at: Date())

        let activity = ProcessActivityCalculator.activity(from: before, to: after)
        let own = try #require(activity.first { $0.identity.pid == getpid() })
        #expect(own.cpuPercent > 10)
        #expect(own.cpuPercent < 100 * Double(ProcessInfo.processInfo.activeProcessorCount) + 1)
    }

    @Test func onlyCurrentUsersProcessesAreRead() async {
        let snapshot = await LiveProcessSnapshotSource().snapshot(at: Date())
        let table = ProcessTable.entries()
        let mine = Set(table.filter { $0.uid == getuid() }.map(\.pid))
        #expect(snapshot.processes.allSatisfy { mine.contains($0.identity.pid) })
        #expect(snapshot.unreadableProcessCount > 0)  // root daemons exist on every Mac
    }

    @Test func snapshotIsFastEnough() async {
        let source = LiveProcessSnapshotSource()
        _ = await source.snapshot(at: Date())  // warm the path cache, like the monitor does
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<5 {
            _ = await source.snapshot(at: Date())
        }
        let average = (clock.now - start) / 5
        #expect(average < .milliseconds(100), "Average snapshot took \(average)")
    }

    @Test func displayNameFallsBackToFolderNameWithoutReadingDisk() {
        #expect(LiveProcessSnapshotSource.folderName(of: "/Users/x/Downloads/Some Tool.app") == "Some Tool")
        #expect(LiveProcessSnapshotSource.folderName(of: "/Volumes/Disk/Tool") == "Tool")
    }

    @Test func machTimebaseConversion() {
        #expect(MachTimebase(numerator: 1, denominator: 1).nanoseconds(fromTicks: 1_000) == 1_000)
        #expect(MachTimebase.appleSiliconNative.nanoseconds(fromTicks: 3) == 125)
        // Apple silicon: 125/3 ns per tick.
        #expect(MachTimebase(numerator: 125, denominator: 3).nanoseconds(fromTicks: 24_000_000) == 1_000_000_000)
        #expect(MachTimebase.current.nanoseconds(fromTicks: 0) == 0)
    }

    @Test func processTableHasStartTimes() {
        let me = ProcessTable.entries().first { $0.pid == getpid() }
        #expect(me != nil)
        #expect((me?.startTimeMicroseconds ?? 0) > 1_600_000_000_000_000)  // after 2020
    }
}
