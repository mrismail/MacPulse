# Deferred scope

Items from the spec that are intentionally not delivered in the phase where they first
appear. Each has a target phase and a reason. Update this file whenever scope moves.

| Spec item | Spec section | Moved to | Reason |
|---|---|---|---|
| Battery screen "process activity table" | §3 Battery screen | Phase 3 (Energy) | Needs the process sampler; blocked on the sandbox spike (ADR-002). A "coming soon" card holds the place. |
| Configurable battery monitoring frequency | §3 Settings | Phase 7 | Fixed at 60 s with 10 s timer tolerance until the Settings work. |
| Configurable data retention | §3 Settings | Phase 7 | Fixed at 30 days (`BatteryMonitor.Configuration.defaultHistoryRetentionDays`). |
| Monitoring while the app is closed | §2 Module A history | Phase 7 | Requires a login item / menu-bar companion (`SMAppService`). History is recorded only while MacPulse runs. |
| Overview "recent scans and cleanup activity" | §3 Overview | Phases 4–6 | No scans exist yet; the Overview shows battery recommendations meanwhile. |
| String Catalog extraction and Arabic translation | (owner requirement) | Phase 7 | Groundwork done in Phase 2 (ADR-008). |
| Snapshot tests (light/dark/RTL) | Review finding | Phase 7 | Needs a third-party snapshot library; decide with the UI polish pass. |
| macOS 14 launch verification | Phase 1 acceptance | Before Phase 8 | CI runners are macOS 15; verify on a macOS 14 VM before release. |
| Real `ioreg` fixtures from Intel and Apple silicon | Review finding | Phase 2 sign-off | Owner to capture `ioreg -rc AppleSmartBattery -a`; fixtures are synthetic until then. |

## Open risks to decide before the phase starts

- **Phase 3:** can a sandboxed app read other processes' CPU time and memory
  (`proc_pid_rusage`, `proc_pidinfo`)? 1-day spike in the signed app first.
- **Phases 4–6:** which cleanup categories are reachable from the sandbox (user Trash,
  other apps' caches, protected folders)? Capability matrix before Phase 4.
- **Phase 8:** Apple Developer Program enrolment; moving from ad-hoc to Team ID signing
  changes the container's code requirement (plan history migration).
