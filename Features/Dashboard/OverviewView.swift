import MacPulseDomain
import MacPulseShared
import SwiftUI

public struct OverviewView: View {
    @State private var viewModel: OverviewViewModel

    public init(viewModel: OverviewViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: Spacing.medium, alignment: .top)],
                    alignment: .leading,
                    spacing: Spacing.medium
                ) {
                    batteryCard
                    storageCard
                    thisMacCard
                }

                Card("Coming next", systemImage: "list.bullet.rectangle") {
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
    }

    private var batteryCard: some View {
        Card("Battery", systemImage: "battery.75percent") {
            MetricValueView("Charge", metric: viewModel.batteryCharge) {
                $0.formatted(.percent.precision(.fractionLength(0)))
            }
            MetricValueView("Estimated runtime", metric: viewModel.estimatedRuntimeMinutes) {
                DurationFormatting.string(fromMinutes: $0)
            }
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
            OverviewView(viewModel: OverviewViewModel(systemInfoRepository: PreviewSystemInfoRepository()))
                .frame(width: 800, height: 600)
        }
    }
#endif
