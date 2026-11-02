import AppKit
import Charts
import MacPulseDomain
import MacPulseShared
import SwiftUI

// MARK: - Scan controls

struct ScanControlsCard: View {
    @Bindable var viewModel: SpaceAnalyzerViewModel
    let pickFolder: () -> Void

    var body: some View {
        Card("Scan", systemImage: "magnifyingglass") {
            HStack(spacing: Spacing.small) {
                Button("Scan Home Folder") { viewModel.scanHomeFolder() }
                    .accessibilityIdentifier("space.scanHome")
                if let volume = viewModel.selectedVolume {
                    Button("Scan \(volume.name)") { viewModel.scanSelectedVolume() }
                        .accessibilityIdentifier("space.scanVolume")
                }
                Button("Choose Folder…", action: pickFolder)
                    .accessibilityIdentifier("space.chooseFolder")
                Spacer()
                if viewModel.isScanning {
                    Button("Stop", role: .cancel) { viewModel.cancelScan() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("space.cancel")
                }
            }
            if case .scanning(let progress) = viewModel.state {
                HStack(spacing: Spacing.small) {
                    ProgressView().controlSize(.small)
                    Text("\(NumberFormatting.integer(progress.itemsScanned)) items · \(ByteFormatting.string(fromByteCount: progress.allocatedBytes))")
                        .monospacedDigit()
                    Text(progress.currentFolder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("space.progress")
            } else {
                Text("Scans only read file sizes; nothing is changed. Desktop, Documents, Downloads and other apps' data are skipped unless you choose them, so macOS doesn't ask for permission unexpectedly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("space.controls")
    }
}

// MARK: - Summary

struct ScanSummaryCard: View {
    let result: ScanResult
    @Bindable var viewModel: SpaceAnalyzerViewModel
    let pickFolder: () -> Void

    var body: some View {
        Card(result.isComplete ? String(localized: "Scan Results") : String(localized: "Partial Results (stopped)"), systemImage: "chart.bar.doc.horizontal") {
            Text(result.rootPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            HStack(alignment: .top, spacing: Spacing.large) {
                MetricValueView("Size on disk", metric: result.allocatedBytes) { ByteFormatting.string(fromByteCount: $0) }
                MetricValueView("File size", metric: Metric<Int64>.measured(result.root.logicalBytes)) { ByteFormatting.string(fromByteCount: $0) }
                MetricValueView("Files", metric: Metric<Int>.measured(result.root.fileCount)) { NumberFormatting.integer($0) }
                MetricValueView("Recoverable", metric: result.recoverableBytes) { ByteFormatting.string(fromByteCount: $0) }
            }
            Text("Size on disk is the space files occupy; file size is what the files contain. Files that share storage (APFS clones, hard links) are counted once where macOS reports it, so removing a file can free less than its size.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !viewModel.skippedSummary.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text("Not scanned").font(.subheadline.weight(.semibold))
                    ForEach(viewModel.skippedSummary) { entry in
                        Text("\(SpacePresentation.skipTitle(entry.reason)): \(entry.count)")
                            .font(.callout)
                    }
                    if !viewModel.skippedProtectedFolders.isEmpty {
                        Button("Choose a Protected Folder to Scan…", action: pickFolder)
                            .accessibilityIdentifier("space.chooseProtected")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("space.skipped")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("space.summary")
    }
}

// MARK: - Folder tree

struct FolderTreeCard: View {
    @Bindable var viewModel: SpaceAnalyzerViewModel
    @State private var selection: ScanNode.ID?

    var body: some View {
        Card("Folders", systemImage: "folder") {
            HStack(spacing: Spacing.xSmall) {
                Button {
                    viewModel.goUp()
                } label: {
                    Label("Up", systemImage: "chevron.up")
                }
                .disabled(viewModel.breadcrumb.count < 2)
                .accessibilityIdentifier("space.up")
                ForEach(viewModel.breadcrumb) { node in
                    Button(node.name) { viewModel.open(node.id) }
                        .buttonStyle(.link)
                    if node.id != viewModel.breadcrumb.last?.id {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("space.breadcrumb")
            let parentSize = max(1, viewModel.currentFolder?.allocatedBytes ?? 1)
            Table(viewModel.folderContents, selection: $selection, sortOrder: $viewModel.folderSortOrder) {
                TableColumn("Name", value: \.name) { node in
                    Label(node.name, systemImage: SpacePresentation.symbol(node))
                        .foregroundStyle(node.kind == .otherFiles ? .secondary : .primary)
                        .accessibilityIdentifier("space.node.\(node.name)")
                }
                .width(min: 200, ideal: 320)
                TableColumn("Size on disk", value: \.allocatedBytes) { node in
                    HStack {
                        Text(ByteFormatting.string(fromByteCount: node.allocatedBytes)).monospacedDigit()
                        Spacer()
                        ProgressView(value: Double(node.allocatedBytes), total: Double(parentSize))
                            .frame(width: 60)
                            .accessibilityHidden(true)
                    }
                }
                .width(min: 140, ideal: 170)
                TableColumn("File size", value: \.logicalBytes) { node in
                    Text(ByteFormatting.string(fromByteCount: node.logicalBytes)).monospacedDigit()
                }
                .width(min: 80, ideal: 100)
                TableColumn("Files", value: \.fileCount) { node in
                    Text(NumberFormatting.integer(node.fileCount)).monospacedDigit()
                }
                .width(min: 60, ideal: 80)
            }
            .contextMenu(forSelectionType: ScanNode.ID.self) { ids in
                if let id = ids.first, let node = viewModel.currentFolder?.children?.first(where: { $0.id == id }), let path = node.path {
                    Button("Reveal in Finder") { SpacePresentation.reveal(path) }
                    if node.kind == .folder {
                        Button("Open") { viewModel.open(id) }
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first { viewModel.open(id) }
            }
            .frame(minHeight: 260)
            .accessibilityIdentifier("space.tree")
            Text("Double-click a folder to open it. Only the largest files of each folder are listed; the rest are summed as smaller files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Largest files

struct LargestFilesCard: View {
    @Bindable var viewModel: SpaceAnalyzerViewModel
    @State private var selection: ScanNode.ID?

    var body: some View {
        Card("Largest Files", systemImage: "doc.text.magnifyingglass") {
            HStack {
                Picker("Type", selection: $viewModel.categoryFilter) {
                    Text("All types").tag(FileCategory?.none)
                    ForEach(FileCategory.allCases) { category in
                        Text(category.title).tag(FileCategory?.some(category))
                    }
                }
                .frame(maxWidth: 220)
                .accessibilityIdentifier("space.typeFilter")
                Picker("Size", selection: $viewModel.sizeFilter) {
                    ForEach(FileSizeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(maxWidth: 200)
                .accessibilityIdentifier("space.sizeFilter")
            }
            Table(viewModel.largestFiles, selection: $selection, sortOrder: $viewModel.fileSortOrder) {
                TableColumn("Name", value: \.name) { node in
                    Label(node.name, systemImage: SpacePresentation.symbol(node))
                        .help(node.id)
                }
                .width(min: 180, ideal: 260)
                TableColumn("Size on disk", value: \.allocatedBytes) { node in
                    Text(ByteFormatting.string(fromByteCount: node.allocatedBytes)).monospacedDigit()
                }
                .width(min: 80, ideal: 100)
                TableColumn("Type") { node in
                    Text(node.category?.title ?? "—")
                }
                .width(min: 80, ideal: 110)
                TableColumn("Folder") { node in
                    Text((node.id as NSString).deletingLastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }
            .contextMenu(forSelectionType: ScanNode.ID.self) { ids in
                if let id = ids.first {
                    Button("Reveal in Finder") { SpacePresentation.reveal(id) }
                }
            } primaryAction: { ids in
                if let id = ids.first { SpacePresentation.reveal(id) }
            }
            .frame(minHeight: 260)
            .accessibilityIdentifier("space.largestFiles")
        }
    }
}

// MARK: - Categories

struct CategoriesCard: View {
    let result: ScanResult

    var body: some View {
        Card("Categories", systemImage: "square.grid.2x2") {
            Chart(result.categories) { total in
                BarMark(
                    x: .value("Size on disk", total.allocatedBytes),
                    y: .value("Category", total.category.title)
                )
                .foregroundStyle(total.category.isTypicallyRecoverable ? Color.orange : Color.accentColor)
                .annotation(position: .trailing) {
                    Text(ByteFormatting.string(fromByteCount: total.allocatedBytes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(max(1, result.categories.count)) * 28 + 20)
            .accessibilityIdentifier("space.categories")
            Text("Orange categories are usually safe to clean up. Categories come from file names and locations; contents are never read.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Presentation

enum SpacePresentation {
    static func symbol(_ node: ScanNode) -> String {
        switch node.kind {
        case .folder: "folder"
        case .package: "shippingbox"
        case .otherFiles: "ellipsis.circle"
        case .file:
            switch node.category {
            case .video: "film"
            case .audio: "music.note"
            case .images: "photo"
            case .archives: "archivebox"
            case .applications: "app"
            case .documents: "doc.text"
            case .caches, .temporary, .logs, .trash: "clock.arrow.circlepath"
            default: "doc"
            }
        }
    }

    static func skipTitle(_ reason: SkipReason) -> String {
        switch reason {
        case .excludedByUser: String(localized: "Excluded by you")
        case .systemLocation: String(localized: "System locations")
        case .protectedByPrivacy: String(localized: "Protected by macOS privacy (choose them to scan)")
        case .noPermission: String(localized: "No permission to read")
        case .otherVolume: String(localized: "On another volume")
        case .linkOrLoop: String(localized: "Links and already-counted folders")
        }
    }

    /// Selects the item in Finder. Read-only: nothing is opened or changed.
    @MainActor
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
