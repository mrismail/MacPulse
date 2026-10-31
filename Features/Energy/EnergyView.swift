import AppKit
import Charts
import MacPulseDomain
import MacPulseShared
import SwiftUI

public struct EnergyView: View {
    @Bindable private var viewModel: EnergyViewModel
    /// Fast (10 s) sampling only while this window is the active one.
    @Environment(\.controlActiveState) private var controlActiveState

    public init(viewModel: EnergyViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                summary
                ScrollView {
                    VStack(spacing: Spacing.small) {
                        ForEach(viewModel.status?.alerts ?? []) { alert in
                            DrainAlertBanner(alert: alert) {
                                viewModel.select(alert.appKey)
                            }
                        }
                    }
                }
                .frame(maxHeight: (viewModel.status?.alerts.isEmpty ?? true) ? 0 : 140)
                Picker("Show", selection: $viewModel.timeframe) {
                    Text("Last \(viewModel.status?.recentWindowMinutes ?? 10) minutes").tag(EnergyTimeframe.recent)
                    Text("Right now").tag(EnergyTimeframe.now)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .accessibilityIdentifier("energy.timeframe")
                AppUsageTable(viewModel: viewModel)
                Text("CPU is shown per processor core: 100% means one core fully busy. System CPU is the share of all cores together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("energy.cpuUnitsNote")
            }
            .padding(Spacing.large)
            .frame(minHeight: 340)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    if let app = viewModel.selectedApp {
                        AppDetail(app: app, viewModel: viewModel)
                    } else if viewModel.selectedAppIsIdle {
                        Text("This app had no activity in the selected period.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        Text("Select an app to see its details and trend.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    AlertSettingsCard(viewModel: viewModel)
                }
                .padding(Spacing.large)
            }
            .frame(minHeight: 200)
        }
        .navigationTitle("Energy")
        .navigationSubtitle(updatedText)
        .task(id: controlActiveState == .key) {
            await viewModel.observe(detailed: controlActiveState == .key)
        }
        .task(id: viewModel.trendRange) { await viewModel.loadHistory() }
    }

    private var updatedText: String {
        guard let date = viewModel.status?.timestamp else { return "" }
        return String(localized: "Updated \(date.formatted(date: .omitted, time: .standard))")
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: Spacing.large) {
            MetricValueView("System CPU (all cores)", metric: viewModel.systemCPU) { NumberFormatting.percent($0) }
                .accessibilityIdentifier("energy.systemCPU")
            MetricValueView("Memory pressure", metric: viewModel.memoryPressure) { level in
                switch level {
                case .normal: String(localized: "Normal")
                case .warning: String(localized: "Elevated")
                case .critical: String(localized: "Critical")
                }
            }
            .accessibilityIdentifier("energy.memoryPressure")
            MetricValueView("MacPulse itself", metric: viewModel.ownCPU) { EnergyPresentation.cpuText($0) }
                .accessibilityIdentifier("energy.ownCPU")
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                if let status = viewModel.status {
                    Label(
                        status.energyDataAvailable
                            ? String(localized: "Battery impact is estimated from the energy macOS reports for each app.")
                            : String(localized: "This Mac doesn't report per-app energy, so apps are ranked by CPU activity. That isn't a battery measurement."),
                        systemImage: "info.circle"
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("energy.basisNote")
                    if status.unreadableProcessCount > 0 {
                        Text("System processes not included: \(status.unreadableProcessCount)")
                            .foregroundStyle(.secondary)
                    }
                    if let issue = status.historyIssue {
                        Label(issue.userMessage, systemImage: "exclamationmark.triangle")
                    }
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Table

private struct AppUsageTable: View {
    @Bindable var viewModel: EnergyViewModel
    @State private var columns = TableColumnCustomization<AppUsage>()

    var body: some View {
        let rows = viewModel.apps
        Table(
            rows,
            selection: Binding(get: { viewModel.selectedAppID }, set: { viewModel.select($0) }),
            sortOrder: $viewModel.sortOrder,
            columnCustomization: $columns
        ) {
            TableColumn("App", value: \.displayName) { app in
                HStack(spacing: Spacing.small) {
                    AppIcon(bundlePath: app.appBundlePath)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.displayName)
                        if app.processCount > 1 {
                            Text("Processes: \(app.processCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("energy.row.\(app.id)")
            }
            .width(min: 180, ideal: 240)
            .customizationID("app")
            .disabledCustomizationBehavior(.visibility)

            TableColumn(EnergyPresentation.impactTitle(energyDataAvailable: viewModel.energyDataAvailable), value: \.shareOfActivity) { app in
                ImpactBadge(impact: app.impact)
            }
            .width(min: 130, ideal: 150)
            .customizationID("impact")

            TableColumn("CPU", value: \.cpuPercent) { app in
                Text(NumberFormatting.percent(app.cpuPercent)).monospacedDigit()
            }
            .width(min: 60, ideal: 70)
            .customizationID("cpu")

            TableColumn("Memory", value: \.memorySortKey) { app in
                Text(app.memoryBytes.map { ByteFormatting.string(fromBytes: $0) } ?? "—").monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            .customizationID("memory")

            TableColumn("Energy", value: \.energySortKey) { app in
                Text(app.energyMilliwatts.map { NumberFormatting.watts($0 / 1_000) } ?? "—").monospacedDigit()
            }
            .width(min: 60, ideal: 80)
            .customizationID("energy")

            TableColumn("Idle wake-ups/s", value: \.wakeupSortKey) { app in
                Text(app.wakeupsPerSecond.map { NumberFormatting.integer(Int($0.rounded())) } ?? "—").monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            .customizationID("wakeups")
        }
        .frame(minHeight: 200)
        .accessibilityIdentifier("energy.table")
        .onChange(of: viewModel.energyDataAvailable, initial: true) { _, available in
            // The Energy column is all "—" when macOS doesn't report per-app energy.
            columns[visibility: "energy"] = available ? .visible : .hidden
        }
        .overlay {
            if viewModel.status == nil {
                ProgressView("Measuring app activity…")
            } else if rows.isEmpty {
                ContentUnavailableView("No Activity", systemImage: "moon.zzz", description: Text("No app used measurable CPU in this period."))
            }
        }
    }
}

extension AppUsage {
    var memorySortKey: Double { Double(memoryBytes ?? 0) }
    var energySortKey: Double { energyMilliwatts ?? -1 }
    var wakeupSortKey: Double { wakeupsPerSecond ?? -1 }
}

/// App icons are looked up once per bundle and cached; `NSWorkspace.icon(forFile:)` is
/// too slow to call for every row on every refresh.
@MainActor
enum AppIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for bundlePath: String) -> NSImage {
        if let cached = cache.object(forKey: bundlePath as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: bundlePath)
        cache.setObject(icon, forKey: bundlePath as NSString)
        return icon
    }
}

private struct AppIcon: View {
    let bundlePath: String?

    var body: some View {
        Group {
            if let bundlePath {
                Image(nsImage: AppIconCache.icon(for: bundlePath))
                    .resizable()
            } else {
                Image(systemName: "gearshape")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// Estimated impact: shape + word, never color alone, always labeled as an estimate.
struct ImpactBadge: View {
    let impact: Metric<BatteryImpactLevel>

    var body: some View {
        Label(EnergyPresentation.levelTitle(impact.value), systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.primary)
            .font(.callout)
            .help(impact.provenance.explanation)
            .accessibilityLabel(String(localized: "Estimated impact: \(EnergyPresentation.levelTitle(impact.value))"))
            .accessibilityHint(impact.provenance.explanation)
    }

    private var symbol: String {
        switch impact.value {
        case .high: "gauge.with.dots.needle.100percent"
        case .moderate: "gauge.with.dots.needle.50percent"
        case .low, nil: "gauge.with.dots.needle.0percent"
        }
    }
}

// MARK: - Detail

private struct AppDetail: View {
    let app: AppUsage
    @Bindable var viewModel: EnergyViewModel

    var body: some View {
        Card(app.displayName, systemImage: "app.dashed") {
            Text(viewModel.timeframe == .now
                ? String(localized: "Latest sample")
                : String(localized: "Average over the last \(viewModel.status?.recentWindowMinutes ?? 10) minutes"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: Spacing.large) {
                MetricValueView("CPU (per core)", metric: .measured(app.cpuPercent)) { NumberFormatting.percent($0) }
                MetricValueView("Memory", metric: app.memoryBytes.map { Metric<UInt64>.measured($0) } ?? .unavailable(.notSupportedOnThisMac)) {
                    ByteFormatting.string(fromBytes: $0)
                }
                MetricValueView(
                    EnergyPresentation.impactTitle(energyDataAvailable: viewModel.energyDataAvailable),
                    metric: app.impact.map { EnergyPresentation.levelTitle($0) }
                ) { $0 }
                MetricValueView("Share of app activity", metric: .estimated(app.shareOfActivity * 100, basis: app.impact.provenance.explanation)) {
                    NumberFormatting.percent($0)
                }
            }
            if let path = app.appBundlePath {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Picker("Trend", selection: $viewModel.trendMetric) {
                    Text("CPU").tag(EnergyTrendMetric.cpu)
                    Text("Memory").tag(EnergyTrendMetric.memory)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .accessibilityIdentifier("energy.trendMetric")
                Picker("Range", selection: $viewModel.trendRange) {
                    Text("24 Hours").tag(EnergyTrendRange.day)
                    Text("7 Days").tag(EnergyTrendRange.week)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            .labelsHidden()

            if let error = viewModel.historyError {
                Label(error.userMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else if viewModel.trend.isEmpty {
                Text("No hourly history yet for this app. Trends build up while MacPulse is running.")
                    .foregroundStyle(.secondary)
            } else {
                TrendChart(points: viewModel.trend, metric: viewModel.trendMetric, domain: viewModel.trendDomain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("energy.detail")
    }
}

private struct TrendChart: View {
    let points: [EnergyTrendPoint]
    let metric: EnergyTrendMetric
    let domain: ClosedRange<Date>

    private static let onBattery = String(localized: "Mostly on battery")
    private static let onPower = String(localized: "Mostly on power")

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Hour", point.hour, unit: .hour),
                y: .value(metric == .cpu ? "Average CPU" : "Average memory", value(of: point))
            )
            // Power state is named in the legend and read by VoiceOver, not shown by color alone.
            .foregroundStyle(by: .value("Power", point.onBattery ? Self.onBattery : Self.onPower))
            .accessibilityLabel(point.hour.formatted(date: .abbreviated, time: .shortened))
            .accessibilityValue("\(label(for: value(of: point))), \(point.onBattery ? Self.onBattery : Self.onPower)")
        }
        .chartForegroundStyleScale([
            Self.onBattery: AnyShapeStyle(Color.orange.gradient),
            Self.onPower: AnyShapeStyle(Color.accentColor.opacity(0.55)),
        ])
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXScale(domain: domain)
        .chartYAxis {
            AxisMarks { mark in
                AxisGridLine()
                AxisValueLabel {
                    if let number = mark.as(Double.self) {
                        Text(label(for: number))
                    }
                }
            }
        }
        .frame(height: 170)
        .accessibilityIdentifier("energy.trendChart")
    }

    private func value(of point: EnergyTrendPoint) -> Double {
        switch metric {
        case .cpu: point.averageCPUPercent
        case .memory: point.averageMemoryBytes ?? 0
        }
    }

    private func label(for value: Double) -> String {
        switch metric {
        case .cpu: NumberFormatting.percent(value)
        case .memory: ByteFormatting.string(fromBytes: UInt64(max(0, value)))
        }
    }
}

// MARK: - Alerts

struct DrainAlertBanner: View {
    let alert: DrainAlert
    var showApp: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(alert.displayName) is using a lot of CPU").bold()
                    Text(alert.explanation)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
            }
            Spacer()
            if let showApp {
                Button("Show", action: showApp)
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.orange, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("energy.alert")
    }
}

private struct AlertSettingsCard: View {
    @Bindable var viewModel: EnergyViewModel

    var body: some View {
        Card("Alerts", systemImage: "bell") {
            Toggle("Alert me when an app uses a lot of CPU", isOn: binding(\.isEnabled))
                .accessibilityIdentifier("energy.alerts.enabled")
            Group {
                HStack {
                    Slider(
                        value: binding(\.cpuThresholdPercent),
                        in: 20...200,
                        step: 10,
                        label: { Text("CPU above") },
                        onEditingChanged: { editing in
                            if !editing { Task { await viewModel.commitSettings() } }
                        }
                    )
                    .frame(maxWidth: 260)
                    .accessibilityValue(NumberFormatting.percent(viewModel.settings.cpuThresholdPercent))
                    .accessibilityIdentifier("energy.alerts.threshold")
                    Text(NumberFormatting.percent(viewModel.settings.cpuThresholdPercent)).monospacedDigit()
                        .accessibilityHidden(true)
                }
                Stepper(value: binding(\.sustainedMinutes), in: 5...60, step: 5) {
                    Text("For at least \(viewModel.settings.sustainedMinutes) minutes")
                }
                Toggle("Only while on battery", isOn: binding(\.onlyOnBattery))
                Toggle("Also show a macOS notification", isOn: binding(\.sendsNotifications))
                if viewModel.notificationsDenied {
                    Label("Notifications are turned off for MacPulse in System Settings → Notifications.", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!viewModel.settings.isEnabled)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<DrainAlertSettings, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.settings[keyPath: keyPath] },
            set: { newValue in viewModel.editSettings { $0[keyPath: keyPath] = newValue } }
        )
    }
}

#if DEBUG
    struct EnergyView_Previews: PreviewProvider {
        static var previews: some View {
            EnergyView(viewModel: EnergyViewModel(monitor: PreviewEnergyMonitor()))
                .frame(width: 1000, height: 820)
        }
    }
#endif
