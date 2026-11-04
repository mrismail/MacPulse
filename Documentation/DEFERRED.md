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
| String Catalog extraction and Arabic translation | (owner requirement) | Phase 8 | Needs Xcode's string extraction on a Mac and a native-speaker review; groundwork in ADR-008. |
| Snapshot tests (light/dark/RTL) | Review finding | After 1.0 | Needs a third-party snapshot library (zero-dependency rule). |
| macOS 14 launch verification | Phase 1 acceptance | Before Phase 8 | CI runners are macOS 15; verify on a macOS 14 VM before release. |
| Contrast audit findings on the Battery screen (`battery.health`, `battery.cycleCount` and 4 unnamed elements) | Accessibility (review) | Delivered (review fixes) | Card text now uses `Palette.secondaryText`; the CI audit reports no contrast issues and is blocking again. |
| Every commit building on its own (Phase 7) | CLAUDE.md | Not rewritten | "Put items back from the Trash" (commit before "Settings, menu bar companion and Put Back") added an enum case whose exhaustive switch was updated in the next commit, so that one commit doesn't compile alone. History is pushed; kept as is. |
| One shared safe walker for scanner, duplicate collector and empty folders | Review (team lead) | After 1.0 | The three walks apply the same rules (policy, device + inode, no links), each covered by its own tests; empty folders now also stop on cancellation and accept the Data volume. Merging them is a refactor without a user-visible change. |
| Package strings in a String Catalog (`bundle: .module`) | Review (front end) | Phase 8 | Needed for the Arabic translation. Concatenated phrases were rewritten as whole localized strings in the review fixes. |
| UI tests for the menu bar panel, Put Back and adding exclusions | Review (front end) | Phase 8 | XCUITest can't open status items reliably; Put Back and exclusions are covered by unit and integration tests. |
| Adaptive layouts (`ViewThatFits`) for four-metric rows and large text | Review (front end) | Phase 8 | Polish pass with the release screenshots. |
| Replacing fixed sleeps in two feature tests | Review (team lead) | Phase 8 | The tests are stable on CI; they will move to explicit waits when touched. |
| Each review-fix commit building on its own | CLAUDE.md | Not verified | Several review fixes span model, service and view; "Close the Cleaner's safety gaps from the review" is one larger commit for that reason. CI tests the branch tip. |

## Open risks to decide before the phase starts

- **Phase 3:** resolved — ADR-009 measured sandbox limits; ADR-010 dropped the sandbox.
- **Phases 4–6:** which cleanup categories are reachable without Full Disk Access
  (user Trash, other apps' caches, TCC-protected folders)? Phase 4 skips protected
  folders unless picked (ADR-013); confirm on the owner's Mac which locations prompt.
- **Apple silicon fixture:** only Intel real-hardware data exists so far
  (`BatteryFixtures.realIntelMacBookPro16`); add an Apple silicon capture when available.
- **Phase 8:** Apple Developer Program enrolment, Developer ID signing and notarization.
  Do one trial notarization early (Phase 4) to catch surprises.
