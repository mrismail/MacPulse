# Architecture Decision Records

## ADR-001 — Swift Package modules + XcodeGen app target

**Date:** 2026-10-31 · **Status:** Accepted

**Context.** The spec asks for a modular architecture with `Package.swift` at the root.
A distributable macOS app also needs an app bundle, Info.plist, entitlements, signing
and notarization, which SwiftPM alone does not produce.

**Decision.** Library code lives in Swift Package targets (Domain, Shared,
Infrastructure, Features, AppCore) laid out as the spec's folder tree. The app target is
described in `project.yml` and generated with XcodeGen; the `.xcodeproj` is not committed.

**Consequences.** `swift build` / `swift test` work from the command line and in CI.
Developers run `xcodegen generate` once after cloning and after editing `project.yml`.
Requires Xcode 16 or later (Swift 6 tools).

## ADR-002 — App Sandbox enabled

**Date:** 2026-10-31 · **Status:** Accepted (chosen by product owner)

**Context.** Direct distribution allows a non-sandboxed app; the App Sandbox keeps the
Mac App Store open and limits what the app can touch.

**Decision.** Ship with `com.apple.security.app-sandbox` enabled. Add entitlements only
when a phase needs them (for example `files.user-selected.read-write` and
security-scoped bookmarks in Phase 4).

**Consequences / risks to validate.**
- **Phase 3:** reading CPU time and memory of *other* processes (`proc_pid_rusage`,
  `proc_pidinfo`) may be denied in the sandbox. This will be tested on a real runner
  before the feature is built; if denied, the options will be brought back for a decision.
- **Phase 4–6:** scanning is limited to locations the user grants through an open
  panel (persisted with security-scoped bookmarks). Whole-disk analysis requires the user
  to select the volume.
- **Phase 2:** IOKit power-source reads (`IOPSCopyPowerSourcesInfo`) are expected to work
  sandboxed; the `AppleSmartBattery` registry entry will be verified.

## ADR-003 — Value provenance is mandatory

**Date:** 2026-10-31 · **Status:** Accepted

Every user-visible metric is a `Metric<T>` tagged measured / estimated / unavailable,
so the UI can never present an estimate as a measurement or invent a missing value.
