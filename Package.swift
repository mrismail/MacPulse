// swift-tools-version: 6.0
// MacPulse — modular Swift package. The macOS app target itself is defined in
// project.yml (XcodeGen) and links the `MacPulseAppCore` product from this package.

import PackageDescription

let package = Package(
    name: "MacPulse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacPulseAppCore", targets: ["MacPulseAppCore"]),
        .library(name: "MacPulseFeatures", targets: ["MacPulseFeatures"]),
        .library(name: "MacPulseInfrastructure", targets: ["MacPulseInfrastructure"]),
        .library(name: "MacPulseShared", targets: ["MacPulseShared"]),
        .library(name: "MacPulseDomain", targets: ["MacPulseDomain"]),
    ],
    targets: [
        // Pure domain: models, repository protocols, use cases, policies.
        // Foundation only — no SwiftUI, AppKit or IOKit.
        .target(
            name: "MacPulseDomain",
            path: "Domain"
        ),

        // Shared design system (SwiftUI), formatting utilities and logging.
        .target(
            name: "MacPulseShared",
            dependencies: ["MacPulseDomain"],
            path: "Shared"
        ),

        // Operating-system integration behind Domain protocols.
        .target(
            name: "MacPulseInfrastructure",
            dependencies: ["MacPulseDomain", "MacPulseShared"],
            path: "Infrastructure",
            linkerSettings: [.linkedFramework("IOKit")]
        ),

        // Screens and view models (MVVM). Depends on Domain protocols, never on Infrastructure.
        .target(
            name: "MacPulseFeatures",
            dependencies: ["MacPulseDomain", "MacPulseShared"],
            path: "Features"
        ),

        // Composition root: navigation, dependency container, root view.
        .target(
            name: "MacPulseAppCore",
            dependencies: ["MacPulseDomain", "MacPulseShared", "MacPulseInfrastructure", "MacPulseFeatures"],
            path: "App/Core"
        ),

        // MARK: Tests
        .testTarget(
            name: "MacPulseDomainTests",
            dependencies: ["MacPulseDomain"],
            path: "Tests/UnitTests/DomainTests"
        ),
        .testTarget(
            name: "MacPulseSharedTests",
            dependencies: ["MacPulseShared", "MacPulseDomain"],
            path: "Tests/UnitTests/SharedTests"
        ),
        .testTarget(
            name: "MacPulseFeaturesTests",
            dependencies: ["MacPulseFeatures", "MacPulseDomain"],
            path: "Tests/UnitTests/FeaturesTests"
        ),
        .testTarget(
            name: "MacPulseAppCoreTests",
            dependencies: ["MacPulseAppCore", "MacPulseDomain", "MacPulseInfrastructure"],
            path: "Tests/UnitTests/AppCoreTests"
        ),
        .testTarget(
            name: "MacPulseInfrastructureTests",
            dependencies: ["MacPulseInfrastructure", "MacPulseDomain"],
            path: "Tests/IntegrationTests/InfrastructureTests"
        ),
    ]
)
