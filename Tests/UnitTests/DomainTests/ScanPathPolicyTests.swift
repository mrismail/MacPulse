import Foundation
import Testing
@testable import MacPulseDomain

@Suite("ScanPathPolicy")
struct ScanPathPolicyTests {
    let home = "/Users/test"

    @Test func systemLocationsAreSkipped() {
        let policy = ScanPathPolicy(homePath: home, approvedRoots: ["/"])
        #expect(policy.decision(forFolder: "/System/Library") == .skip(.systemLocation))
        #expect(policy.decision(forFolder: "/private/var/vm") == .skip(.systemLocation))
        #expect(policy.decision(forFolder: "/Volumes/Backup") == .skip(.systemLocation))
        #expect(policy.decision(forFolder: "/Applications") == .scan)
    }

    @Test func pickedVolumeIsScannedEvenUnderVolumes() {
        let policy = ScanPathPolicy(homePath: home, approvedRoots: ["/Volumes/Backup"])
        #expect(policy.decision(forFolder: "/Volumes/Backup/Photos") == .scan)
        #expect(policy.decision(forFolder: "/Volumes/Other") == .skip(.systemLocation))
    }

    @Test func protectedFoldersNeedAnExplicitPick() {
        let homeScan = ScanPathPolicy(homePath: home, approvedRoots: [home])
        #expect(homeScan.decision(forFolder: "\(home)/Documents") == .skip(.protectedByPrivacy))
        #expect(homeScan.decision(forFolder: "\(home)/Downloads/Movies") == .skip(.protectedByPrivacy))
        #expect(homeScan.decision(forFolder: "\(home)/Library/Containers/com.example") == .skip(.protectedByPrivacy))
        #expect(homeScan.decision(forFolder: "\(home)/Library/Caches") == .scan)
        #expect(homeScan.decision(forFolder: "\(home)/Movies") == .scan)

        let downloads = ScanPathPolicy(homePath: home, approvedRoots: ["\(home)/Downloads"])
        #expect(downloads.decision(forFolder: "\(home)/Downloads/Movies") == .scan)
        #expect(downloads.decision(forFolder: "\(home)/Documents") == .skip(.protectedByPrivacy))
    }

    @Test func approvingTheRootDoesNotApproveEverything() {
        let policy = ScanPathPolicy(homePath: home, approvedRoots: ["/"])
        #expect(policy.decision(forFolder: "\(home)/Desktop") == .skip(.protectedByPrivacy))
    }

    @Test func userExclusionsWinAndMatchWholeComponents() {
        let policy = ScanPathPolicy(homePath: home, userExclusions: ["\(home)/Movies/"], approvedRoots: [home])
        #expect(policy.decision(forFolder: "\(home)/Movies") == .skip(.excludedByUser))
        #expect(policy.decision(forFolder: "\(home)/Movies/Clips") == .skip(.excludedByUser))
        #expect(policy.decision(forFolder: "\(home)/Movies2") == .scan)
    }

    @Test func protectedFoldersMatchRegardlessOfCaseOrDataVolumePath() {
        let policy = ScanPathPolicy(homePath: home, approvedRoots: [home])
        #expect(policy.decision(forFolder: "\(home)/documents") == .skip(.protectedByPrivacy))
        #expect(policy.decision(forFolder: "/System/Volumes/Data\(home)/Documents") == .skip(.protectedByPrivacy))
        #expect(ScanPathPolicy.normalized("/System/Volumes/Data/Users/x") == "/Users/x")
        #expect(ScanPathPolicy.normalized("/System/Volumes/Data") == "/System/Volumes/Data")
    }

    @Test func pathContainmentIsComponentWise() {
        #expect(ScanPathPolicy.path("/a/b", isInside: "/a/b"))
        #expect(ScanPathPolicy.path("/a/b/c", isInside: "/a/b"))
        #expect(!ScanPathPolicy.path("/a/bc", isInside: "/a/b"))
        #expect(ScanPathPolicy.path("/anything", isInside: "/"))
        #expect(ScanPathPolicy.normalized("/a/b/../c/") == "/a/c")
    }
}

@Suite("VolumeInfo")
struct VolumeInfoTests {
    @Test func usedAndPurgeableComeFromReportedValues() {
        let volume = VolumeInfo(
            id: "1", name: "Macintosh HD", mountPath: "/", kind: .startup,
            totalBytes: .measured(1_000), availableBytes: .measured(200), availableForImportantUsageBytes: .measured(350)
        )
        #expect(volume.usedBytes == .measured(800))
        #expect(volume.purgeableBytes == .measured(150))
        #expect(volume.usedFraction == 0.8)
    }

    @Test func unknownCapacityIsUnavailable() {
        let volume = VolumeInfo(
            id: "n", name: "Share", mountPath: "/Volumes/Share", kind: .network,
            totalBytes: .unavailable(.notSupportedOnThisMac), availableBytes: .measured(1),
            availableForImportantUsageBytes: .unavailable(.notSupportedOnThisMac)
        )
        #expect(!volume.usedBytes.isAvailable)
        #expect(volume.usedFraction == nil)
    }
}
