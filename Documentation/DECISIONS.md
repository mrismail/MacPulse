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

## ADR-004 — Battery history in JSON-lines day files

**Date:** 2026-10-31 · **Status:** Accepted

**Context.** Phase 2 needs local, private storage for battery samples (about one per
minute while MacPulse runs, 30-day retention, ≈ 43,000 samples). Options considered:
SwiftData, SQLite (C API) and plain files.

**Decision.** Store one JSON object per line in one file per UTC day
(`Application Support/MacPulse/History/Battery/battery-YYYY-MM-DD.jsonl`), behind the
`BatteryHistoryRepository` protocol, implemented by the `JSONLinesBatteryHistoryStore` actor.

**Why.** Appending is a single small write (cheap on battery). Retention is deleting
whole day files. Range reads touch at most 7–8 files. No schema migrations, no
dependency, easy to inspect and to delete, and trivially testable with a temp
directory. SwiftData's model contexts add concurrency friction under Swift 6 strict
checking for no benefit at this size.

**Consequences.** Files are created 0600 / directory 0700 inside the sandbox container.
Corrupt lines are skipped, not fatal. If later phases need richer queries (process
history in Phase 3), revisit with SQLite behind the same protocol style.

## ADR-005 — Battery data sources and labeling

**Date:** 2026-10-31 · **Status:** Accepted

| Value | Source | Label |
|---|---|---|
| Charge, power source, charging state, battery condition | `IOPSCopyPowerSourcesInfo` (documented `IOPSKeys.h`) | Measured |
| macOS time to empty / full | IOPS `Time to Empty` / `Time to Full Charge` | Estimate ("macOS's own estimate") |
| Adapter watts | `IOPSCopyExternalPowerAdapterDetails` | Measured |
| Cycle count, design and full-charge capacity, temperature, voltage | `AppleSmartBattery` IORegistry entry (best-effort, not formally documented) | Measured when present and plausible, otherwise Unavailable |
| Health % | full-charge ÷ design capacity | Estimate, with both numbers in the explanation |
| Charging power | voltage × current | Estimate |
| Runtime from recent discharge | MacPulse least-squares fit over ≤ 30 min of on-battery history | Estimate, with the window in the explanation |

The registry is never the only source for the main values (charge, state). Every
registry value is range-checked; out-of-range values show as Unavailable with the
raw figure in the tooltip. On Apple silicon `MaxCapacity` is a percentage, so the
full-charge capacity comes from `AppleRawMaxCapacity` / `NominalChargeCapacity`.

**Sandbox:** IOPS and IORegistry property reads need no entitlement. Confirmed by the
integration tests on the developer's MacBook (Phase 2 acceptance).
