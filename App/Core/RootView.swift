import MacPulseFeatures
import MacPulseShared
import SwiftUI

/// Main window content: sidebar plus the selected feature.
public struct RootView: View {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        @Bindable var coordinator = model.coordinator
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
        .task { await model.start() }
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
        case .overview:
            OverviewView(
                viewModel: model.overview,
                openBattery: { model.coordinator.select(.battery) },
                openEnergy: { model.coordinator.select(.energy) }
            )
        case .battery:
            BatteryView(viewModel: model.battery, energy: model.energy) {
                model.coordinator.select(.energy)
            }
        case .energy: EnergyView(viewModel: model.energy)
        case .spaceAnalyzer: SpaceAnalyzerView()
        case .duplicateFinder: DuplicateFinderView()
        case .cleaner: CleanerView()
        case .settings: SettingsView(viewModel: model.settings)
        }
    }
}
