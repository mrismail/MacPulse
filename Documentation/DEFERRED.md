# Deferred scope

Items from the spec that are intentionally not delivered in the phase where they first
appear. Each has a target phase and a reason. Update this file whenever scope moves.

| Spec item | Spec section | Moved to | Reason |
|---|---|---|---|
| Battery screen "process activity table" | §3 Battery screen | Phase 3 (Energy) | Delivered in Phase 3 (Energy). |
| Configurable battery monitoring frequency | §3 Settings | Phase 7 | Fixed at 60 s with 10 s timer tolerance until the Settings work. |
| Full process table on the Battery screen | §3 Battery screen | Phase 7 | The Battery screen shows the top 5 apps with a link to the full Energy table. |
| Alert/notification settings in the Settings screen | §3 Settings "Notifications" | Phase 7 | Alert settings live on the Energy screen next to what they control; Settings gets a Notifications section with the other preferences. |
| Rewriting Phase 3 history so every commit builds | Review (team lead) | Not planned | Several early Phase 3 commits failed tests on their own (fixture crash, identifier bug, misplaced tests). History is already pushed and reviewed; it is kept as is and the rule applies going forward. |
| Configurable process monitoring frequency | §2 Module B "configurable monitoring" | Phase 7 | Fixed: 60 s background, 10 s while the Energy screen is visible. Alert thresholds *are* configurable now. |
| Ending an app from MacPulse | Spec non-goal | Not planned | Spec forbids automatic termination; a manual "Quit" button may be considered with the owner later. |
| Configurable data retention | §3 Settings | Phase 7 | Fixed at 30 days (`BatteryMonitor.Configuration.defaultHistoryRetentionDays`). |
| Monitoring while the app is closed | §2 Module A history | Phase 7 | Requires a login item / menu-bar companion (`SMAppService`). History is recorded only while MacPulse runs. |
| Overview "recent scans and cleanup activity" | §3 Overview | Phases 4–6 | No scans exist yet; the Overview shows battery recommendations meanwhile. |
| String Catalog extraction and Arabic translation | (owner requirement) | Phase 7 | Groundwork done in Phase 2 (ADR-008). |
| Snapshot tests (light/dark/RTL) | Review finding | Phase 7 | Needs a third-party snapshot library; decide with the UI polish pass. |
| macOS 14 launch verification | Phase 1 acceptance | Before Phase 8 | CI runners are macOS 15; verify on a macOS 14 VM before release. |
| Contrast audit findings on the Battery screen (`battery.health`, `battery.cycleCount` and 4 unnamed elements) | Accessibility (review) | Phase 2 sign-off, local | The CI audit flags them but can't show colors. Inspect with Accessibility Inspector on a real Mac, fix, then make the contrast check blocking again (it is an expected failure in `MacPulseUITests` until then). Badge colors were already moved to label colors. |

## Open risks to decide before the phase starts

- **Phase 3:** resolved — ADR-009 measured sandbox limits; ADR-010 dropped the sandbox.
- **Phases 4–6:** which cleanup categories are reachable without Full Disk Access
  (user Trash, other apps' caches, TCC-protected folders)? Capability matrix before Phase 4.
- **Apple silicon fixture:** only Intel real-hardware data exists so far
  (`BatteryFixtures.realIntelMacBookPro16`); add an Apple silicon capture when available.
- **Phase 8:** Apple Developer Program enrolment, Developer ID signing and notarization.
  Do one trial notarization early (Phase 4) to catch surprises.
