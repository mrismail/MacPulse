import AppKit
import MacPulseDomain
import MacPulseShared
import SwiftUI
import UniformTypeIdentifiers

/// Cleaner: review a category, select items, confirm, move them to the Trash, see the
/// result. Nothing is moved without the confirmation dialog.
public struct CleanerView: View {
    @Bindable private var viewModel: CleanerViewModel
    @State private var pickingFolder = false

    public init(viewModel: CleanerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            List(selection: Binding(
                get: { viewModel.selectedCategory },
                set: { if let category = $0 { viewModel.select(category) } }
            )) {
                ForEach(CleanupCategory.allCases) { category in
                    Label(category.title, systemImage: category.systemImage)
                        .tag(category)
                        .accessibilityIdentifier("cleaner.category.\(category.rawValue)")
                }
            }
            .frame(width: 200)
            // Changing category during a cleanup would leave its result under the wrong one.
            .disabled(viewModel.isCleaning)
            .accessibilityIdentifier("cleaner.categories")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    CategoryReviewCard(viewModel: viewModel, pickFolder: { pickingFolder = true })
                    if case .finished(let report) = viewModel.phase {
                        CleanupResultCard(report: report, viewModel: viewModel)
                    }
                    if !viewModel.history.isEmpty {
                        CleanupHistoryCard(viewModel: viewModel)
                    }
                }
                .padding(Spacing.large)
            }
        }
        .navigationTitle("Cleaner")
        .task { await viewModel.loadHistory() }
        // The age is shared with Settings; a change there lists old downloads again.
        .onChange(of: viewModel.minimumAgeDays) { viewModel.ageDaysChanged() }
        .confirmationDialog(
            CleanerPresentation.confirmationTitle(viewModel.phase),
            isPresented: Binding(
                get: { if case .confirming = viewModel.phase { true } else { false } },
                set: { if !$0 { viewModel.cancelCleanup() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { viewModel.confirmCleanup() }
                .accessibilityIdentifier("cleaner.confirm")
            // Escape cancels; nothing is moved by pressing a key alone.
            Button("Cancel", role: .cancel) { viewModel.cancelCleanup() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("cleaner.cancelConfirm")
        } message: {
            Text("Each item is checked again just before it is moved. You can put items back from the Trash until it is emptied.")
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { picked in
            guard case .success(let url) = picked else { return }
            if viewModel.selectedCategory == .oldDownloads {
                viewModel.chooseDownloadsFolder(url.path)
            } else {
                viewModel.chooseEmptyFoldersRoot(url.path)
            }
        }
    }
}

// MARK: - Review

private struct CategoryReviewCard: View {
    @Bindable var viewModel: CleanerViewModel
    let pickFolder: () -> Void

    var body: some View {
        let category = viewModel.selectedCategory
        Card(category.title, systemImage: category.systemImage) {
            Text(category.summary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            options(for: category)
            if category == .trash {
                Button("Open Trash in Finder") { CleanerPresentation.open(viewModel.trashPath) }
                    .accessibilityIdentifier("cleaner.openTrash")
            }
            HStack {
                Button(viewModel.list == nil ? "Review" : "Refresh") {
                    viewModel.startReview()
                }
                .disabled(viewModel.needsFolder || viewModel.phase == .loading || viewModel.isCleaning)
                .accessibilityIdentifier("cleaner.review")
                if viewModel.phase == .loading {
                    ProgressView().controlSize(.small)
                }
            }
            if let pickError = viewModel.pickError {
                Label(pickError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("cleaner.pickError")
            }
            if let list = viewModel.list {
                if let reason = list.unavailableReason {
                    Label(reason, systemImage: "info.circle").foregroundStyle(.secondary)
                }
                if let note = list.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if !list.candidates.isEmpty {
                    CandidateTable(viewModel: viewModel)
                    selectionBar
                } else if list.unavailableReason == nil {
                    Label("Nothing to clean here.", systemImage: "checkmark.circle")
                        .accessibilityIdentifier("cleaner.nothing")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cleaner.review.card")
    }

    @ViewBuilder
    private func options(for category: CleanupCategory) -> some View {
        switch category {
        case .oldDownloads:
            HStack {
                Button(viewModel.downloadsFolder == nil ? "Choose Downloads Folder…" : "Change Folder…", action: pickFolder)
                    .accessibilityIdentifier("cleaner.chooseFolder")
                if let folder = viewModel.downloadsFolder {
                    Text(folder).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Unchanged for", selection: Binding(get: { viewModel.minimumAgeDays }, set: { viewModel.setMinimumAgeDays($0) })) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                }
                .frame(maxWidth: 220)
            }
        case .emptyFolders:
            HStack {
                Button(viewModel.emptyFoldersRoot == nil ? "Choose Folder…" : "Change Folder…", action: pickFolder)
                    .accessibilityIdentifier("cleaner.chooseFolder")
                if let folder = viewModel.emptyFoldersRoot {
                    Text(folder).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                }
            }
        default:
            EmptyView()
        }
    }

    private var selectionBar: some View {
        HStack(spacing: Spacing.small) {
            Button("Select All") { viewModel.selectAll() }
                .disabled(viewModel.isReadOnlyCategory)
            Button("Select None") { viewModel.selectNone() }
            Spacer()
            if case .cleaning(let done, let total) = viewModel.phase {
                ProgressView(value: Double(done), total: Double(max(1, total))).frame(width: 140)
                Button("Stop") { viewModel.stopCleanup() }
            } else {
                Text("\(viewModel.selectedCandidates.count) selected · \(ByteFormatting.string(fromByteCount: viewModel.selectedBytes.value ?? 0))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cleaner.selectionSummary")
                Button("Move to Trash…") { viewModel.requestCleanup() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!viewModel.canRequestCleanup)
                    .accessibilityIdentifier("cleaner.moveToTrash")
            }
        }
    }
}

private struct CandidateTable: View {
    @Bindable var viewModel: CleanerViewModel
    /// Row highlight for the context menu; separate from the checkboxes that choose items.
    @State private var highlighted: Set<CleanupCandidate.ID> = []

    var body: some View {
        Table(viewModel.candidates, selection: $highlighted) {
            TableColumn("") { candidate in
                Toggle("Select \(candidate.name)", isOn: Binding(
                    get: { viewModel.isSelected(candidate) },
                    set: { _ in viewModel.toggle(candidate) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("cleaner.select.\(candidate.name)")
            }
            .width(28)
            TableColumn("Item") { candidate in
                VStack(alignment: .leading, spacing: 0) {
                    Label(candidate.name, systemImage: candidate.isFolder ? "folder" : "doc")
                    Text(candidate.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let warning = candidate.warning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .help(candidate.path)
            }
            .width(min: 260, ideal: 420)
            TableColumn("Size") { candidate in
                Text(ByteFormatting.string(fromByteCount: candidate.allocatedBytes)).monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            TableColumn("Modified") { candidate in
                Text(candidate.modified?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 110)
        }
        .contextMenu(forSelectionType: CleanupCandidate.ID.self) { ids in
            if let id = ids.first {
                Button("Reveal in Finder") { CleanerPresentation.reveal(id) }
            }
        }
        .frame(minHeight: 280)
        .accessibilityIdentifier("cleaner.candidates")
    }
}

// MARK: - Result and history

private struct CleanupResultCard: View {
    let report: CleanupReport
    @Bindable var viewModel: CleanerViewModel

    var body: some View {
        Card(report.isComplete ? String(localized: "Cleanup Finished") : String(localized: "Cleanup Stopped"), systemImage: "checkmark.circle") {
            Text(CleanerPresentation.summary(report))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("cleaner.result.summary")
            Text("The space is freed when you empty the Trash. Until then you can put items back.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !report.notMoved.isEmpty {
                Text("Not moved").font(.subheadline.weight(.semibold))
                ForEach(report.notMoved) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 0) {
                            Text((item.path as NSString).lastPathComponent)
                            Text(CleanerPresentation.explanation(item.outcome)).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    }
                }
            }
            HStack {
                Button("Open Trash in Finder") { CleanerPresentation.open(viewModel.trashPath) }
                Button("Done") { viewModel.dismissResult() }
                    .accessibilityIdentifier("cleaner.result.done")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cleaner.result")
    }
}

private struct CleanupHistoryCard: View {
    @Bindable var viewModel: CleanerViewModel

    var body: some View {
        Card("Cleanup History", systemImage: "clock.arrow.circlepath") {
            if let error = viewModel.historyError {
                Label(error.userMessage, systemImage: "exclamationmark.triangle")
            }
            if let message = viewModel.putBackError {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            ForEach(viewModel.history.prefix(20)) { report in
                DisclosureGroup {
                    ForEach(report.items) { item in
                        HStack {
                            Text((item.path as NSString).lastPathComponent).lineLimit(1)
                            Spacer()
                            if item.outcome.isMoved {
                                Button("Put Back") { Task { await viewModel.putBack(item, in: report) } }
                                    .accessibilityIdentifier("cleaner.putBack.\((item.path as NSString).lastPathComponent)")
                            } else {
                                Text(CleanerPresentation.explanation(item.outcome)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .help(item.path)
                    }
                } label: {
                    HStack {
                        Image(systemName: report.category.systemImage).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(report.category.title)
                            Text(report.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(CleanerPresentation.summary(report)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Kept for 30 days on this Mac, including where each item went in the Trash.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cleaner.history")
    }
}

// MARK: - Presentation

enum CleanerPresentation {
    static func confirmationTitle(_ phase: CleanerViewModel.Phase) -> String {
        guard case .confirming(let items) = phase else { return "" }
        let size = ByteFormatting.string(fromByteCount: items.map(\.allocatedBytes).reduce(0, +))
        return items.count == 1
            ? String(localized: "Move 1 item (\(size)) to the Trash?")
            : String(localized: "Move \(items.count) items (\(size)) to the Trash?")
    }

    /// Whole localized phrases joined with the locale's list format (no hand-made
    /// concatenation, so translations can reorder words).
    static func summary(_ report: CleanupReport) -> String {
        let size = ByteFormatting.string(fromByteCount: report.bytesMovedToTrash)
        var parts = [String(localized: "\(report.moved.count) moved to the Trash (\(size))")]
        let skipped = report.items.filter { if case .skipped = $0.outcome { true } else { false } }.count
        let failed = report.items.filter { if case .failed = $0.outcome { true } else { false } }.count
        let restored = report.items.filter { $0.outcome == .putBack }.count
        if skipped > 0 { parts.append(String(localized: "\(skipped) skipped")) }
        if failed > 0 { parts.append(String(localized: "\(failed) failed")) }
        if restored > 0 { parts.append(String(localized: "\(restored) put back")) }
        return parts.formatted(.list(type: .and))
    }

    static func explanation(_ outcome: CleanupItemOutcome) -> String {
        switch outcome {
        case .movedToTrash: String(localized: "Moved to the Trash.")
        case .skipped(.missing): String(localized: "Skipped: it no longer exists.")
        case .skipped(.changed): String(localized: "Skipped: it changed since the preview, so it was left alone.")
        case .skipped(.notAllowed): String(localized: "Skipped: MacPulse never removes this kind of item.")
        case .skipped(.keptCopyChanged): String(localized: "Skipped: the copy that was to be kept is gone or changed, so this one was kept too.")
        case .skipped(.notEmpty): String(localized: "Skipped: the folder isn't empty anymore.")
        case .failed(let message): String(localized: "macOS didn't move it: \(message)")
        case .putBack: String(localized: "Put back where it was.")
        }
    }

    static func putBackMessage(_ failure: PutBackFailure) -> String {
        switch failure {
        case .notInTrash: String(localized: "It is no longer in the Trash.")
        case .originalPlaceTaken: String(localized: "Something else now has its name in the original folder.")
        case .originalFolderMissing: String(localized: "The folder it came from no longer exists.")
        case .notAllowed: String(localized: "MacPulse can't put items back in that place.")
        case .differentItem: String(localized: "A different item now has that name in the Trash, so it was left alone.")
        case .notVerifiable: String(localized: "This cleanup is from an older version of MacPulse, which didn't record exactly which item it moved. Use Put Back in the Trash in Finder.")
        case .trashNotReadable: String(localized: "macOS doesn't let MacPulse look inside the Trash. Use Put Back in the Trash in Finder, or allow Full Disk Access in System Settings.")
        case .failed(let message): String(localized: "macOS didn't move it back: \(message)")
        }
    }

    static func isCleaning(_ phase: CleanerViewModel.Phase) -> Bool {
        if case .cleaning = phase { return true }
        return false
    }

    @MainActor
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Opens a folder in Finder (e.g. the Trash). Read-only.
    @MainActor
    static func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}
