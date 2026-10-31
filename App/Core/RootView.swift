import MacPulseFeatures
import MacPulseShared
import SwiftUI

/// Main window content: sidebar plus the selected feature.
public struct RootView: View {
    @Bindable private var coordinator: AppCoordinator

    // View models are created once and kept for the window's lifetime, so switching
    // sections does not reload data or lose state.
    @State private var overviewModel: OverviewViewModel
    @State private var settingsModel: SettingsViewModel

    public init(coordinator: AppCoordinator, dependencies: AppDependencies) {
        self.coordinator = coordinator
        _overviewModel = State(initialValue: OverviewViewModel(systemInfoRepository: dependencies.systemInfo))
        _settingsModel = State(initialValue: SettingsViewModel(systemInfoRepository: dependencies.systemInfo))
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $coordinator.selection) {
                ForEach(SidebarGroup.allCases) { group in
                    if let title = group.title {
                        Section(title) { rows(for: group) }
                    } else {
                        Section { rows(for: group) }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        } detail: {
            detail(for: coordinator.effectiveSelection)
        }
    }

    @ViewBuilder
    private func rows(for group: SidebarGroup) -> some View {
        ForEach(group.sections) { section in
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
                .accessibilityIdentifier(section.accessibilityIdentifier)
        }
    }

    @ViewBuilder
    private func detail(for section: SidebarSection) -> some View {
        switch section {
        case .overview: OverviewView(viewModel: overviewModel)
        case .battery: BatteryView()
        case .energy: EnergyView()
        case .spaceAnalyzer: SpaceAnalyzerView()
        case .duplicateFinder: DuplicateFinderView()
        case .cleaner: CleanerView()
        case .settings: SettingsView(viewModel: settingsModel)
        }
    }
}
