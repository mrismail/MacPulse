import Charts
import MacPulseDomain
import MacPulseShared
import SwiftUI

/// Space Analyzer: volume overview, then folder scans (read-only).
public struct SpaceAnalyzerView: View {
    @Bindable private var viewModel: SpaceAnalyzerViewModel

    public init(viewModel: SpaceAnalyzerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                VolumeOverviewCard(viewModel: viewModel)
            }
            .padding(Spacing.large)
        }
        .navigationTitle("Space Analyzer")
        .task { await viewModel.observeVolumes() }
    }
}

// MARK: - Volume overview

private struct VolumeOverviewCard: View {
    @Bindable var viewModel: SpaceAnalyzerViewModel

    var body: some View {
        Card("Storage", systemImage: "internaldrive") {
            if let error = viewModel.volumeError {
                Label(error.userMessage, systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("space.volumeError")
            }
            if viewModel.volumes.count > 1 {
                Picker("Volume", selection: Binding(
                    get: { viewModel.selectedVolume?.id ?? "" },
                    set: { viewModel.selectedVolumeID = $0 }
                )) {
                    ForEach(viewModel.volumes) { volume in
                        Label(volume.name, systemImage: VolumePresentation.symbol(volume.kind)).tag(volume.id)
                    }
                }
                .frame(maxWidth: 360)
                .accessibilityIdentifier("space.volumePicker")
            }
            if let volume = viewModel.selectedVolume {
                VolumeUsageView(volume: volume)
            } else if viewModel.hasLoadedVolumes {
                ContentUnavailableView("No Volumes", systemImage: "externaldrive.badge.questionmark")
            } else {
                ProgressView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("space.volume")
    }
}

/// One stacked bar (used · purgeable · free) and the figures the filesystem reports.
struct VolumeUsageView: View {
    let volume: VolumeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(spacing: Spacing.small) {
                Text(volume.name).font(.title3.weight(.semibold))
                if let format = volume.fileSystem {
                    Text(format).foregroundStyle(.secondary)
                }
                if volume.isReadOnly {
                    Text("Read-only").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let segments = VolumePresentation.segments(volume) {
                Chart(segments) { segment in
                    BarMark(x: .value("Bytes", segment.bytes), y: .value("Volume", volume.name))
                        .foregroundStyle(by: .value("Part", segment.title))
                }
                .chartForegroundStyleScale([
                    VolumePresentation.usedTitle: Color.accentColor,
                    VolumePresentation.purgeableTitle: Color.orange,
                    VolumePresentation.freeTitle: Color.secondary.opacity(0.25),
                ])
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 44)
                .accessibilityLabel(VolumePresentation.summary(volume))
                .accessibilityIdentifier("space.volumeChart")
            }
            HStack(alignment: .top, spacing: Spacing.large) {
                MetricValueView("Capacity", metric: volume.totalBytes) { ByteFormatting.string(fromBytes: $0) }
                MetricValueView("Used", metric: volume.usedBytes) { ByteFormatting.string(fromBytes: $0) }
                MetricValueView("Available", metric: volume.availableBytes) { ByteFormatting.string(fromBytes: $0) }
                MetricValueView("Purgeable", metric: volume.purgeableBytes) { ByteFormatting.string(fromBytes: $0) }
            }
            Text("Figures reported by the file system. Purgeable space (caches and local snapshots) is freed by macOS when space is needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Wording and chart data for volumes.
public enum VolumePresentation {
    public struct Segment: Identifiable, Equatable {
        public var id: String { title }
        public let title: String
        public let bytes: Int64
    }

    public static var usedTitle: String { String(localized: "Used") }
    public static var purgeableTitle: String { String(localized: "Purgeable") }
    public static var freeTitle: String { String(localized: "Available") }

    /// Used (excluding purgeable), purgeable, free; `nil` when capacity is unknown.
    public static func segments(_ volume: VolumeInfo) -> [Segment]? {
        guard let total = volume.totalBytes.value, total > 0, let available = volume.availableBytes.value else { return nil }
        // "Used" as the file system reports it includes purgeable space; show it once.
        let used = max(0, total - available)
        let purgeable = min(volume.purgeableBytes.value ?? 0, used)
        return [
            Segment(title: usedTitle, bytes: used - purgeable),
            Segment(title: purgeableTitle, bytes: purgeable),
            Segment(title: freeTitle, bytes: available),
        ]
    }

    public static func summary(_ volume: VolumeInfo) -> String {
        let used = volume.usedBytes.value.map { ByteFormatting.string(fromBytes: $0) } ?? "—"
        let total = volume.totalBytes.value.map { ByteFormatting.string(fromBytes: $0) } ?? "—"
        return String(localized: "\(volume.name): \(used) used of \(total)")
    }

    public static func symbol(_ kind: VolumeKind) -> String {
        switch kind {
        case .startup, .internal: "internaldrive"
        case .external: "externaldrive"
        case .network: "server.rack"
        case .diskImage: "opticaldiscdrive"
        }
    }
}
