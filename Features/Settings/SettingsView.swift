import AppKit
import MacPulseShared
import SwiftUI

public struct SettingsView: View {
    private let viewModel: SettingsViewModel
    @State private var isConfirmingClearHistory = false
    @State private var isConfirmingClearUsage = false

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section("Privacy") {
                Label("MacPulse works entirely on this Mac.", systemImage: "lock.shield")
                Text("No account is required. File names, file contents and usage data are never uploaded.")
                    .foregroundStyle(.secondary)
                Text("To find apps that drain your battery, MacPulse reads the list of your running apps and how much CPU, memory and energy each uses — the same information Activity Monitor shows. It never reads what's inside your apps or documents, and it can't see other users' or system processes.")
                    .foregroundStyle(.secondary)
            }

            Section("Battery history") {
                Text("MacPulse records the battery level about once a minute while it is running and keeps \(viewModel.batteryHistoryRetentionDays) days of history on this Mac. Old history is removed automatically.")
                    .foregroundStyle(.secondary)
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
                    switch viewModel.clearBatteryHistoryState {
                    case .idle:
                        EmptyView()
                    case .clearing:
                        ProgressView().controlSize(.small)
                    case .cleared:
                        Label("History cleared", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    case .failed(let error):
                        Label(error.userMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if viewModel.canClearUsageHistory {
                Section("App usage history") {
                    Text("MacPulse keeps \(viewModel.usageHistoryRetentionDays) days of hourly CPU and energy use per app, to show trends. It stores app names and locations only — never documents, window titles or what you do in an app.")
                        .foregroundStyle(.secondary)
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
                        switch viewModel.clearUsageHistoryState {
                        case .idle:
                            EmptyView()
                        case .clearing:
                            ProgressView().controlSize(.small)
                        case .cleared:
                            Label("History cleared", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        case .failed(let error):
                            Label(error.userMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
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
                    KeyValueRow("Model", value: info.hardwareModel ?? "Unknown")
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
