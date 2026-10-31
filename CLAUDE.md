# MacPulse — notes for Claude

- Work phase by phase (see Documentation/ and the project plan). Stop for approval
  before starting each phase and before moving to the next.
- Keep the app buildable after every phase. CI (`.github/workflows/ci.yml`) is the source
  of truth for macOS builds; Claude's shells are Linux and cannot compile SwiftUI/AppKit.
- Branch per phase: `phase/<n>-<name>`. One PR per feature or per phase into `main`.
- Make small, focused commits as you work: one logical change each (model, service,
  view, tests, docs). Every commit must build and keep tests passing on its own.
- Merge PRs with a merge commit (not squash) so the small commits stay on `main`.
- Never merge a PR before CI is green. `main` is protected.
- Never claim something is verified unless a test or recorded evidence proves it.
- Record any scope moved to a later phase in `Documentation/DEFERRED.md`.
- Swift 6, strict concurrency, zero warnings (`swift build -Xswiftc -warnings-as-errors`).
- Features must not import MacPulseInfrastructure; inject Domain protocols via AppDependencies.
- Every displayed number is a `Metric<T>` with provenance. Never show CPU % as battery use.
- No App Sandbox (ADR-010): Hardened Runtime, zero entitlements, Developer ID + notarization.
  Never add entitlements, network code, admin prompts or private APIs without an ADR.
- Never delete files without explicit user confirmation; prefer the Trash.
- Tests use Swift Testing (`import Testing`); UI tests use XCTest/XCUITest.
- Log `AppError` with `Logger.log(_:context:)`; never log paths or file names as public.
- Fake services and preview data are `#if DEBUG` only.
