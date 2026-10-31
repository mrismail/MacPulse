import XCTest

/// End-to-end checks of navigation, the Battery screen, the Overview and Settings,
/// using fake services so results don't depend on the test machine's battery.
///
/// Run from Xcode (⌘U) or:
///   xcodebuild test -project MacPulse.xcodeproj -scheme MacPulse -destination 'platform=macOS'
/// The first local run may ask to allow the test runner to control the computer
/// (System Settings → Privacy & Security → Accessibility).
final class MacPulseUITests: XCTestCase {
    private static let sectionIDs = [
        "overview", "battery", "energy", "spaceAnalyzer", "duplicateFinder", "cleaner", "settings",
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MacPulseUseFakeServices"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func open(_ section: String, in app: XCUIApplication) {
        let item = element("sidebar.\(section)", in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 10), "Missing sidebar item \(section)")
        item.click()
    }

    @MainActor
    func testSidebarListsEverySection() {
        let app = launchApp()
        for id in Self.sectionIDs {
            XCTAssertTrue(
                element("sidebar.\(id)", in: app).waitForExistence(timeout: 10),
                "Missing sidebar item \(id)"
            )
        }
    }

    @MainActor
    func testBatteryScreenShowsLabeledValues() {
        let app = launchApp()
        open("battery", in: app)

        let charge = element("battery.charge", in: app)
        XCTAssertTrue(charge.waitForExistence(timeout: 10))
        // Static text exposes its string as label or value depending on the macOS version.
        let label = [charge.label, charge.value as? String ?? ""].joined(separator: " ")
        XCTAssertTrue(label.contains("Charge"), "Unexpected charge text: \(label)")
        XCTAssertTrue(label.contains("72"), "Charge value missing: \(label)")
        XCTAssertTrue(label.contains("Measured"), "Charge must carry its provenance: \(label)")

        XCTAssertTrue(element("battery.state", in: app).exists)
        XCTAssertTrue(element("battery.health", in: app).exists)
        XCTAssertTrue(element("battery.historyChart", in: app).waitForExistence(timeout: 10))
    }

    @MainActor
    func testRangeSwitchingKeepsTheChart() {
        let app = launchApp()
        open("battery", in: app)
        let range = element("battery.range", in: app)
        XCTAssertTrue(range.waitForExistence(timeout: 10))
        for title in ["6 Hours", "7 Days", "24 Hours"] {
            range.radioButtons[title].firstMatch.click()
            XCTAssertTrue(element("battery.historyChart", in: app).waitForExistence(timeout: 10), title)
        }
    }

    @MainActor
    func testGoMenuShortcutsNavigate() {
        let app = launchApp()
        XCTAssertTrue(element("sidebar.overview", in: app).waitForExistence(timeout: 10))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(element("battery.state", in: app).waitForExistence(timeout: 10))
    }

    @MainActor
    func testOverviewLinksToBattery() {
        let app = launchApp()
        XCTAssertTrue(element("overview.recommendations", in: app).waitForExistence(timeout: 10))
        let link = element("overview.openBattery", in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()
        XCTAssertTrue(element("battery.state", in: app).waitForExistence(timeout: 10))
    }

    @MainActor
    func testClearHistoryAsksForConfirmation() {
        let app = launchApp()
        open("settings", in: app)
        let clear = element("settings.clearBatteryHistory", in: app)
        XCTAssertTrue(clear.waitForExistence(timeout: 10))
        clear.click()
        // Query the confirmation sheet: `app.buttons` also matches the Touch Bar copy.
        let confirm = app.sheets.buttons["Clear History"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Clearing must ask for confirmation first")
        confirm.click()
        XCTAssertTrue(app.staticTexts["History cleared"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBatteryScreenPassesAccessibilityAudit() throws {
        let app = launchApp()
        open("battery", in: app)
        XCTAssertTrue(element("battery.charge", in: app).waitForExistence(timeout: 10))
        // Inactive windows render secondary text dimmer; audit the window as the user sees it.
        app.activate()
        app.windows.firstMatch.click()
        var problems: [String] = []
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .sufficientElementDescription]) { issue in
            let element = issue.element
            let name = [element?.identifier, element?.label]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " / ")
            // Swift Charts generates its own axis-label elements; they have no identifier or label.
            if name.isEmpty && issue.auditType == .sufficientElementDescription {
                return true
            }
            // Sidebar rows are drawn by the system sidebar style (vibrancy over the desktop),
            // not by MacPulse colors; their contrast depends on the wallpaper behind the window.
            if issue.auditType == .contrast, element?.identifier.hasPrefix("sidebar.") == true {
                return true
            }
            problems.append("\(issue.compactDescription) — \(name.isEmpty ? "unnamed element" : name)")
            return true  // collect everything, then report below with element names
        }
        XCTAssertTrue(problems.isEmpty, "Accessibility audit: " + problems.joined(separator: " | "))
    }
}
