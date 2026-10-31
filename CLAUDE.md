# MacPulse — notes for Claude

- Work phase by phase (see Documentation/ and the project plan). Stop for approval
  before starting each phase and before moving to the next.
- Keep the app buildable after every phase. CI (`.github/workflows/ci.yml`) is the source
  of truth for macOS builds; Claude's shells are Linux and cannot compile SwiftUI/AppKit.
- Branch per phase: `phase/<n>-<name>`. One PR per feature or per phase into `main`.
- Make small, focused commits: one logical change each (model, service, view, tests, docs),
  never one large commit for a whole phase.
- Swift 6, strict concurrency, zero warnings (`swift build -Xswiftc -warnings-as-errors`).
- Features must not import MacPulseInfrastructure; inject Domain protocols via AppDependencies.
- Every displayed number is a `Metric<T>` with provenance. Never show CPU % as battery use.
- App Sandbox is on (ADR-002). Add entitlements only when a phase needs them, and record why.
- Never delete files without explicit user confirmation; prefer the Trash.
- Tests use Swift Testing (`import Testing`).
