import SwiftUI

/// Menu-bar commands. Adds a "Go" menu with ⌘1 … ⌘7 for each sidebar section.
public struct MainCommands: Commands {
    private let coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some Commands {
        SidebarCommands()
        CommandMenu("Go") {
            ForEach(SidebarSection.allCases) { section in
                Button(section.title) {
                    coordinator.select(section)
                }
                .keyboardShortcut(KeyEquivalent(section.shortcutDigit), modifiers: .command)
            }
        }
    }
}
