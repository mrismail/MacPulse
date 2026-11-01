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

**Date:** 2026-10-31 · **Status:** Superseded by ADR-010 (2026-11-01)

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

**Consequences.** Files are created 0600 / directory 0700 in `~/Library/Application Support/MacPulse/History` (was the sandbox container until ADR-010).
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

**Access:** IOPS and IORegistry property reads need no entitlement (the app has none,
ADR-010). Real-hardware verification is still open: compare the Battery screen on a
MacBook with System Settings → Battery and `ioreg -rc AppleSmartBattery`. The owner's
Intel MacBook Pro 16 capture (2026-10-31) is now a test fixture and exposed one bug
(stale fully-charged flag, fixed in PR #3).

**Health condition:** `BatteryHealth` values other than "Good" ("Fair", "Poor") and any
`BatteryHealthCondition` are shown as needing service, never as Normal.

**Runtime:** one "Estimated runtime" figure is shown everywhere: MacPulse's own
recent-discharge estimate when it has ≥ 15 min and ≥ 2 percentage points of
uninterrupted on-battery history, otherwise macOS's estimate; the provenance basis
says which. History stores only MacPulse's own estimate.

## ADR-006 — Sampling guarantees and history access pattern

**Date:** 2026-10-31 · **Status:** Accepted (from the Phase 2 review)

- `BatteryMonitor` serializes samples (each waits for the previous) and never publishes
  an older reading over a newer one.
- Power-source notifications inside the 5 s spacing window schedule one trailing sample,
  so a plug/unplug right after a timer sample is never lost.
- The 30-minute estimator window lives in memory; the store is read once at startup.
  The Battery screen reads history from disk only when the range changes and appends
  live samples in memory. Chart and session derivation run off the main actor.
- Pruning runs at most once a day, inside the sampling loop.
- If the on-disk store cannot be created or written, monitoring continues and
  `BatteryStatus.historyIssue` is shown to the user (banner + recommendation).

## ADR-007 — Release safety and logging privacy

**Date:** 2026-10-31 · **Status:** Accepted

- Fake services and preview data compile only in Debug (`#if DEBUG`); Release ignores
  `-MacPulseUseFakeServices`. CI builds the Release configuration.
- `AppError` is logged with `Logger.log(_:context:)`: kind and user message public,
  technical detail private (it may contain file paths and therefore the user name).
- CI fails if the Release app has any entitlement at all (ADR-010; previously only
  `app-sandbox` was allowed). New entitlements require an ADR.

## ADR-008 — Localization groundwork

**Date:** 2026-10-31 · **Status:** Accepted

The owner targets global customers including Arabic. Phase 2 sets
`defaultLocalization: "en"`, formats every number, percentage, duration, temperature
(°C/°F by locale), voltage, power and capacity with Foundation format styles, uses
`String(localized:)` / `LocalizedStringKey` for UI text, and mirrors directional glyphs
in RTL. Extracting a String Catalog and translating (Arabic first) is scheduled for
Phase 7, when the UI text is stable; see `DEFERRED.md`.

## ADR-009 — Process monitoring inside the App Sandbox (Phase 3 spike)

**Date:** 2026-10-31 · **Status:** Measured; decided in ADR-010

**Method.** `MacPulse --macpulse-process-access-probe` runs in the signed, sandboxed
Release and Debug apps in CI (macOS 15.8.2) and prints counts and errno only.

**Results (sandboxed Release, 300-process sample):**

| API | Result |
|---|---|
| `sysctl(KERN_PROC_ALL)` process list (pid, uid, name) | ✅ 519 processes |
| `proc_listallpids` | ❌ returns 0 in the sandbox |
| `host_statistics(HOST_CPU_LOAD_INFO)` system CPU | ✅ |
| `NSWorkspace.runningApplications` | ✅ 35 apps |
| `proc_pidinfo(PROC_PIDTASKINFO)` CPU time, resident memory, threads | ✅ 187/187 same-user processes; ❌ EPERM for 113 root/system |
| `proc_pidinfo(PROC_PIDTBSDINFO)` | ✅ same-user apps |
| `proc_pid_rusage` (billed energy, phys footprint, disk I/O) on other processes | ❌ EPERM for all, including same-user |
| `proc_pid_rusage` on MacPulse itself | ✅ (billed energy 0 on the CI VM) |

**Consequences.**
- Sandboxed Phase 3 is feasible: per-process CPU % (from CPU-time deltas), resident
  memory and threads for every process of the current user, plus system CPU load.
- Per-process energy (`ri_billed_energy`), memory footprint and disk I/O are only
  available without the sandbox. Without them, battery impact is a resource-based
  estimate, labeled as such (spec §6 allows this).
- Root/system daemons are not readable either way without admin rights (spec forbids
  requesting admin for this).
- Open: run the probe on a real Mac (owner's Intel MacBook, macOS 26) to confirm, and to
  see whether billed energy is non-zero on Intel at all.

## ADR-010 — No App Sandbox; Developer ID distribution

**Date:** 2026-11-01 · **Status:** Accepted (chosen by product owner after ADR-009)

**Context.** ADR-009 measured that the sandbox blocks `proc_pid_rusage` for every other
process, which removes per-app energy accounting, memory footprint and disk I/O — the
best data for "which app drains my battery". The original spec (§8) already targets
direct download with Developer ID signing and notarization.

**Decision.** Ship without the App Sandbox. Keep the Hardened Runtime. The app has **no
entitlements**; CI fails if any appear in the Release build or if the Hardened Runtime
flag is missing. Distribution: signed and notarized direct download (Phase 8). The Mac
App Store is out of scope.

**Guardrails that replace the sandbox's protection** (CI-enforced where marked):
- No network access code paths; no admin rights; no private APIs. **CI:** source scan
  for networking/process-control/privilege APIs and an `nm` check of the Release binary
  for `socket`, `connect`, `task_for_pid`, `kill`, `ptrace`.
- Process monitoring is read-only (no signals, no `task_for_pid`); root/system
  processes stay unread. **CI:** the Release probe must report process access working
  and the app unsandboxed, and must stay silent without `MACPULSE_DIAGNOSTICS=1`.
- Zero entitlements and the Hardened Runtime flag. **CI:** Release signing check.
- File access in Phases 4–6 goes only to folders the user selects or to documented
  user-level locations, and macOS privacy prompts (TCC) are respected; Full Disk Access
  is never required.
- Deletion stays user-confirmed and Trash-first (unchanged).

**Consequences.**
- History now lives in `~/Library/Application Support/MacPulse/History/` instead of the
  sandbox container. Earlier development history in the container is not migrated
  (pre-release data only).
- Signing today is ad-hoc. Developer ID signing and notarization are Phase 8 work; the
  README says "will be".
- Phase 3 can use per-app billed energy, footprint, disk I/O and wake-ups for the
  current user's processes. **Confirmed in CI (non-sandboxed Release, macOS 15.8.2):**
  `proc_pid_rusage` succeeded for 193/193 same-user processes (0 when sandboxed);
  root/system processes still EPERM. Billed energy was 0 on the CI virtual machine.

## ADR-011 — Estimating an app's battery impact

**Date:** 2026-11-01 · **Status:** Accepted

**Context.** macOS does not publish Activity Monitor's "Energy Impact" formula. The
spec forbids presenting CPU % as battery consumption.

**Decision.**
- Per-app CPU %, memory, disk and idle wake-ups are shown as measured values. CPU is per
  core (100 % = one core); System CPU is all cores together; both are labelled.
- "Battery impact" (Low / Moderate / High) is **always labeled an estimate** with its basis:
  - If macOS reported billed energy for the interval (`ri_billed_energy`), impact uses the
    average power macOS attributes to the app (High ≥ 2 W, Moderate ≥ 0.4 W).
  - Otherwise it uses CPU (High ≥ 50 % of a core, Moderate ≥ 10 %), and says so.
  - One basis is used for all apps in an interval so the ranking is consistent.
- Helper processes are grouped under their outermost `.app` bundle.
- Drain alerts fire only for sustained use (every interval in the window, default 10 min
  at ≥ 50 % CPU), on battery by default; macOS notifications are opt-in and permission is
  requested only when the user enables them; 30 min cooldown per app.

**Measured on the owner's Intel MacBook Pro 16 (macOS 26.7.1, 2026-11-01):**
`ownBilledEnergyNonZero = false` — this Intel Mac reports no per-app energy, so MacPulse
uses the CPU-based basis there and says so ("Activity (CPU-based)"). Process access:
`proc_pid_rusage` worked for 261/261 same-user processes in the sample (39 root/system
refused), 192/195 running apps; 1,110 processes in total.

## ADR-012 — Monitoring overhead budget (Phase 3 acceptance evidence)

**Date:** 2026-11-01 · **Status:** Accepted

**Context.** Spec Phase 3: monitoring "does not significantly increase battery
consumption itself". Measuring inside the parallel test run counted other tests' CPU.

**Decision.** `MACPULSE_DIAGNOSTICS=1 MacPulse --macpulse-overhead-benchmark` runs 30
real samples (process read + aggregation) in the Release app alone and reports its own
CPU time and wake-ups via `proc_pid_rusage`. CI fails above **15 ms CPU per sample**.

**First result (CI, macOS 15.8 arm64 VM, 279 user processes):** 4.1 ms CPU per sample →
**0.007 % of one core** at the 60 s background rate, **0.04 %** at the 10 s rate used
only while the Energy window is active; 0.03 wake-ups per sample; 6 MB footprint.
Timers use 5–10 s tolerance so macOS can coalesce wake-ups.

**Owner's Mac (2026-11-01, Intel MacBook Pro 16, macOS 26.7.1, 734 user processes):**
18.6 ms CPU per sample → **0.031 % of one core** at 60 s, **0.19 %** at 10 s;
0.33 wake-ups per sample; 9.7 MB footprint. This is above the 15 ms CI threshold
because the Mac runs 2.6× as many user processes as the CI VM and an Intel CPU is
slower per call (≈0.025 ms per process vs ≈0.015 ms on the arm64 VM). As a share of
the CPU it remains negligible.

**Open.** A one-hour on-battery run with Activity Monitor's Energy tab; and whether to
express the CI budget per process (e.g. ≤ 0.05 ms) or as a percentage of a core rather
than an absolute 15 ms per sample.
