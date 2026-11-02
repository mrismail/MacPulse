import Foundation
import Testing
@testable import MacPulseDomain

@Suite("BackgroundGrouping")
struct BackgroundGroupingTests {
    typealias F = ProcessFixtures

    let firefox = F.usage("/Applications/Firefox.app", cpu: 19, bundle: "/Applications/Firefox.app", memory: 4_000, wakeups: 70, share: 0.5)
    let dock = F.usage("/System/Library/CoreServices/Dock.app", cpu: 1, bundle: "/System/Library/CoreServices/Dock.app", memory: 100, wakeups: 0, share: 0.03)
    let vm = F.usage("process:com.apple.Virtualization.VirtualMachine", cpu: 12, memory: 1_300, wakeups: 359, share: 0.3)

    @Test func foldsNonForegroundProcessesIntoOneRow() throws {
        let rows = BackgroundGrouping.fold([firefox, dock, vm], foregroundApps: ["/Applications/Firefox.app"], basis: .cpu)
        #expect(rows.count == 2)
        let group = try #require(rows.first { $0.id == BackgroundGrouping.groupID })
        #expect(group.isGroup)
        #expect(group.cpuPercent == 13)
        #expect(group.memoryBytes == 1_400)
        #expect(group.wakeupsPerSecond == 359)
        #expect(abs(group.shareOfActivity - 0.33) < 1e-9)
        #expect(group.processCount == 2)
        #expect(group.impact.value == .moderate)  // 13 % ≥ 10 % moderate threshold
        #expect(group.children?.map(\.id) == [vm.id, dock.id])  // ranked inside the group
        #expect(rows.contains { $0.id == firefox.id && !$0.isGroup })
    }

    @Test func groupIsRankedWithTheApps() throws {
        let busyVM = F.usage("process:vm", cpu: 80, share: 0.8)
        let rows = BackgroundGrouping.fold([firefox, busyVM], foregroundApps: ["/Applications/Firefox.app"], basis: .cpu)
        #expect(rows.first?.id == BackgroundGrouping.groupID)  // heavy background work stays on top
        #expect(rows.first?.impact.value == .high)
    }

    @Test func unknownForegroundAppsLeaveTheListUnchanged() {
        let apps = [firefox, dock, vm]
        #expect(BackgroundGrouping.fold(apps, foregroundApps: [], basis: .cpu) == apps)
    }

    @Test func noBackgroundMeansNoGroupRow() {
        let rows = BackgroundGrouping.fold([firefox], foregroundApps: ["/Applications/Firefox.app"], basis: .cpu)
        #expect(rows == [firefox])
    }

    @Test func flattenedIncludesTheGroupAndItsMembers() throws {
        let rows = BackgroundGrouping.fold([firefox, dock, vm], foregroundApps: ["/Applications/Firefox.app"], basis: .cpu)
        let group = try #require(rows.first { $0.isGroup })
        #expect(Set(group.flattened.map(\.id)) == [BackgroundGrouping.groupID, dock.id, vm.id])
    }
}
