import Charts
import MacPulseDomain
import MacPulseShared
import SwiftUI

public struct BatteryView: View {
    @Bindable private var viewModel: BatteryViewModel
    private let energy: EnergyViewModel?
    private let openEnergy: () -> Void
    @State private var selectedDate: Date?

    public init(viewModel: BatteryViewModel, energy: EnergyViewModel? = nil, openEnergy: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.energy = energy
        self.openEnergy = openEnergy
    }

    public var body: some View {
        Group {
            if viewModel.hasBattery {
                content
            } else {
                ContentUnavailableView(
                    "No Battery",
                    systemImage: "powerplug",
                    description: Text("This Mac runs on external power only, so there is no battery to monitor.")
                )
            }
        }
        .navigationTitle("Battery")
        .navigationSubtitle(lastUpdatedText)
        .toolbar {
            if viewModel.hasBattery {
                ToolbarItem {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Read the battery now (⌘R)")
                }
            }
        }
        .task { await viewModel.observe() }
        .task(id: viewModel.range) { await viewModel.reloadHistory() }
    }

    private var lastUpdatedText: String {
        guard let lastUpdated = viewModel.lastUpdated else { return "" }
        return String(localized: "Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                if let issue = viewModel.status?.historyIssue {
                    Label(issue.userMessage, systemImage: "exclamationmark.triangle.fill")
                        .padding(Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.card))
                        .accessibilityIdentifier("battery.historyIssue")
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: Spacing.medium, alignment: .top)],
                    alignment: .leading,
                    spacing: Spacing.medium
                ) {
                    statusCard
                    healthCard
                    electricalCard
                }
                historyCard
                sessionsCard
                if let energy {
                    TopAppsCard(energy: energy, openEnergy: openEnergy)
                }
            }
            .padding(Spacing.large)
        }
    }

    // MARK: Cards

    @ViewBuilder
    private var statusCard: some View {
        Card("Status", systemImage: "battery.75percent") {
            if let status = viewModel.status {
                MetricValueView("Charge", metric: status.reading.charge, prominence: .hero) {
                    NumberFormatting.percent($0)
                }
                .accessibilityIdentifier("battery.charge")
                Text(viewModel.stateDescription)
                    .font(.headline)
                    .accessibilityIdentifier("battery.state")
                Divider()
                if status.reading.chargingState.value == .charging {
                    MetricValueView("Time to full", metric: status.reading.systemTimeToFullMinutes) {
                        DurationFormatting.string(fromMinutes: $0)
                    }
                } else {
                    MetricValueView("Estimated runtime", metric: viewModel.estimatedRuntime) {
                        DurationFormatting.string(fromMinutes: $0)
                    }
                    .accessibilityIdentifier("battery.runtime")
                    if status.reading.powerSource.value == .battery {
                        DisclosureGroup("How this is estimated") {
                            VStack(alignment: .leading, spacing: Spacing.small) {
                                MetricValueView("From recent discharge", metric: status.runtimeFromRecentDischarge) {
                                    DurationFormatting.string(fromMinutes: $0)
                                }
                                MetricValueView("macOS estimate", metric: status.reading.systemTimeToEmptyMinutes) {
                                    DurationFormatting.string(fromMinutes: $0)
                                }
                                MetricValueView("Discharge rate", metric: status.dischargeRatePercentPerHour) {
                                    NumberFormatting.percentPerHour($0)
                                }
                            }
                            .padding(.top, Spacing.small)
                        }
                    }
                }
            } else {
                ProgressView("Reading battery…")
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var healthCard: some View {
        Card("Health", systemImage: "heart.text.square") {
            if let reading = viewModel.status?.reading {
                MetricValueView("Health", metric: reading.healthPercentage) { NumberFormatting.percent($0) }
                    .accessibilityIdentifier("battery.health")
                MetricValueView("Condition", metric: viewModel.conditionDescription) { $0 }
                MetricValueView("Cycle count", metric: reading.cycleCount) { NumberFormatting.integer($0) }
                    .accessibilityIdentifier("battery.cycleCount")
                MetricValueView("Full-charge capacity", metric: reading.fullChargeCapacityMAh) {
                    NumberFormatting.milliampereHours($0)
                }
                MetricValueView("Design capacity", metric: reading.designCapacityMAh) {
                    NumberFormatting.milliampereHours($0)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var electricalCard: some View {
        Card("Power", systemImage: "bolt.fill") {
            if let reading = viewModel.status?.reading {
                MetricValueView("Charging power", metric: reading.chargingPowerWatts) { NumberFormatting.watts($0) }
                MetricValueView("Power adapter", metric: reading.adapterWatts) { NumberFormatting.watts(Double($0)) }
                MetricValueView("Battery temperature", metric: reading.temperatureCelsius) {
                    NumberFormatting.temperature(celsius: $0)
                }
                MetricValueView("Voltage", metric: reading.voltageVolts) { NumberFormatting.volts($0) }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var historyCard: some View {
        Card("Charge history", systemImage: "chart.xyaxis.line") {
            Picker("Range", selection: $viewModel.range) {
                ForEach(BatteryHistoryRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .accessibilityIdentifier("battery.range")

            if let error = viewModel.historyError {
                Label(error.userMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else if viewModel.chartPoints.isEmpty {
                Text("No history yet. MacPulse records the charge level every minute while it is running.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart
                HStack(spacing: Spacing.medium) {
                    Label {
                        Text("Charge")
                    } icon: {
                        RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(width: 14, height: 3)
                            .accessibilityHidden(true)
                    }
                    .accessibilityIdentifier("battery.legend.charge")
                    Label {
                        Text("On power")
                    } icon: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.3))
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.green, lineWidth: 1))
                            .frame(width: 14, height: 10)
                            .accessibilityHidden(true)
                    }
                    .accessibilityIdentifier("battery.legend.onPower")
                    Spacer()
                    Text("Gaps mean MacPulse wasn't running or the Mac was asleep.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("battery.legend.gaps")
                }
                .font(.caption)
            }
        }
    }

    private var selectedPoint: BatteryChartPoint? {
        guard let selectedDate else { return nil }
        return viewModel.chartPoints.min {
            abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate))
        }
    }

    private var chart: some View {
        Chart {
            ForEach(viewModel.recentSessions) { session in
                RectangleMark(
                    xStart: .value("Plugged in", session.start),
                    xEnd: .value("Unplugged", session.end),
                    yStart: .value("Bottom", 0),
                    yEnd: .value("Top", 100)
                )
                .foregroundStyle(Color.green.opacity(0.12))
                .accessibilityLabel("On power")
                .accessibilityValue("\(session.start.formatted(date: .abbreviated, time: .shortened)) to \(session.end.formatted(date: .omitted, time: .shortened))")
            }
            ForEach(viewModel.chartPoints) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Charge", point.percentage),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.monotone)
                .accessibilityLabel(point.timestamp.formatted(date: .abbreviated, time: .shortened))
                .accessibilityValue(NumberFormatting.percent(point.percentage))
            }
            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.timestamp))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(NumberFormatting.percent(selectedPoint.percentage)).bold()
                            Text(selectedPoint.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(Spacing.xSmall)
                        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: Radius.badge))
                    }
                PointMark(
                    x: .value("Time", selectedPoint.timestamp),
                    y: .value("Charge", selectedPoint.percentage)
                )
                .foregroundStyle(Color.accentColor)
            }
        }
        .chartXScale(domain: viewModel.chartDomain)
        .chartYScale(domain: 0...100)
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text(NumberFormatting.percent(percent))
                    }
                }
            }
        }
        .frame(height: 220)
        .accessibilityLabel("Battery charge history")
        .accessibilityIdentifier("battery.historyChart")
    }

    private var sessionsCard: some View {
        Card("Charging sessions", systemImage: "powerplug") {
            if viewModel.recentSessions.isEmpty {
                Text("No charging sessions in this range.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("battery.sessions.empty")
            } else {
                ForEach(viewModel.recentSessions.prefix(8)) { session in
                    ChargingSessionRow(session: session)
                }
            }
        }
    }
}

/// The apps with the highest estimated battery impact, from the Energy monitor.
private struct TopAppsCard: View {
    let energy: EnergyViewModel
    let openEnergy: () -> Void

    var body: some View {
        Card(EnergyPresentation.topAppsTitle(energyDataAvailable: energy.energyDataAvailable), systemImage: "bolt.horizontal.circle") {
            if energy.status == nil {
                ProgressView("Measuring app activity…").controlSize(.small)
            } else if energy.topApps.isEmpty {
                Text("No app has used noticeable CPU in the last \(energy.status?.recentWindowMinutes ?? 10) minutes.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(energy.topApps) { app in
                    HStack {
                        Text(app.displayName)
                        Spacer()
                        Text(EnergyPresentation.cpuText(app.cpuPercent))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        ImpactBadge(impact: app.impact)
                            .frame(minWidth: 110, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Button("Show All Apps", action: openEnergy)
                .buttonStyle(.link)
                .accessibilityIdentifier("battery.openEnergy")
        }
        .accessibilityElement(children: .contain)  // keep the children's own identifiers
        .accessibilityIdentifier("battery.topApps")
        .task { await energy.observe(detailed: false) }
    }
}

private struct ChargingSessionRow: View {
    let session: ChargingSession

    var body: some View {
        row
            .accessibilityIdentifier("battery.session")
    }

    private var row: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.start.formatted(date: .abbreviated, time: .shortened))
                Text(durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let start = session.startPercentage, let end = session.endPercentage {
                HStack(spacing: Spacing.xSmall) {
                    Text(NumberFormatting.percent(start))
                    // `arrow.forward` mirrors automatically in right-to-left languages.
                    Image(systemName: "arrow.forward").foregroundStyle(.secondary)
                    Text(NumberFormatting.percent(end))
                }
                .monospacedDigit()
            } else {
                Text("—")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var durationText: String {
        let base = DurationFormatting.string(fromMinutes: Int(session.duration / 60))
        return session.isOngoing ? String(localized: "\(base), still on power") : base
    }
}

#if DEBUG
    struct BatteryView_Previews: PreviewProvider {
        static var previews: some View {
            BatteryView(
                viewModel: BatteryViewModel(monitor: PreviewBatteryMonitor()),
                energy: EnergyViewModel(monitor: PreviewEnergyMonitor())
            )
                .frame(width: 900, height: 900)
        }
    }
#endif
