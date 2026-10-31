import MacPulseDomain
import MacPulseInfrastructure
import Testing
@testable import MacPulseAppCore

@Suite("SidebarSection")
struct SidebarSectionTests {
    @Test func containsTheSevenSpecifiedSectionsInOrder() {
        #expect(SidebarSection.allCases.map(\.title) == [
            "Overview", "Battery", "Energy", "Space Analyzer", "Duplicate Finder", "Cleaner", "Settings",
        ])
    }

    @Test func everySectionAppearsInExactlyOneGroup() {
        let grouped = SidebarGroup.allCases.flatMap(\.sections)
        #expect(grouped.count == SidebarSection.allCases.count)
        #expect(Set(grouped) == Set(SidebarSection.allCases))
    }

    @Test func groupOrderMatchesSectionOrder() {
        #expect(SidebarGroup.allCases.flatMap(\.sections) == SidebarSection.allCases)
    }

    @Test func shortcutsAreUniqueDigitsOneToSeven() {
        let digits = SidebarSection.allCases.map(\.shortcutDigit)
        #expect(digits == ["1", "2", "3", "4", "5", "6", "7"])
    }

    @Test func identifiersAndIconsAreUnique() {
        let ids = SidebarSection.allCases.map(\.accessibilityIdentifier)
        let icons = SidebarSection.allCases.map(\.systemImage)
        #expect(Set(ids).count == ids.count)
        #expect(Set(icons).count == icons.count)
    }
}

@Suite("AppCoordinator")
@MainActor
struct AppCoordinatorTests {
    @Test func startsOnOverview() {
        #expect(AppCoordinator().selection == .overview)
        #expect(AppCoordinator(initialSelection: .cleaner).selection == .cleaner)
    }

    @Test func selectChangesSelection() {
        let coordinator = AppCoordinator()
        coordinator.select(.spaceAnalyzer)
        #expect(coordinator.selection == .spaceAnalyzer)
        #expect(coordinator.effectiveSelection == .spaceAnalyzer)
    }

    @Test func clearedSelectionFallsBackToOverview() {
        let coordinator = AppCoordinator(initialSelection: .battery)
        coordinator.selection = nil
        #expect(coordinator.effectiveSelection == .overview)
    }
}

@Suite("AppDependencies")
struct AppDependenciesTests {
    @Test func liveUsesSystemRepository() {
        #expect(AppDependencies.live().systemInfo is LiveSystemInfoRepository)
    }

    @Test func launchArgumentSelectsFakeServices() async throws {
        let fake = AppDependencies.forLaunch(arguments: ["MacPulse", LaunchArgument.useFakeServices])
        #expect(!(fake.systemInfo is LiveSystemInfoRepository))
        let info = try await fake.systemInfo.currentSystemInfo()
        #expect(info.hardwareModel == "MacBookPro18,3")

        let live = AppDependencies.forLaunch(arguments: ["MacPulse"])
        #expect(live.systemInfo is LiveSystemInfoRepository)
    }
}

@Suite("AppModel")
@MainActor
struct AppModelTests {
    @Test func createsOneViewModelPerScreenSharingTheMonitor() async {
        let model = AppModel(dependencies: .preview())
        #expect(model.coordinator.selection == .overview)
        await model.start()
        await model.battery.observe()
        await model.overview.observeBattery()
        // Both screens see the same battery status from the shared monitor.
        #expect(model.battery.status != nil)
        #expect(model.battery.status == model.overview.batteryStatus)
    }
}

@Suite("LaunchDiagnostics")
@MainActor
struct LaunchDiagnosticsTests {
    @Test func requiresEnvironmentVariableAndArgument() {
        let argument = "--macpulse-process-access-probe"
        #expect(!LaunchDiagnostics.runIfRequested(arguments: ["MacPulse", argument], environment: [:]))
        #expect(!LaunchDiagnostics.runIfRequested(arguments: ["MacPulse"], environment: ["MACPULSE_DIAGNOSTICS": "1"]))
    }
}
