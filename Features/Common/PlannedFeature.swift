/// Describes a feature that is not built yet, for its placeholder screen.
public struct PlannedFeature: Sendable, Equatable {
    public let title: String
    public let systemImage: String
    public let summary: String
    public let capabilities: [String]
    public let phase: Int

    public static let spaceAnalyzer = PlannedFeature(
        title: "Space Analyzer",
        systemImage: "chart.pie",
        summary: "See what is using your disk, folder by folder.",
        capabilities: [
            "Volume overview",
            "Largest files and folders",
            "Storage categories",
            "Exclusions and scan history",
        ],
        phase: 4
    )

    public static let duplicateFinder = PlannedFeature(
        title: "Duplicate Finder",
        systemImage: "doc.on.doc",
        summary: "Find files with identical content, verified byte for byte.",
        capabilities: [
            "Content-verified duplicate groups",
            "Previews and keep/remove selection",
            "Accurate potential savings",
        ],
        phase: 5
    )

    public static let cleaner = PlannedFeature(
        title: "Cleaner",
        systemImage: "trash",
        summary: "Review and remove unneeded files. Nothing is removed without your confirmation.",
        capabilities: [
            "Preview of every affected file",
            "Moves files to the Trash",
            "Cleanup history",
        ],
        phase: 6
    )

    public static let all: [PlannedFeature] = [spaceAnalyzer, duplicateFinder, cleaner]
}
