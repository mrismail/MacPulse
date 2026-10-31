import MacPulseDomain
import MacPulseShared
import SwiftUI

public struct OverviewView: View {
    private let viewModel: OverviewViewModel
    private let openBattery: () -> Void
    private let openEnergy: () -> Void

    public init(
        viewModel: OverviewViewModel,
        openBattery: @escaping () -> Void = {},
        openEnergy: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.openBattery = openBattery
        self.openEnergy = openEnergy
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                recommendationsCard

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: Spacing.medium, alignment: .top)],
                    alignment: .leading,
                    spacing: Spacing.medium
                ) {
                    batteryCard
                    energyCard
                    storageCard
                    thisMacCard
                }

                Card("More tools coming soon", systemImage: "sparkles") {
                    ForEach(viewModel.upcomingFeatures, id: \.title) { feature in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title).bold()
                                Text(feature.summary).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: feature.systemImage)
                        }
                    }
                }
            }
            .padding(Spacing.large)
        }
        .navigationTitle("Overview")
        .task { await viewModel.load() }
        .task { await viewModel.observeBattery() }
        .task { await viewModel.observeEnergy() }
    }

    private var recommendationsCard: some View {
        Card("Recommended", systemImage: "lightbulb") {
            if viewModel.recommendations.isEmpty {
                Label("Nothing needs your attention right now.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.recommendations) { recommendation in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recommendation.title).bold()
                            Text(recommendation.detail)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: recommendation.severity == .warning
                            ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundStyle(recommendation.severity == .warning ? Color.orange : Color.accentColor)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.recommendations")
    }

    private var batteryCard: some View {
        Card("Battery", systemImage: "battery.75percent") {
            MetricValueView("Charge", metric: viewModel.batteryCharge) {
                NumberFormatting.percent($0)
            }
            if let state = viewModel.batteryStateDescription {
                Text(state).font(.headline)
            }
            MetricValueView("Estimated runtime", metric: viewModel.estimatedRuntimeMinutes) {
                DurationFormatting.string(fromMinutes: $0)
            }
            Button("Show Battery Details", action: openBattery)
                .buttonStyle(.link)
                .accessibilityIdentifier("overview.openBattery")
        }
    }

    private var energyCard: some View {
        Card("Energy", systemImage: "bolt.horizontal.circle") {
            if viewModel.topApps.isEmpty {
                Text("Measuring app activity…").foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.topApps) { app in
                    HStack {
                        Text(app.displayName).lineLimit(1)
                        Spacer()
                        ImpactBadge(impact: app.impact)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Button("Show Energy Details", action: openEnergy)
                .buttonStyle(.link)
                .accessibilityIdentifier("overview.openEnergy")
        }
    }

    private var storageCard: some View {
        Card("Storage", systemImage: "internaldrive") {
            MetricValueView("Available", metric: viewModel.storageAvailableBytes) {
                ByteFormatting.string(fromBytes: $0)
            }
            MetricValueView("Potentially reclaimable", metric: viewModel.reclaimableBytes) {
                ByteFormatting.string(fromBytes: $0)
            }
        }
    }

    private var thisMacCard: some View {
        Card("This Mac", systemImage: "laptopcomputer") {
            switch viewModel.systemInfo {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
            case .loaded(let info):
                VStack(alignment: .leading, spacing: Spacing.small) {
                    KeyValueRow("Model", value: info.hardwareModel ?? "Unknown")
                    KeyValueRow("Processor", value: info.architectureDescription)
                    KeyValueRow("Memory", value: info.memoryDescription)
                    KeyValueRow("macOS", value: info.macOSVersion)
                }
            case .failed(let error):
                Label(error.userMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
    struct OverviewView_Previews: PreviewProvider {
        static var previews: some View {
            OverviewView(viewModel: OverviewViewModel(
                systemInfoRepository: PreviewSystemInfoRepository(),
                batteryMonitor: PreviewBatteryMonitor(),
                energyMonitor: PreviewEnergyMonitor()
            ))
            .frame(width: 800, height: 700)
        }
    }
#endif
