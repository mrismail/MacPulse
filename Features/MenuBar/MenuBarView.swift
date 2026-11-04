import AppKit
import MacPulseDomain
import MacPulseShared
import SwiftUI

/// The menu bar companion (ADR-016): battery, the most active apps, free space and
/// shortcuts into the app. Uses the same view model and monitors as the Overview.
public struct MenuBarView: View {
    private let overview: OverviewViewModel
    private let open: (MenuBarDestination) -> Void

    public init(overview: OverviewViewModel, open: @escaping (MenuBarDestination) -> Void) {
        self.overview = overview
        self.open = open
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text(MenuBarPresentation.chargeText(overview.batteryCharge))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                if let state = overview.batteryStateDescription {
                    Text(state).foregroundStyle(.secondary)
                }
                Spacer()
                ProvenanceBadge(overview.batteryCharge.provenance)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("menubar.battery")
            if let minutes = overview.estimatedRuntimeMinutes.value {
                Text("About \(DurationFormatting.string(fromMinutes: minutes)) left (estimate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            // CPU is activity, not battery use: the title says what is shown.
            Text(overview.energyStatus?.energyDataAvailable == true
                 ? String(localized: "Apps using the most energy (estimate)")
                 : String(localized: "Most active apps (CPU)"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if overview.topApps.isEmpty {
                Text("No app is using much right now.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(overview.topApps) { app in
                HStack {
                    Text(app.displayName).lineLimit(1)
                    Spacer()
                    ImpactBadge(impact: app.impact)
                    Text(EnergyPresentation.cpuText(app.cpuPercent)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
            }
            Divider()
            HStack {
                Text("Free space")
                Spacer()
                ProvenanceBadge(overview.storageAvailableBytes.provenance)
                Text(overview.storageAvailableBytes.value.map { ByteFormatting.string(fromByteCount: $0) } ?? "—")
                    .monospacedDigit()
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            Divider()
            HStack(spacing: Spacing.small) {
                Button("Open MacPulse") { open(.overview) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("menubar.open")
                Button("Battery") { open(.battery) }
                Button("Energy") { open(.energy) }
                Button("Space Analyzer") { open(.spaceAnalyzer) }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .accessibilityIdentifier("menubar.quit")
            }
            .controlSize(.small)
        }
        .padding(Spacing.medium)
        .frame(width: 320)
        .task { await overview.loadStorage() }
    }
}

/// Where a menu bar button leads.
public enum MenuBarDestination: Sendable {
    case overview
    case battery
    case energy
    case spaceAnalyzer
}

/// The menu bar label: charge as a number with a battery symbol, never a made-up value.
public struct MenuBarLabel: View {
    private let overview: OverviewViewModel

    public init(overview: OverviewViewModel) {
        self.overview = overview
    }

    public var body: some View {
        let charge = overview.batteryCharge
        HStack(spacing: 2) {
            Image(systemName: MenuBarPresentation.symbol(charge, charging: overview.batteryStatus?.reading.chargingState.value == .charging))
            if let value = charge.value {
                Text(NumberFormatting.percent(value)).monospacedDigit()
            }
        }
        .task { await overview.observeBattery() }
        .task { await overview.observeEnergy() }
    }
}

enum MenuBarPresentation {
    static func chargeText(_ charge: Metric<Double>) -> String {
        charge.value.map { NumberFormatting.percent($0) } ?? "—"
    }

    static func symbol(_ charge: Metric<Double>, charging: Bool) -> String {
        guard let value = charge.value else { return "gauge.with.dots.needle.50percent" }
        if charging { return "battery.100percent.bolt" }
        switch value {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
