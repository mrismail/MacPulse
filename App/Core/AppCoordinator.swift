import MacPulseShared
import Observation

/// Owns app-level navigation state.
@MainActor
@Observable
public final class AppCoordinator {
    /// The selected sidebar destination. Optional because `List(selection:)` can
    /// clear it; `effectiveSelection` always resolves to a destination.
    public var selection: SidebarSection?

    public init(initialSelection: SidebarSection = .overview) {
        selection = initialSelection
    }

    public var effectiveSelection: SidebarSection {
        selection ?? .overview
    }

    public func select(_ section: SidebarSection) {
        guard selection != section else { return }
        selection = section
        Log.logger(.navigation).debug("Selected \(section.rawValue, privacy: .public)")
    }
}
