import AppKit
import Charts
import MacPulseDomain
import MacPulseShared
import SwiftUI

public struct EnergyView: View {
    @Bindable private var viewModel: EnergyViewModel

    public init(viewModel: EnergyViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                summary
                ForEach(viewModel.status?.alerts ?? []) { alert in
                    DrainAlertBanner(alert: alert)
                }
                Picker("Show", selection: $viewModel.timeframe) {
                    Text("Last \(viewModel.status?.recentWindowMinutes ?? 10) minutes").tag(EnergyTimeframe.recent)
                    Text("Right now").tag(EnergyTimeframe.now)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .accessibilityIdentifier("energy.timeframe")
                AppUsageTable(viewModel: viewModel)
            }
            .padding(Spacing.large)
            .frame(minHeight: 320)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    if let app = viewModel.selectedApp {
                        AppDetail(app: app, viewModel: viewModel)
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
        .task { await viewModel.observe(detailed: true) }
        .task(id: viewModel.trendRange) { await viewModel.loadHistory() }
    }

    private var updatedText: String {
        guard let date = viewModel.status?.timestamp else { return "" }
        return String(localized: "Updated \(date.formatted(date: .omitted, time: .standard))")
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: Spacing.large) {
            MetricValueView("System CPU", metric: viewModel.systemCPU) { NumberFormatting.percent($0) }
                .accessibilityIdentifier("energy.systemCPU")
            MetricValueView("MacPulse itself", metric: viewModel.ownCPU) {
                NumberFormatting.percent($0) + " " + String(localized: "CPU")
            }
            .accessibilityIdentifier("energy.ownCPU")
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                if let status = viewModel.status {
                    Label(
                        status.energyDataAvailable
                            ? String(localized: "Battery impact uses macOS energy data.")
                            : String(localized: "Battery impact is estimated from CPU use."),
                        systemImage: "info.circle"
                    )
                    if status.unreadableProcessCount > 0 {
                        Text("\(status.unreadableProcessCount) system processes run as another user and aren't included.")
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
    @State private var sortOrder = [KeyPathComparator(\AppUsage.shareOfActivity, order: .reverse)]

    private var rows: [AppUsage] {
        let apps = viewModel.apps
        // Default order is the impact ranking; a column click re-sorts.
        return sortOrder.first?.keyPath == \AppUsage.shareOfActivity ? apps : apps.sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: Binding(get: { viewModel.selectedAppID }, set: { viewModel.select($0) }), sortOrder: $sortOrder) {
            TableColumn("App", value: \.displayName) { app in
                HStack(spacing: Spacing.small) {
                    AppIcon(bundlePath: app.appBundlePath)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.displayName)
                        if app.processCount > 1 {
                            Text("\(app.processCount) processes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("energy.row.\(app.displayName)")
            }
            .width(min: 180, ideal: 240)

            TableColumn("Battery impact", value: \.shareOfActivity) { app in
                ImpactBadge(impact: app.impact)
            }
            .width(min: 110, ideal: 120)

            TableColumn("CPU", value: \.cpuPercent) { app in
                Text(NumberFormatting.percent(app.cpuPercent)).monospacedDigit()
            }
            .width(min: 60, ideal: 70)

            TableColumn("Memory", value: \.memorySortKey) { app in
                Text(app.memoryBytes.map { ByteFormatting.string(fromBytes: $0) } ?? "—").monospacedDigit()
            }
            .width(min: 70, ideal: 90)

            TableColumn("Energy", value: \.energySortKey) { app in
                Text(app.energyMilliwatts.map { NumberFormatting.watts($0 / 1_000) } ?? "—").monospacedDigit()
            }
            .width(min: 60, ideal: 80)

            TableColumn("Wake-ups/s", value: \.wakeupSortKey) { app in
                Text(app.wakeupsPerSecond.map { NumberFormatting.integer(Int($0.rounded())) } ?? "—").monospacedDigit()
            }
            .width(min: 70, ideal: 90)
        }
        .frame(minHeight: 200)
        .accessibilityIdentifier("energy.table")
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

private struct AppIcon: View {
    let bundlePath: String?

    var body: some View {
        Group {
            if let bundlePath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: bundlePath))
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

/// Estimated battery impact: shape + word, never color alone, always an estimate.
struct ImpactBadge: View {
    let impact: Metric<BatteryImpactLevel>

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.primary)
            .font(.callout)
            .help(impact.provenance.explanation)
            .accessibilityLabel(String(localized: "Battery impact: \(title), estimate"))
    }

    private var title: String {
        switch impact.value {
        case .high: String(localized: "High")
        case .moderate: String(localized: "Moderate")
        case .low: String(localized: "Low")
        case nil: "—"
        }
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
            HStack(alignment: .top, spacing: Spacing.large) {
                MetricValueView("CPU", metric: .measured(app.cpuPercent)) { NumberFormatting.percent($0) }
                MetricValueView("Memory", metric: app.memoryBytes.map { Metric<UInt64>.measured($0) } ?? .unavailable(.notSupportedOnThisMac)) {
                    ByteFormatting.string(fromBytes: $0)
                }
                MetricValueView("Battery impact", metric: app.impact.map { level in
                    switch level {
                    case .high: String(localized: "High")
                    case .moderate: String(localized: "Moderate")
                    case .low: String(localized: "Low")
                    }
                }) { $0 }
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

            Picker("Trend", selection: $viewModel.trendRange) {
                Text("24 Hours").tag(EnergyTrendRange.day)
                Text("7 Days").tag(EnergyTrendRange.week)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)

            if let error = viewModel.historyError {
                Label(error.userMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else if viewModel.trend.isEmpty {
                Text("No hourly history yet for this app. Trends build up while MacPulse is running.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(viewModel.trend) { point in
                    BarMark(
                        x: .value("Hour", point.hour, unit: .hour),
                        y: .value("Average CPU", point.averageCPUPercent)
                    )
                    .foregroundStyle(point.onBattery ? Color.orange : Color.accentColor)
                    .accessibilityLabel(point.hour.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityValue("\(NumberFormatting.percent(point.averageCPUPercent)) CPU\(point.onBattery ? ", on battery" : "")")
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let percent = value.as(Double.self) {
                                Text(NumberFormatting.percent(percent))
                            }
                        }
                    }
                }
                .frame(height: 160)
                .accessibilityIdentifier("energy.trendChart")
                HStack(spacing: Spacing.medium) {
                    Label("Mostly on battery", systemImage: "square.fill").foregroundStyle(Color.orange)
                    Label("Mostly on power", systemImage: "square.fill").foregroundStyle(Color.accentColor)
                }
                .font(.caption)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("energy.detail")
    }
}

// MARK: - Alerts

struct DrainAlertBanner: View {
    let alert: DrainAlert

    var body: some View {
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
                    Text("CPU above")
                    Slider(value: binding(\.cpuThresholdPercent), in: 20...200, step: 10)
                        .frame(maxWidth: 220)
                    Text(NumberFormatting.percent(viewModel.settings.cpuThresholdPercent)).monospacedDigit()
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
            Text("100% CPU equals one fully busy processor core.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<DrainAlertSettings, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = viewModel.settings
                updated[keyPath: keyPath] = newValue
                Task { await viewModel.updateSettings(updated) }
            }
        )
    }
}

#if DEBUG
    struct EnergyView_Previews: PreviewProvider {
        static var previews: some View {
            EnergyView(viewModel: EnergyViewModel(monitor: PreviewEnergyMonitor()))
                .frame(width: 1000, height: 800)
        }
    }
#endif
