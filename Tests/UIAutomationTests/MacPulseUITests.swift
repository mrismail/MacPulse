import XCTest

/// End-to-end checks of navigation and the Battery screen, using fake services.
///
/// Run from Xcode (⌘U) or:
///   xcodebuild test -project MacPulse.xcodeproj -scheme MacPulse -destination 'platform=macOS'
/// The first run may ask to allow the test runner to control the computer
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
    func testSidebarListsEverySection() {
        let app = launchApp()
        for id in Self.sectionIDs {
            XCTAssertTrue(
                element("sidebar.\(id)", in: app).waitForExistence(timeout: 5),
                "Missing sidebar item \(id)"
            )
        }
    }

    @MainActor
    func testBatteryScreenShowsLabeledValues() {
        let app = launchApp()
        element("sidebar.battery", in: app).click()

        let charge = element("battery.charge", in: app)
        XCTAssertTrue(charge.waitForExistence(timeout: 5))
        let chargeText = charge.label + " " + String(describing: charge.value ?? "")
        XCTAssertTrue(chargeText.contains("72%"), "Unexpected charge text: \(chargeText)")
        XCTAssertTrue(chargeText.contains("Measured"), "Charge must carry its provenance: \(chargeText)")

        XCTAssertTrue(element("battery.state", in: app).exists)
        XCTAssertTrue(element("battery.health", in: app).exists)
        XCTAssertTrue(element("battery.historyChart", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testGoMenuShortcutsNavigate() {
        let app = launchApp()
        XCTAssertTrue(element("sidebar.overview", in: app).waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(element("battery.state", in: app).waitForExistence(timeout: 5))
    }
}
