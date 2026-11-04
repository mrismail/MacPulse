import AppKit
import MacPulseDomain
import MacPulseShared
import SwiftUI
import UniformTypeIdentifiers

public struct SettingsView: View {
    @Bindable private var viewModel: SettingsViewModel
    private let energy: EnergyViewModel?
    private let spaceAnalyzer: SpaceAnalyzerViewModel?
    @State private var isConfirmingClearHistory = false
    @State private var isConfirmingClearUsage = false
    @State private var isConfirmingClearScans = false
    @State private var isConfirmingClearCleanups = false
    @State private var isPickingExclusion = false

    public init(viewModel: SettingsViewModel, energy: EnergyViewModel? = nil, spaceAnalyzer: SpaceAnalyzerViewModel? = nil) {
        self.viewModel = viewModel
        self.energy = energy
        self.spaceAnalyzer = spaceAnalyzer
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.preferences[keyPath: keyPath] },
            set: { value in viewModel.update { $0[keyPath: keyPath] = value } }
        )
    }

    public var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open MacPulse at login", isOn: Binding(
                    get: { viewModel.opensAtLogin },
                    set: { value in Task { await viewModel.setOpensAtLogin(value) } }
                ))
                .accessibilityIdentifier("settings.openAtLogin")
                if let error = viewModel.loginItemError {
                    Label(error.userMessage, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.secondaryText)
                }
                Toggle("Show MacPulse in the menu bar", isOn: preference(\.showsMenuBarExtra))
                    .accessibilityIdentifier("settings.menuBar")
                Text("While MacPulse is in the menu bar, closing its window keeps it running so battery and app activity are still recorded. Opening at login is off unless you turn it on; you can also change it in System Settings > General > Login Items.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            Section("Monitoring") {
                Picker("Battery level", selection: preference(\.batteryInterval)) {
                    ForEach(AppPreferences.BatteryInterval.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.batteryInterval")
                Picker("App activity in the background", selection: preference(\.activityInterval)) {
                    ForEach(AppPreferences.ActivityInterval.allCases) { Text($0.title).tag($0) }
                }
                Text("While the Energy screen is open, app activity is measured every 10 seconds.")
                    .font(.caption).foregroundStyle(Palette.secondaryText)
                if viewModel.needsRestart {
                    Label("Takes effect the next time MacPulse starts.", systemImage: "arrow.clockwise")
                        .foregroundStyle(Palette.secondaryText)
                        .accessibilityIdentifier("settings.restartNeeded")
                }
            }

            if let energy {
                Section("Notifications") {
                    DrainAlertControls(viewModel: energy)
                }
            }

            if let spaceAnalyzer {
                Section("Scans and cleanup") {
                    Text("Excluded folders are skipped by the Space Analyzer and the Duplicate Finder, and the Cleaner never touches anything in them.")
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                    ForEach(spaceAnalyzer.exclusions, id: \.self) { path in
                        HStack {
                            Label(path, systemImage: "folder.badge.minus").lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Remove") { spaceAnalyzer.removeExclusion(path) }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Exclude a Folder…") { isPickingExclusion = true }
                        .accessibilityIdentifier("settings.addExclusion")
                        .fileImporter(isPresented: $isPickingExclusion, allowedContentTypes: [.folder]) { picked in
                            if case .success(let url) = picked { spaceAnalyzer.addExclusion(url.path) }
                        }
                    Picker("Old downloads are files unchanged for", selection: preference(\.cleanupDownloadsAgeDays)) {
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                    }
                }
            }

            Section("Data retention") {
                Picker("Keep battery history for", selection: preference(\.batteryRetentionDays)) {
                    ForEach(AppPreferences.batteryRetentionChoices, id: \.self) { Text(SettingsPresentation.days($0)).tag($0) }
                }
                Picker("Keep app usage history for", selection: preference(\.usageRetentionDays)) {
                    ForEach(AppPreferences.usageRetentionChoices, id: \.self) { Text(SettingsPresentation.days($0)).tag($0) }
                }
                Text("Scan history is kept 180 days and cleanup history 30 days. Everything stays on this Mac.")
                    .font(.caption).foregroundStyle(Palette.secondaryText)
            }

            Section("Privacy") {
                Label("MacPulse works entirely on this Mac.", systemImage: "lock.shield")
                Text("No account is required. File names, file contents and usage data are never uploaded.")
                    .foregroundStyle(Palette.secondaryText)
                Text("To find apps that drain your battery, MacPulse reads the list of your running apps and how much CPU, memory and energy each uses — the same information Activity Monitor shows. It never reads what's inside your apps or documents, and it can't see other users' or system processes.")
                    .foregroundStyle(Palette.secondaryText)
            }

            Section("Battery history") {
                Text("MacPulse records the battery level \(viewModel.preferencesAtLaunch.batteryInterval.inSentence) while it is running and keeps \(viewModel.batteryHistoryRetentionDays) days of history on this Mac. Old history is removed automatically.")
                    .foregroundStyle(Palette.secondaryText)
                HStack {
                    Button("Clear Battery History…", role: .destructive) {
                        isConfirmingClearHistory = true
                    }
                    .disabled(viewModel.clearBatteryHistoryState == .clearing)
                    .accessibilityIdentifier("settings.clearBatteryHistory")
                    .confirmationDialog(
                        "Clear all battery history?",
                        isPresented: $isConfirmingClearHistory,
                        titleVisibility: .visible
                    ) {
                        Button("Clear History", role: .destructive) {
                            Task { await viewModel.clearBatteryHistory() }
                        }
                    } message: {
                        Text("Charts and charging sessions start again from now. Your battery itself is not affected.")
                    }
                    ClearStateLabel(state: viewModel.clearBatteryHistoryState)
                }
            }

            if viewModel.canClearUsageHistory {
                Section("App usage history") {
                    Text("MacPulse keeps \(viewModel.usageHistoryRetentionDays) days of hourly CPU and energy use per app, to show trends. It stores app names and locations only — never documents, window titles or what you do in an app.")
                        .foregroundStyle(Palette.secondaryText)
                    HStack {
                        Button("Clear App Usage History…", role: .destructive) {
                            isConfirmingClearUsage = true
                        }
                        .disabled(viewModel.clearUsageHistoryState == .clearing)
                        .accessibilityIdentifier("settings.clearUsageHistory")
                        .confirmationDialog(
                            "Clear all app usage history?",
                            isPresented: $isConfirmingClearUsage,
                            titleVisibility: .visible
                        ) {
                            Button("Clear Usage History", role: .destructive) {
                                Task { await viewModel.clearUsageHistory() }
                            }
                        } message: {
                            Text("Per-app trends start again from now.")
                        }
                        ClearStateLabel(state: viewModel.clearUsageHistoryState)
                    }
                }
            }

            if viewModel.canClearScanHistory || viewModel.canClearCleanupHistory {
                Section("Scan and cleanup history") {
                    if viewModel.canClearScanHistory {
                        HStack {
                            Button("Clear Scan History…", role: .destructive) { isConfirmingClearScans = true }
                                .accessibilityIdentifier("settings.clearScanHistory")
                                .disabled(viewModel.clearScanHistoryState == .clearing)
                                .confirmationDialog("Clear all scan history?", isPresented: $isConfirmingClearScans, titleVisibility: .visible) {
                                    Button("Clear Scan History", role: .destructive) { Task { await viewModel.clearScanHistory() } }
                                } message: {
                                    Text("Size comparisons start again from your next scan. No files are touched.")
                                }
                            ClearStateLabel(state: viewModel.clearScanHistoryState)
                        }
                    }
                    if viewModel.canClearCleanupHistory {
                        HStack {
                            Button("Clear Cleanup History…", role: .destructive) { isConfirmingClearCleanups = true }
                                .accessibilityIdentifier("settings.clearCleanupHistory")
                                .disabled(viewModel.clearCleanupHistoryState == .clearing)
                                .confirmationDialog("Clear all cleanup history?", isPresented: $isConfirmingClearCleanups, titleVisibility: .visible) {
                                    Button("Clear Cleanup History", role: .destructive) { Task { await viewModel.clearCleanupHistory() } }
                                } message: {
                                    Text("Items already in the Trash stay there, but MacPulse can no longer put them back for you. Finder's Put Back still works.")
                                }
                            ClearStateLabel(state: viewModel.clearCleanupHistoryState)
                        }
                    }
                }
            }

            Section("About") {
                switch viewModel.systemInfo {
                case .idle, .loading:
                    ProgressView().controlSize(.small)
                case .loaded(let info):
                    KeyValueRow("Version", value: info.appVersionDescription)
                    KeyValueRow("macOS", value: info.macOSVersion)
                    KeyValueRow("Model", value: info.hardwareModel ?? String(localized: "Unknown"))
                    KeyValueRow("Processor", value: "\(info.architectureDescription), \(info.processorCount) cores")
                    KeyValueRow("Memory", value: info.memoryDescription)
                case .failed(let error):
                    Label(error.userMessage, systemImage: "exclamationmark.triangle")
                }
                if let diagnostics = viewModel.diagnosticsText {
                    Button("Copy Diagnostics") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diagnostics, forType: .string)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task { await viewModel.load() }
        .task { await viewModel.loadLoginItem() }
    }
}

enum SettingsPresentation {
    /// "30 days", formatted by the locale (plural rules and digits included).
    static func days(_ count: Int) -> String {
        Duration.seconds(count * 86_400).formatted(.units(allowed: [.days], width: .wide))
    }
}

private struct ClearStateLabel: View {
    let state: SettingsViewModel.ClearHistoryState

    var body: some View {
        switch state {
        case .idle: EmptyView()
        case .clearing: ProgressView().controlSize(.small)
        case .cleared: Label("History cleared", systemImage: "checkmark.circle").foregroundStyle(Palette.secondaryText)
        case .failed(let error): Label(error.userMessage, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.secondaryText)
        }
    }
}

#if DEBUG
    struct SettingsView_Previews: PreviewProvider {
        static var previews: some View {
            SettingsView(viewModel: SettingsViewModel(
                systemInfoRepository: PreviewSystemInfoRepository(),
                batteryMonitor: PreviewBatteryMonitor()
            ))
                .frame(width: 600, height: 500)
        }
    }
#endif
