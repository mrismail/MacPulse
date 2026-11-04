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

## ADR-013 — Space Analyzer scanner: safety rules and budget (Phase 4)

**Date:** 2026-11-02 · **Status:** Accepted

**Context.** Spec Phase 4 acceptance: "scanning works on large directory trees without
blocking the UI or following unsafe filesystem paths". Without the sandbox (ADR-010)
MacPulse can read anything the user can, so the scanner itself must be safe. macOS 14+
shows privacy prompts for Desktop, Documents, Downloads, iCloud Drive, removable and
network volumes and other apps' data; some locations need Full Disk Access.

**Decision.**
- `FileSystemScanner` lists folders with `FileManager.contentsOfDirectory` and reads
  metadata (`URLResourceValues`, `lstat`) only; it never opens a file.
- Symbolic links are never followed. Each folder is entered once, keyed by device +
  inode, which also defeats firmlinks and hard-linked folders. The scan stays on the
  starting volume (for `/`, the System and Data volumes count as one).
- `ScanPathPolicy` runs before each folder: user exclusions; system locations
  (`/System`, `/dev`, `/private/var/vm`, `/private/var/db`, `/Volumes`, Spotlight,
  FSEvents, Time Machine, …); and privacy-protected locations, which are skipped unless
  the user picked that location (or something inside it) in the folder panel. Picking
  `/` or the home folder does not approve Documents. No Full Disk Access is requested.
- Hard-linked files are counted once; packages are sized as one item; unreadable
  folders are recorded as "no permission" and never retried or escalated.
- Memory is bounded: every folder is kept, but only the 50 largest files per folder
  (the rest summed) and the 1,000 largest overall.
- The walk runs in a detached utility-priority task; cancelling returns a partial
  result. Progress is throttled to 10 updates per second.
- Sizes are labelled: size on disk (`totalFileAllocatedSize`, measured), file size
  (`totalFileSize`, measured), volume figures (filesystem-reported, measured) and
  "recoverable" (caches, logs, temporary files, Trash — an estimate).
- CI guardrail: file-changing APIs (`removeItem`, `trashItem`, `moveItem`,
  `replaceItem`, `unlink`, `rmdir`) are allowed only in MacPulse's own data stores
  (`Infrastructure/Persistence`) and the scan benchmark's temporary tree, until the
  Phase 6 Cleaner ADR.

**Evidence.** Integration tests build real trees with a symlink loop, a link out of the
tree, hard links, a package, exclusions, a protected folder, a locked folder, and a
cancelled scan. `MACPULSE_DIAGNOSTICS=1 MacPulse --macpulse-scan-benchmark` builds a
sparse synthetic tree (`MACPULSE_SCAN_FILES`, default 200,000), scans it, measures scan
time, CPU, peak footprint and the longest main-thread stall (10 ms heartbeat), then
removes the tree. CI budget for 200,000 files: complete result, main-thread stall
≤ 250 ms, peak footprint ≤ 150 MB, scan ≤ 120 s.

**First results (CI, macOS 15.8 arm64 VM, 200,000 files in 2,200 folders):** complete;
14.2 s (≈14,100 files/s), 12.1 s CPU; longest main-thread stall 43 ms; peak footprint
**75 MB**. The first run peaked at 318 MB because autoreleased URLs and resource values
from every listing lived until the scan ended; each folder listing now drains its own
autorelease pool.

**Open.** Owner's Mac: 1,000,000-file run (`MACPULSE_SCAN_FILES=1000000`), and a home
scan to confirm no unexpected privacy prompt.

## ADR-014 — Duplicate Finder: content-only comparison, verified groups (Phase 5)

**Date:** 2026-11-03 · **Status:** Accepted

**Context.** Spec Phase 5 acceptance: "files with identical names but different content are
never classified as identical". The spec also asks for staged hashing, verification before
presenting groups, no symlink following, no hard links counted as savings, and never
deleting automatically.

**Decision.**
- Candidates come from the same safe walk as the Space Analyzer (ADR-013): regular files
  only, no links, folders once by device + inode, same volume, `ScanPathPolicy`
  (protected folders only when the user picked them). Package contents (apps, libraries)
  are never offered. Empty files are ignored.
- Stages: same logical size → hard links merged (same device + inode is one stored file,
  never a copy) → SHA-256 of the first and last 64 KB (whole file when ≤ 128 KB) →
  streaming SHA-256 of the whole file → byte-by-byte comparison with the group's first
  copy. Only byte-verified groups are shown. Names and dates are never compared.
- Files are opened read-only with `O_NOFOLLOW`, and only if device, inode, size and
  modification time still match what was listed; a file that changes is left out and
  counted.
- Savings keep one copy: size on disk of every other copy. When APFS reports
  `EF_MAY_SHARE_BLOCKS` (clones) for a copy, the group's savings are an estimate.
  A copy with other hard links frees nothing on its own and counts as zero when marked.
- Phase 5 is review only: users mark copies (at least one per group is always kept),
  see the savings and reveal them in Finder. Moving marked copies to the Trash will use
  the Cleaner's confirmation and re-validation flow (Phase 6).

**Evidence.** Integration tests on real files: same name with different content; same
size with different content; same first and last 64 KB with one different byte in the
middle; identical files in different folders; hard links with and without a real copy;
symbolic links; empty and unreadable files; package contents; type and size filters;
overlapping folders; a group of 50; stopping. CI benchmark
(`--macpulse-duplicate-benchmark`): 12,504 files (1.0 GB) — 10,000 unique files, 500
groups of 4, one group of 4 × 64 MB, 200 look-alike pairs differing in one middle byte,
one group of 100.

**First results (CI, macOS 15.8 arm64 VM):** 502 of 502 groups, 0 look-alike pairs grouped,
largest group 100; 6.3 s, 1.9 GB read; longest main-thread stall 41 ms; peak footprint
**41 MB** (415 MB before reads were drained per file). Budget: correct result, stall
≤ 250 ms, peak ≤ 100 MB, search ≤ 180 s.

## ADR-015 — Cleaner: Trash only, explicit confirmation, re-validation (Phase 6)

**Date:** 2026-11-03 · **Status:** Accepted

**Context.** Spec Phase 6 acceptance: "no file is deleted without explicit user
confirmation". Every cleanup must show a preview, the reason, the estimated space,
ask for confirmation and report what actually happened. Use the Trash where possible,
validate identity and location immediately before acting, protect app data and system
files, and never report false success. Without the sandbox (ADR-010) MacPulse could
reach anything the user can, so the limits are in code and enforced by CI.

**Decision.**
- **One removal path.** `FileManagerTrashService` is the only code that moves user items,
  using `FileManager.trashItem`. There is no permanent deletion anywhere in the app; the
  Trash category is information only and opens the Trash in Finder. CI fails if
  `trashItem` appears anywhere else, and keeps `removeItem`/`moveItem`/`unlink`/`rmdir`
  to MacPulse's own data stores and benchmarks.
- **Two steps in the view model.** `requestCleanup()` only shows the confirmation dialog
  (count and size); `confirmCleanup()` runs only while that dialog's items are pending and
  moves exactly those items. Nothing is pre-selected except copies the user already marked
  in the Duplicate Finder. Nothing runs at launch or on a timer.
- **Safety policy** (`CleanupSafetyPolicy`), applied when listing and again before each
  item: inside the home folder or a picked folder only; never the home folder, a picked
  folder itself or a standard folder (Desktop, Documents, Downloads, Library, Pictures,
  Movies, Music, Applications, Public, Sites, .Trash); in `~/Library` only items inside
  Caches and Logs, and not Apple's own (`com.apple.*`, CloudKit, FamilyCircle); never
  package contents or media libraries; never MacPulse's own data. Paths are normalized
  first, so `..` can't escape.
- **Re-validation per item, immediately before moving:** still exists; not a link or
  special file (`lstat`); same device + inode; for files, same size and modification time.
  Folders are matched by device + inode only, because apps keep writing into caches.
  Otherwise the item is skipped and reported.
- **Truthful results.** Each item is moved (with its Trash location), skipped (missing,
  changed, not allowed) or failed (macOS's message). Space is reported as "moved to the
  Trash", freed when the Trash is emptied.
- **History.** Reports (original and Trash paths) are kept 30 days in owner-only files,
  never logged, so items can be found and put back.
- **Categories.** App caches and logs (per app folder); old downloads in a Downloads
  folder the user picks (30/90/365 days); large files (≥ 500 MB) from the last Space
  Analyzer scan; empty folders in a picked folder; copies marked in the Duplicate Finder
  (one copy per group is always kept); the Trash (read-only). Running apps' caches are
  flagged.

**Evidence.** Integration tests move real files to the real Trash and restore them:
- the item lands in the Trash and the reported path exists;
- grown, replaced, swapped-for-a-link and missing items are skipped;
- a standard folder and `~/Library/Preferences` are refused;
- a read-only parent produces a reported failure while its sibling moves;
- stopping before the start moves nothing;
- candidate sources list caches without Apple's, old downloads by age, empty folders
  (skipping links), and duplicates with the kept copy named.

View-model tests prove that nothing is moved without confirmation, that cancelling moves
nothing, and that exactly the confirmed items are passed. A UI test cancels the dialog
(nothing happens), then confirms and sees the result and history.

**Not done.** Permanent deletion and emptying the Trash (not offered; Finder does it).

## ADR-016 — Menu bar companion, open at login, preferences, one safety policy (Phase 7)

**Date:** 2026-11-03 · **Status:** Accepted

**Context.** Spec Phase 7: unified dashboard, shared scan and cleanup workflows, menu bar
companion, notifications, Settings, performance. Acceptance: all modules operate
consistently and share the same safety policies. History is recorded only while MacPulse
runs (DEFERRED), so monitoring "in the background" needs the app to keep running.

**Decision.**
- **Menu bar companion** = a `MenuBarExtra` scene in the main app (no helper, no daemon,
  no admin rights, no new entitlements). It shows charge (with its provenance), state,
  the runtime estimate, the most active apps, free space and links into the app. On by
  default; Settings can hide it.
- **Background monitoring** stays in the main process. While the menu bar companion is
  shown, closing the window keeps MacPulse running (`applicationShouldTerminateAfterLastWindowClosed`),
  so battery and activity keep being recorded.
- **Open at login** uses `SMAppService.mainApp` (public API). Off by default; turned on in
  Settings; macOS lists it under System Settings → General → Login Items. Approval needed
  by macOS is reported in Settings.
- **Preferences** (`AppPreferences`, user defaults): battery sampling 30 s / 1 min / 5 min,
  background app activity 1 / 5 min, battery retention 7/30/90 days, usage retention
  7/14/30 days, menu bar on/off, default old-downloads age. Intervals and retention are
  read at launch; Settings says when a restart is needed. Unknown values fall back to
  defaults.
- **One safety policy for every module.** The user's excluded folders now also apply to the
  Cleaner (`CleanupSafetyPolicy.excludedFolders`): items inside are never offered or
  moved. Space Analyzer, Duplicate Finder and Cleaner all use `ScanPathPolicy` rules
  (ADR-013) for walking and the Cleaner adds `CleanupSafetyPolicy` (ADR-015) for acting.
- **Put Back.** Cleanup history can move an item back from a Trash folder, only when its
  original place is empty, its folder still exists and the safety policy allows it. Done by
  the Trash service, the only code that moves user items (CI guardrail updated to allow
  exactly this `moveItem`).
- **Settings** covers the spec's list: startup, monitoring frequency, notifications (the
  same drain-alert controls as the Energy screen), scan locations and exclusions, cleanup
  preferences, data retention, privacy and clearing every history (battery, app usage,
  scans, cleanups), version and diagnostics.

**Evidence.** Unit tests: preferences decoding and validation, restart notice, login item
success and failure, clearing scan and cleanup history, Cleaner exclusions, Put Back
recorded in history, menu bar label never inventing a charge. Integration tests: Put Back
restores into a free place only, refuses an occupied place, a second Put Back, and paths
outside a Trash folder; preferences round-trip and fall back on corrupt data. UI test:
Settings shows startup, menu bar and monitoring controls and the history buttons.

**Not done.** The menu bar extra itself isn't driven by UI tests (XCUITest can't open
status items reliably); it reuses the tested Overview view model.

## ADR-017 — Hardening after the review of `main` (before Phase 8)

**Date:** 2026-11-04 · **Status:** Accepted

**Context.** Three reviewers (team lead, front end, platform/security/QA) reviewed `main`
after Phase 7 (`claude/MacPulse-Main-Review.md`). The safety findings showed ways the Cleaner
could move the wrong item, and the Duplicate Finder could download iCloud files.

**Decision.**
- **Duplicates (amends ADR-014/015):**
  - Each copy carries the identity it had when its bytes were compared.
  - The Cleaner offers and moves a copy only while that copy and the kept copy are both
    unchanged (`CleanupRequirement.keptCopyUnchanged`).
- **iCloud placeholders:** files with `SF_DATALESS` are never opened; they are counted as
  "not downloaded" (amends ADR-014). ADR-018 adds a read policy for files evicted after
  listing.
- **Empty folders:** listed again immediately before moving
  (`CleanupRequirement.stillEmpty`).
- **After `trashItem`:** the item in the Trash must have the checked device and inode;
  otherwise it is moved back and reported as changed.
- **Put Back:**
  - restores only the recorded identity;
  - only from this user's Trash or a drive's `.Trashes`;
  - uses the folders picked at the time (stored in the report).
- **History during a cleanup:** written before the first item and after each one, so a
  cleanup interrupted by quitting can still be put back.
- **Picked folders:** never `/`, system locations, the home folder, Library, a standard
  folder (Downloads excepted), a hidden folder or a drive root. A pick unlocks only its
  own category.
- **Policy refusals:**
  - Hidden items and macOS crash reports are refused.
  - Policies compare case-insensitively and map `/System/Volumes/Data/...` to `/...`.
- **One task at a time:**
  - One scan and one duplicate search at a time; an older run never overwrites a newer
    one.
  - Cleaner reviews and cleanups use separate tasks.
  - Categories are locked while cleaning.
- **CI guardrails:**
  - Cover `unlink`/`unlinkat`/`removefile`/`rename*`/`truncate`/`copyfile`/`clonefile`,
    bare `remove(`/`rename(`, dynamic selectors, and running other programs (source and
    binary).
  - The single allowed `trashItem` and `moveItem` calls are matched exactly.
  - Persistence is limited to its two store files.
- **Overhead budget (amends ADR-012):**
  - 0.04 ms of CPU per process read, plus a ceiling of 0.1 % of one core at the background
    rate.
  - This replaces the flat 15 ms per sample: CI ≈ 0.007 ms per process, the owner's Intel
    Mac 0.025 ms.
- **Diagnostics:** the run loop now turns in 5 ms slices, so the measured main-thread stall
  is the app's.
- **Contrast:** card text uses `Palette.secondaryText` (72 % primary). This did **not** clear
  the Battery-screen audit findings, which stay non-blocking until they are inspected on a
  real Mac (DEFERRED).

**Evidence.** New tests cover:
- a kept copy that was edited or deleted after the comparison (the last copy is never
  moved);
- a copy edited after the comparison (no longer offered);
- an empty folder that gained a file (skipped);
- Put Back refusing a different item;
- a file rewritten just before it is read (left out of duplicates);
- the dataless flag;
- unsafe picks unlocking nothing, and case or Data-volume paths;
- history saved while a cleanup runs, with categories locked;
- a second scan refused while one runs;
- Space Analyzer results dropping trashed items.

CI on the hardening branch: overhead 1.9 ms for 266 processes; scan of 200k files in
13.2 s, 76 MB peak, 26 ms longest stall; duplicates 502/502 groups found, 0 look-alikes
grouped, 5.2 s, 42 MB peak, 34 ms longest stall.

## ADR-018: Second review hardening (picks, Trash access, history, reads)

**Status:** Accepted (second review of `main`, after PR #14)

**Context.** The second round of reviews (team lead, front end, platform/security)
found a path hole through `/Volumes/<startup disk>`, unverified behaviour without Full
Disk Access, history writes that grew with the square of the number of items, a hidden
failed move-back, old-download folders not re-checked, and gaps in the CI guardrails.

**Decision.**
- **Picks:** a picked folder is judged by its `realpath`; a `/Volumes/…` path on the
  startup disk's devices is refused; hidden folders on drives are refused. Empty Folders
  may start in a standard folder (the folder itself stays protected).
- **External drives:** the folder scanned by the Space Analyzer or searched for
  duplicates counts as picked for those categories, if it could be picked.
- **Trash without access:** if `lstat` inside the Trash is refused, a successful
  `trashItem` counts as moved with the identity checked before the move, and nothing is
  moved back. Put Back then says to use Finder. Put Back refuses history without an
  identity and other users' `.Trashes` folders.
- **Failed move-back:** reported as failed, naming the item in the Trash.
- **Old downloads:** folders get `CleanupRequirement.unchangedSince(cutoff)` and are
  checked again just before moving; a folder too large to check (20,000 items) or with
  unreadable items is never old.
- **History:** item results go through one ordered stream; saves are batched (50 items or
  one second) and chained so an older version never overwrites a newer one. `replace`
  throws `reportNotFound`; `append` doesn't throw after writing. Day files are fsynced
  before replacing the old file. Report times are whole milliseconds so ids survive JSON.
- **iCloud placeholders:** hashing and byte comparison run with the thread's
  `IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES` policy off, so a file evicted after listing
  fails to read instead of downloading (public API in `<sys/resource.h>`).
- **Guardrails:** dynamic lookup (`NSClassFromString`, `dlsym`, `Selector(())`),
  `NSWorkspace` open calls, module-qualified `remove`/`rename` and file-writing APIs are
  forbidden outside MacPulse's own stores and benchmarks; the binary check adds `remove`,
  `truncate`, `dlopen`, `dlsym`, `NSClassFromString` and `sel_registerName`. "Open Trash in
  Finder" uses `selectFile`, which never launches anything.
- **CI:** the overhead budget is 0.03 ms per process (about 2× CI); runs are no longer
  cancelled by the next push.

**Consequences.** No new entitlements, network code or private APIs. Behaviour without
Full Disk Access still needs checking on a signed build (DEFERRED).

## ADR-019: Release packaging, updates and localization

**Status:** Accepted (Phase 8)

**Context.** MacPulse is distributed directly, without the Mac App Store or a sandbox
(ADR-002, ADR-010). The owner hasn't enrolled in the Apple Developer Program yet. Updates
and the Arabic translation needed decisions.

**Decision.**
- **Packaging:**
  - A DMG (the app plus an Applications link) on GitHub Releases.
  - `scripts/release/` archives, signs, notarizes and staples, and the Release workflow runs them on version tags.
  - Without the Developer ID secrets, the same pipeline produces an ad-hoc-signed DMG, documented as a known limitation. No code changes are needed after enrolment.
- **Version:** `MARKETING_VERSION` in `project.yml` (1.0.0). The build number is the git commit count, so it always increases. A tag must match the version.
- **Updates:** manual download from GitHub Releases. No auto-updater, because it would add network code and a third-party dependency. Sparkle can be revisited after 1.0 with its own ADR.
- **Privacy manifest:**
  - `PrivacyInfo.xcprivacy` declares no tracking and no collected data.
  - It lists the required-reason APIs: file timestamps (DDA9.1, 3B52.1), disk space (85F4.1), boot time for elapsed-time measurement (35F9.1) and UserDefaults (CA92.1).
- **Localization:**
  - One `Localizable.xcstrings` in the app, generated from the compiler's extracted strings (`SWIFT_EMIT_LOC_STRINGS` with `xcstringstool sync`), never hand-edited for English.
  - The package modules look strings up in the main bundle, so one table serves them all.
  - The Strings workflow keeps the catalog in sync.
  - Arabic is a machine-assisted draft, every string marked "Needs Review", and is checked by a right-to-left UI test.
- **App icon:** an original design (a gauge with a pulse line), drawn by `scripts/design/make_icon.py` so it can be regenerated.
- **Window at launch:** in a right-to-left layout macOS 15 didn't open MacPulse's `Window` scene at launch (CI). The menu bar label, which is drawn at launch, opens the main window when none is visible. The `.defaultLaunchBehavior` scene modifier would do this directly but needs macOS 15.

**Consequences.**
- No new entitlements, network code or dependencies.
- Gatekeeper warns about ad-hoc builds until the owner adds the secrets.
- Signed-build behaviour (privacy prompts, the Trash without Full Disk Access, `SMAppService`) is verified with `Documentation/OWNER_CHECKLIST.md`.
