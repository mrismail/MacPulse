# Deferred scope

Items from the spec that are intentionally not delivered in the phase where they first
appear. Each has a target phase and a reason. Update this file whenever scope moves.

| Spec item | Spec section | Moved to | Reason |
|---|---|---|---|
| Battery screen "process activity table" | §3 Battery screen | Phase 3 (Energy) | Delivered in Phase 3 (Energy). |
| Configurable battery monitoring frequency | §3 Settings | Delivered (Phase 7) | 30 s / 1 min / 5 min in Settings; applies at the next launch (ADR-016). |
| Full process table on the Battery screen | §3 Battery screen | Not planned | The Battery screen shows the top 5 apps with a link to the full Energy table. |
| Alert/notification settings in the Settings screen | §3 Settings "Notifications" | Delivered (Phase 7) | The same controls appear on the Energy screen and in Settings. |
| Rewriting Phase 3 history so every commit builds | Review (team lead) | Not planned | Several early Phase 3 commits failed tests on their own (fixture crash, identifier bug, misplaced tests). History is already pushed and reviewed; it is kept as is and the rule applies going forward. |
| Configurable process monitoring frequency | §2 Module B "configurable monitoring" | Delivered (Phase 7) | Background 1 or 5 min in Settings; 10 s while the Energy screen is visible. |
| Ending an app from MacPulse | Spec non-goal | Not planned | Spec forbids automatic termination; a manual "Quit" button may be considered with the owner later. |
| Configurable data retention | §3 Settings | Delivered (Phase 7) | Battery 7/30/90 days, app usage 7/14/30 days; scans 180 and cleanups 30 days fixed. |
| Monitoring while the app is closed | §2 Module A history | Delivered (Phase 7) | The menu bar companion keeps MacPulse running when the window closes; open at login is opt-in (ADR-016). Nothing is recorded after quitting. |
| Overview "recent scans and cleanup activity" | §3 Overview | Delivered (Phase 6) | The Overview shows free space, the last scan, its recoverable estimate and the last cleanup. |
| Storage chart as a treemap or sunburst | §3 Space Analyzer screen | After 1.0 | Phase 4 ships a stacked volume bar, a category bar chart and a size bar per folder row. |
| Live updates while files change (FSEvents) | §2 Module C | After 1.0 | Results reflect the moment of the scan; rescan to refresh. |
| "Large application data" for other apps | §2 Module C | After 1.0 | Other apps' containers are behind a per-app macOS prompt. Caches and logs are Cleaner categories; Application Support is app data and is never offered for removal (ADR-015). |
| Acting on recoverable space from the Space Analyzer | §2 Module C "estimated recoverable storage" | Delivered (Phase 6) | Large files link to the Cleaner; caches and logs are Cleaner categories. |
| Emptying the Trash / permanent deletion | §2 Module E "supported permanent-delete action" | Not planned for now | MacPulse moves items to the Trash only; macOS hides the Trash from apps without Full Disk Access, and Finder empties it. Revisit with an ADR if the owner wants it. |
| Putting items back from the Trash inside MacPulse | §10 "Recovery of files from Trash" | Delivered (Phase 7) | Put Back in cleanup history, only into a free and allowed place. |
| Cleanup preferences in Settings | §3 Settings "Cleanup preferences" | Delivered (Phase 7) | Default old-downloads age and excluded folders in Settings. |
| Clearing scan history from Settings | §3 Settings | Delivered (Phase 7) | Scan and cleanup history can be cleared in Settings. |
| Removing marked duplicates (move to Trash) | §2 Module D "manual selection of files to keep or remove" | Delivered (Phase 6) | "Review Marked in Cleaner" → confirmation → Trash (ADR-015). |
| Similar (not identical) images | — | Not planned | The spec asks for identical files only. |
| String Catalog extraction and Arabic translation | (owner requirement) | Delivered (Phase 8), Arabic needs review | The catalog is generated from the compiler's strings (ADR-019). Arabic is a draft marked "Needs Review" until a native speaker checks it (owner checklist). |
| Snapshot tests (light/dark/RTL) | Review finding | After 1.0 | Needs a third-party snapshot library (zero-dependency rule). |
| macOS 14 launch verification | Phase 1 acceptance | Owner checklist (release) | CI runners are macOS 15; verified by the owner on macOS 14 before publishing (`Documentation/OWNER_CHECKLIST.md`). |
| Contrast audit findings on the Battery screen (`battery.health`, `battery.cycleCount` and 4 unnamed elements) | Accessibility (review) | Partly fixed (Phase 8) | See the Phase 8 table below. |
| Every commit building on its own (Phase 7) | CLAUDE.md | Not rewritten | "Put items back from the Trash" (commit before "Settings, menu bar companion and Put Back") added an enum case whose exhaustive switch was updated in the next commit, so that one commit doesn't compile alone. History is pushed; kept as is. |
| One shared safe walker for scanner, duplicate collector and empty folders | Review (team lead) | After 1.0 | The three walks apply the same rules (policy, device + inode, no links), each covered by its own tests; empty folders now also stop on cancellation and accept the Data volume. Merging them is a refactor without a user-visible change. |
| Package strings in a String Catalog (`bundle: .module`) | Review (front end) | Delivered differently (Phase 8) | One app catalog serves all modules, which look strings up in the main bundle (ADR-019); no per-package bundles needed. |
| UI tests for the menu bar panel, Put Back and adding exclusions | Review (front end) | Phase 8 | XCUITest can't open status items reliably; Put Back and exclusions are covered by unit and integration tests. |
| Adaptive layouts (`ViewThatFits`) for four-metric rows and large text | Review (front end) | Phase 8 | Polish pass with the release screenshots. |
| Replacing fixed sleeps in two feature tests | Review (team lead) | Phase 8 | The tests are stable on CI; they will move to explicit waits when touched. |
| Each review-fix commit building on its own (PR #14) | CLAUDE.md | Shown to fail, not rewritten | CI showed these commits on `main` fail on their own: 393bacd (Put Back test), 825e5b7, b2171ea and bc12e33 (CI script syntax), 86e3314 and ace99c7 (blocking contrast test), 34a4f82 (doesn't compile). f9d4232 (607 lines) was cancelled, so it is unverified. History is pushed; kept as is. From the second review on, CI no longer cancels a run when the next batch is pushed, so every pushed batch is checked. |
| Every commit building on its own (second review fixes) | CLAUDE.md | Shown to fail, not rewritten | Two batches were red on CI and fixed in the next commit: the dataless test used another suite's helpers, and a cleanup report saved with a sub-millisecond time didn't decode to the same time. |
| Duplicate benchmark at home-folder scale | Review (team lead) | Phase 8, on the owner's Mac | CI measures a synthetic 1,000-group tree; a real home folder needs the owner's machine. It was dropped from the Phase 6 plan without a note; recorded here now. |
| Soak test (hours of monitoring) and the one-hour battery run | Spec §10 "long sessions" | Phase 8, on the owner's Mac | Needs real hardware and time; CI runs short sessions only. |
| Quitting during a cleanup, against the real history store | Spec §10 | Phase 8 | Covered with the in-memory store and by the store's own replace round trip; a test that kills the app mid-cleanup needs a UI test harness that can relaunch. |
| Cleanup and Put Back without Full Disk Access | Review (platform) | Phase 8, signed build on the owner's Mac | When macOS hides the Trash, a successful move counts as moved (identity checked before the move) and Put Back points to Finder. Whether `lstat` in `~/.Trash` is refused, and whether moving back out works, must be checked on a signed build without Full Disk Access (CI runners have it). |
| Monitoring cost with many processes; wake-ups per hour | Review (platform) | Phase 8 | The per-process budget (0.03 ms) can hide costs that grow faster than linearly; measure with a few thousand processes and check wake-ups with Instruments on a real Mac. |
| Flagging iCloud Desktop/Documents items before trashing | Review (platform) | Phase 8 | Moving them to the Trash removes them from iCloud on every device; show a warning on such items. |
| Hard-linked duplicates' size in the Cleaner | Review (platform) | Phase 8 | The Cleaner counts a hard-linked copy at full size while the Duplicate Finder counts 0; align the two. |
| Reading history written by newer versions | Review (platform) | After 1.0 | An older build skips reports with outcome kinds it doesn't know; a tolerant "unknown" case would keep them readable. Data is not lost. |
| Lowercased path comparisons on case-sensitive drives | Review (team lead) | After 1.0 | Fails safe for refusals; a pick on a case-sensitive drive may match a folder that differs only in case. |
| UI test for a refused folder pick | Review (front end) | Phase 8 | Needs driving the open panel; the refusal and its message are covered by unit tests. |

## Open risks to decide before the phase starts

- **Phase 3:** resolved — ADR-009 measured sandbox limits; ADR-010 dropped the sandbox.
- **Phases 4–6:** which cleanup categories are reachable without Full Disk Access
  (user Trash, other apps' caches, TCC-protected folders)? Phase 4 skips protected
  folders unless picked (ADR-013); confirm on the owner's Mac which locations prompt.
- **Apple silicon fixture:** only Intel real-hardware data exists so far
  (`BatteryFixtures.realIntelMacBookPro16`); add an Apple silicon capture when available.
- **Phase 8:** Apple Developer Program enrolment, Developer ID signing and notarization.
  Do one trial notarization early (Phase 4) to catch surprises.

## Phase 8 (release)

| Item | Status | Reason |
|---|---|---|
| Developer ID signing and notarization | Waiting for the owner's Apple Developer enrolment | Scripts and workflow are ready and switch on when the secrets exist (`Documentation/RELEASE.md`). Until then releases are ad-hoc signed. |
| Clean-machine install, macOS 14, privacy prompts, Trash without Full Disk Access, open at login, notifications | Owner checklist | Need a signed build on real Macs. |
| Automatic updates | After 1.0 | Would need network code and a dependency (ADR-019). |
| Plural rules in the catalog (Arabic has six plural forms) | After 1.0 | Counts use separate singular and plural sentences; Arabic forms for 2 and 3–10 come with the native review. |
| Removing the unused "planned feature" placeholder code | After 1.0 | No longer shown anywhere; harmless. |
| Window at launch when the menu bar companion is off, in right-to-left languages | Owner checklist | The launch fix runs from the menu bar label; with the companion turned off, a right-to-left launch may still open without a window (use the Dock icon). Replace with `.defaultLaunchBehavior(.presented)` when macOS 15 becomes the minimum. |
| Contrast audit on the Battery screen | Phase 8, on a real Mac | `battery.health` and `battery.cycleCount` now pass, but two unnamed elements are reported in some CI runs and not others; non-blocking until Accessibility Inspector shows what they are. |
