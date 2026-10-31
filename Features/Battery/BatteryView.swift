import Charts
import MacPulseDomain
import MacPulseShared
import SwiftUI

public struct BatteryView: View {
    @State private var viewModel: BatteryViewModel

    public init(viewModel: BatteryViewModel) {
        _viewModel = State(initialValue: viewModel)
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
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Read the battery now")
            }
        }
        .task { await viewModel.observe() }
        .task(id: viewModel.range) { await viewModel.reloadHistory() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
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
                Card("App activity", systemImage: "list.bullet.rectangle") {
                    Text("Which apps use the most CPU and memory arrives with the Energy view in Phase 3.")
                        .foregroundStyle(.secondary)
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
                MetricValueView("Charge", metric: status.reading.charge) { NumberFormatting.percent($0) }
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
                    MetricValueView("Estimated runtime", metric: status.runtimeFromRecentDischarge) {
                        DurationFormatting.string(fromMinutes: $0)
                    }
                    .accessibilityIdentifier("battery.runtime")
                    MetricValueView("macOS estimate", metric: status.reading.systemTimeToEmptyMinutes) {
                        DurationFormatting.string(fromMinutes: $0)
                    }
                    MetricValueView("Discharge rate", metric: status.dischargeRatePercentPerHour) {
                        NumberFormatting.percentPerHour($0)
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
                MetricValueView("Cycle count", metric: reading.cycleCount) { "\($0)" }
                    .accessibilityIdentifier("battery.cycleCount")
                MetricValueView("Full-charge capacity", metric: reading.fullChargeCapacityMAh) { "\($0) mAh" }
                MetricValueView("Design capacity", metric: reading.designCapacityMAh) { "\($0) mAh" }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var electricalCard: some View {
        Card("Power", systemImage: "bolt.fill") {
            if let reading = viewModel.status?.reading {
                MetricValueView("Charging power", metric: reading.chargingPowerWatts) {
                    NumberFormatting.measurement($0, unit: "W")
                }
                MetricValueView("Power adapter", metric: reading.adapterWatts) { "\($0) W" }
                MetricValueView("Battery temperature", metric: reading.temperatureCelsius) {
                    NumberFormatting.measurement($0, unit: "°C")
                }
                MetricValueView("Voltage", metric: reading.voltageVolts) {
                    NumberFormatting.measurement($0, unit: "V", fractionDigits: 2)
                }
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
                    Label("Charge", systemImage: "line.diagonal").foregroundStyle(Color.accentColor)
                    Label("On power", systemImage: "square.fill").foregroundStyle(Color.green.opacity(0.5))
                    Spacer()
                    Text("Gaps mean MacPulse wasn't running or the Mac was asleep.")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
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
            }
            ForEach(viewModel.chartPoints) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Charge", point.percentage),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text("\(percent)%")
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
            } else {
                ForEach(viewModel.recentSessions.prefix(8)) { session in
                    ChargingSessionRow(session: session)
                }
            }
        }
    }
}

private struct ChargingSessionRow: View {
    let session: ChargingSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.start.formatted(date: .abbreviated, time: .shortened))
                Text(durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(percentText)
                .monospacedDigit()
        }
    }

    private var durationText: String {
        let minutes = Int(session.duration / 60)
        let base = DurationFormatting.string(fromMinutes: minutes)
        return session.isOngoing ? "\(base) so far" : base
    }

    private var percentText: String {
        switch (session.startPercentage, session.endPercentage) {
        case let (start?, end?):
            "\(NumberFormatting.percent(start)) → \(NumberFormatting.percent(end))"
        default:
            "—"
        }
    }
}

#if DEBUG
    struct BatteryView_Previews: PreviewProvider {
        static var previews: some View {
            BatteryView(viewModel: BatteryViewModel(monitor: PreviewBatteryMonitor()))
                .frame(width: 900, height: 900)
        }
    }
#endif
