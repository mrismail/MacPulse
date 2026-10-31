import AppKit
import MacPulseShared
import SwiftUI

public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        Form {
            Section("Privacy") {
                Label("MacPulse works entirely on this Mac.", systemImage: "lock.shield")
                Text("No account is required. File names, file contents and usage data are never uploaded.")
                    .foregroundStyle(.secondary)
            }

            Section("Coming in later phases") {
                Text("Scan locations and exclusions, monitoring frequency, notifications, cleanup preferences, data retention and startup behavior.")
                    .foregroundStyle(.secondary)
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
            SettingsView(viewModel: SettingsViewModel(systemInfoRepository: PreviewSystemInfoRepository()))
                .frame(width: 600, height: 500)
        }
    }
#endif
