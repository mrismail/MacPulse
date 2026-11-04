import AppKit
import MacPulseDomain
import MacPulseShared
import QuickLook
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Duplicate Finder: choose folders, search, review verified groups and mark copies.
/// Review only in this phase: nothing is removed.
public struct DuplicateFinderView: View {
    @Bindable private var viewModel: DuplicateFinderViewModel
    @State private var isPickingFolders = false
    @State private var previewURL: URL?
    private let reviewInCleaner: () -> Void

    public init(viewModel: DuplicateFinderViewModel, reviewInCleaner: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.reviewInCleaner = reviewInCleaner
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                SearchSetupCard(viewModel: viewModel, pickFolders: { isPickingFolders = true })
                if let result = viewModel.result {
                    DuplicateSummaryCard(result: result, viewModel: viewModel, reviewInCleaner: reviewInCleaner)
                    DuplicateGroupsCard(viewModel: viewModel, preview: { previewURL = URL(fileURLWithPath: $0) })
                }
            }
            .padding(Spacing.large)
        }
        .navigationTitle("Duplicate Finder")
        .quickLookPreview($previewURL)
        .fileImporter(isPresented: $isPickingFolders, allowedContentTypes: [.folder], allowsMultipleSelection: true) { picked in
            if case .success(let urls) = picked {
                urls.forEach { viewModel.addFolder($0.path) }
            }
        }
    }
}

// MARK: - Setup

private struct SearchSetupCard: View {
    @Bindable var viewModel: DuplicateFinderViewModel
    let pickFolders: () -> Void

    var body: some View {
        Card("Search", systemImage: "doc.on.doc") {
            if viewModel.folders.isEmpty {
                Text("Choose the folders to search. Desktop, Documents and Downloads are searched only when you choose them, so macOS can ask you once.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(viewModel.folders, id: \.self) { folder in
                HStack {
                    Label(folder, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        viewModel.removeFolder(folder)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(folder)")
                    .disabled(viewModel.isSearching)
                }
            }
            HStack(spacing: Spacing.small) {
                Button("Add Folders…", action: pickFolders)
                    .accessibilityIdentifier("duplicates.addFolders")
                Button("Add Home Folder") { viewModel.addFolder(viewModel.homeFolder) }
                    .accessibilityIdentifier("duplicates.addHome")
                Picker("Minimum size", selection: $viewModel.minimumSize) {
                    ForEach(DuplicateMinimumSize.allCases) { Text($0.title).tag($0) }
                }
                .frame(maxWidth: 220)
                Picker("Type", selection: $viewModel.searchCategory) {
                    Text("All types").tag(FileCategory?.none)
                    ForEach(DuplicatePresentation.searchableCategories) { Text($0.title).tag(FileCategory?.some($0)) }
                }
                .frame(maxWidth: 220)
            }
            .disabled(viewModel.isSearching)
            HStack(spacing: Spacing.small) {
                Button("Find Duplicates") { viewModel.search() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSearch)
                    .accessibilityIdentifier("duplicates.search")
                if viewModel.isSearching {
                    Button("Stop", role: .cancel) { viewModel.cancelSearch() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("duplicates.cancel")
                }
            }
            if case .searching(let progress) = viewModel.state {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    if let fraction = progress.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    Text("\(progress.stage.title) · \(ByteFormatting.string(fromByteCount: progress.bytesRead)) read")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("duplicates.progress")
            }
            Text("Files are compared by content: same size, then a SHA-256 of the start and end, then of the whole file, then byte by byte. Names and dates are never used. Nothing is changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("duplicates.setup")
    }
}

// MARK: - Summary

private struct DuplicateSummaryCard: View {
    let result: DuplicateScanResult
    @Bindable var viewModel: DuplicateFinderViewModel
    let reviewInCleaner: () -> Void

    var body: some View {
        Card(result.isComplete ? String(localized: "Results") : String(localized: "Partial Results (stopped)"), systemImage: "checkmark.seal") {
            HStack(alignment: .top, spacing: Spacing.large) {
                MetricValueView("Duplicate groups", metric: Metric<Int>.measured(result.groups.count)) { NumberFormatting.integer($0) }
                MetricValueView("Extra copies", metric: Metric<Int>.measured(result.extraCopies)) { NumberFormatting.integer($0) }
                MetricValueView("Potential savings", metric: result.potentialSavings) { ByteFormatting.string(fromByteCount: $0) }
                MetricValueView("Marked for removal", metric: viewModel.markedSavings) { ByteFormatting.string(fromByteCount: $0) }
            }
            Text(DuplicatePresentation.funnel(result.statistics))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.small) {
                Menu("Mark Copies") {
                    Button("Keep the Newest in Each Group") { viewModel.markAllExcept(.newest) }
                    Button("Keep the Oldest in Each Group") { viewModel.markAllExcept(.oldest) }
                    Divider()
                    Button("Clear Marks") { viewModel.clearMarks() }
                }
                .fixedSize()
                .accessibilityIdentifier("duplicates.markMenu")
                Button("Reveal Marked in Finder") { DuplicatePresentation.reveal(viewModel.markedPaths) }
                    .disabled(viewModel.markedCount == 0)
                    .accessibilityIdentifier("duplicates.revealMarked")
                Button("Review Marked in Cleaner…", action: reviewInCleaner)
                    .disabled(viewModel.markedCount == 0)
                    .accessibilityIdentifier("duplicates.reviewInCleaner")
                Spacer()
                Text("\(viewModel.markedCount) marked")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("duplicates.markedCount")
            }
            Text("Marking is a plan: nothing is removed here. The Cleaner shows the marked copies, asks you to confirm, checks each file again and moves it to the Trash.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("duplicates.summary")
    }
}

// MARK: - Groups

private struct DuplicateGroupsCard: View {
    @Bindable var viewModel: DuplicateFinderViewModel
    let preview: (String) -> Void

    var body: some View {
        Card("Duplicate Groups", systemImage: "square.stack.3d.up") {
            HStack(spacing: Spacing.small) {
                Picker("Type", selection: $viewModel.resultCategory) {
                    Text("All types").tag(FileCategory?.none)
                    ForEach(FileCategory.allCases) { Text($0.title).tag(FileCategory?.some($0)) }
                }
                .frame(maxWidth: 200)
                Picker("Size", selection: $viewModel.resultMinimumSize) {
                    ForEach(DuplicateMinimumSize.allCases) { Text($0.title).tag($0) }
                }
                .frame(maxWidth: 200)
                TextField("Filter by location", text: $viewModel.locationFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .accessibilityIdentifier("duplicates.locationFilter")
            }
            // Filtered once per update, not once per use.
            let groups = viewModel.groups
            if groups.isEmpty {
                ContentUnavailableView(
                    "No Duplicates",
                    systemImage: "checkmark.circle",
                    description: Text("No files with identical contents match.")
                )
            }
            LazyVStack(alignment: .leading, spacing: Spacing.medium) {
                ForEach(groups) { group in
                    DuplicateGroupView(group: group, viewModel: viewModel, preview: preview)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("duplicates.groups")
    }
}

private struct DuplicateGroupView: View {
    let group: DuplicateGroup
    @Bindable var viewModel: DuplicateFinderViewModel
    let preview: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack {
                Text(group.files.first?.name ?? "—").font(.headline)
                Text("\(group.files.count) copies · \(ByteFormatting.string(fromByteCount: group.logicalBytesPerFile)) each")
                    .foregroundStyle(.secondary)
                Spacer()
                if let savings = group.potentialSavings.value {
                    let size = ByteFormatting.string(fromByteCount: savings)
                    Text(group.potentialSavings.isMeasured
                        ? String(localized: "Saves \(size)")
                        : String(localized: "Saves about \(size) (estimate)"))
                        .monospacedDigit()
                }
            }
            ForEach(group.files) { file in
                DuplicateFileRow(file: file, group: group, viewModel: viewModel, preview: preview)
            }
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("duplicates.group.\(group.contentHash.prefix(12))")
    }
}

private struct DuplicateFileRow: View {
    let file: DuplicateFile
    let group: DuplicateGroup
    @Bindable var viewModel: DuplicateFinderViewModel
    let preview: (String) -> Void

    var body: some View {
        HStack(spacing: Spacing.small) {
            Toggle(isOn: Binding(
                get: { viewModel.isMarked(file) },
                set: { _ in viewModel.toggle(file, in: group) }
            )) {
                Text("Remove")
            }
            // Copies usually share a name: VoiceOver and tests need the folder too.
            .accessibilityLabel(String(localized: "Remove \(file.name) in \(file.folder)"))
            .toggleStyle(.checkbox)
            .disabled(!viewModel.canMark(file, in: group))
            .help(viewModel.canMark(file, in: group)
                ? String(localized: "Mark this copy for removal")
                : String(localized: "At least one copy is always kept"))
            .accessibilityIdentifier(DuplicatePresentation.markIdentifier(file, home: viewModel.homeFolder))
            FileThumbnail(path: file.path, category: file.category)
            VStack(alignment: .leading, spacing: 0) {
                // Marked copies are struck through and labelled, not just dimmed.
                HStack(spacing: Spacing.xSmall) {
                    Text(file.name).strikethrough(viewModel.isMarked(file))
                    if viewModel.isMarked(file) {
                        Text("Marked for removal").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(file.folder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !file.hardLinkPaths.isEmpty {
                    Text(file.hardLinkPaths.count == 1
                        ? String(localized: "Also linked at 1 other place; removing this path alone frees nothing.")
                        : String(localized: "Also linked at \(file.hardLinkPaths.count) other places; removing this path alone frees nothing."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if let modified = file.modified {
                Text(modified.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
            }
            Text(ByteFormatting.string(fromByteCount: file.allocatedBytes)).monospacedDigit()
        }
        .contextMenu {
            Button("Quick Look") { preview(file.path) }
            Button("Reveal in Finder") { DuplicatePresentation.reveal([file.path]) }
        }
    }
}

/// A Quick Look thumbnail for images and videos; an icon otherwise.
private struct FileThumbnail: View {
    let path: String
    let category: FileCategory
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: category == .images ? "photo" : category == .video ? "film" : "doc")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
        .task(id: path) {
            guard category == .images || category == .video else { return }
            image = await DuplicatePresentation.thumbnail(for: path)
        }
        // Leaving the screen (or scrolling past in a lazy stack) cancels the request.
    }
}

// MARK: - Presentation

enum DuplicatePresentation {
    static let searchableCategories: [FileCategory] = [.images, .video, .audio, .documents, .archives, .applications, .developer, .other]

    static func funnel(_ statistics: DuplicateScanStatistics) -> String {
        var text = String(localized: "\(statistics.filesConsidered) files considered · \(statistics.sameSizeFiles) shared a size · \(statistics.fullyHashed) fully hashed · \(statistics.verified) verified identical byte by byte.")
        if statistics.hardLinks > 0 {
            text += " " + (statistics.hardLinks == 1
                ? String(localized: "1 hard link was counted once.")
                : String(localized: "\(statistics.hardLinks) hard links were counted once."))
        }
        let notDownloaded = statistics.excluded[.notDownloaded] ?? 0
        if notDownloaded > 0 {
            text += " " + (notDownloaded == 1
                ? String(localized: "1 file in iCloud that isn't downloaded was skipped, so nothing was downloaded.")
                : String(localized: "\(notDownloaded) files in iCloud that aren't downloaded were skipped, so nothing was downloaded."))
        }
        let excluded = statistics.excluded.values.reduce(0, +) - notDownloaded
        if excluded > 0 {
            text += " " + (excluded == 1
                ? String(localized: "1 file was left out because it couldn't be read or changed during the search.")
                : String(localized: "\(excluded) files were left out because they couldn't be read or changed during the search."))
        }
        return text
    }

    @MainActor
    static func reveal(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
    }

    /// "duplicates.mark.<folder>/<name>": unique within a group even when names repeat.
    /// Unique per file: the path relative to the home folder (copies in backups with the
    /// same folder structure differ by their full path).
    static func markIdentifier(_ file: DuplicateFile, home: String) -> String {
        "duplicates.mark.\(PathPresentation.relative(file.path, to: home))"
    }

    @MainActor private static let thumbnails = NSCache<NSString, NSImage>()

    /// A Quick Look thumbnail, cached. Quick Look reads the file in its own process.
    @MainActor
    static func thumbnail(for path: String) async -> NSImage? {
        if let cached = thumbnails.object(forKey: path as NSString) { return cached }
        let box = await thumbnailImage(for: path)
        guard !Task.isCancelled, let image = box.image.map({ NSImage(cgImage: $0, size: .zero) }) else { return nil }
        thumbnails.setObject(image, forKey: path as NSString)
        return image
    }

    /// Quick Look calls back on its own queue, so the callback must not be main-actor
    /// isolated (Swift 6 checks this at run time).
    static func thumbnailImage(for path: String) async -> ImageBox {
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path), size: CGSize(width: 72, height: 72), scale: 2, representationTypes: .thumbnail
        )
        let box = RequestBox(request)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ImageBox, Never>) in
                QLThumbnailGenerator.shared.generateBestRepresentation(for: box.request) { @Sendable representation, _ in
                    continuation.resume(returning: ImageBox(representation?.cgImage))
                }
            }
        } onCancel: {
            // Quick Look then calls back with no image, which ends the wait.
            QLThumbnailGenerator.shared.cancel(box.request)
        }
    }
}

/// Carries a thumbnail out of Quick Look's callback.
/// Lets the cancellation handler reach the request.
final class RequestBox: @unchecked Sendable {
    let request: QLThumbnailGenerator.Request
    init(_ request: QLThumbnailGenerator.Request) { self.request = request }
}

final class ImageBox: @unchecked Sendable {
    let image: CGImage?
    init(_ image: CGImage?) { self.image = image }
}
