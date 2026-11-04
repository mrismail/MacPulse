# Test report: MacPulse 1.0.0 (release candidate)

All figures come from GitHub Actions on `phase/8-release` (macOS 15.8 virtual machine,
Xcode 16, Release build unless noted). Checks that CI can't run are listed under
"Not verified by CI" and are in `Documentation/OWNER_CHECKLIST.md`.

## Automated tests
| Suite | Framework | Count | Result |
|---|---|---|---|
| Domain, Shared, Features, AppCore unit tests and Infrastructure integration tests (real files in temporary folders) | Swift Testing | 358 | All pass |
| UI tests: navigation, Battery, Overview, Energy, Space Analyzer, Duplicate Finder, Cleaner (confirm, Escape, Cancel), Settings, accessibility audit, Arabic (window opens, right-to-left layout, translated text) | XCTest/XCUITest | 21 | All pass; the Battery-screen contrast audit is non-blocking (below) |
| Build with warnings as errors (Swift 6, strict concurrency) | xcodebuild | Debug and Release | Pass |
| Launch smoke test (app stays running for 10 s, in English and in Arabic with a translated window title) | CI | — | Pass |

## Spec §10 coverage
| Scenario | Evidence |
|---|---|
| Files changing during a scan or search | Space Analyzer scan with files being added and removed; a duplicate rewritten just before it is read; a kept copy edited or deleted before cleanup; an empty folder that gains a file; an old-download folder that gains a file |
| Interrupted scans and cleanups | Stop during a scan; history saved while a cleanup runs and replaced by the final report; real-store round trip |
| Long sessions | Not covered by CI (owner checklist: one-hour session) |
| Recovery from the Trash | Put Back into a free place only; refuses a different item, a missing identity and other users' `.Trashes`; no Trash access falls back to Finder |
| Inaccessible files | Unreadable folders reported as skipped; unreadable files left out of duplicates |
| Protected folders | Policy tests for system locations, Library, hidden items, picks (including `/Volumes/<startup disk>` and case or `/System/Volumes/Data` paths) |
| Large groups | Duplicate benchmark with 502 groups (largest 100 copies); cleanup history with 500 items saved in batches |
| Memory | Benchmarks below |

## Performance (CI virtual machine)
| Benchmark | Result | Budget |
|---|---|---|
| Monitoring overhead | 3.9 ms CPU per sample for 276 processes (0.014 ms per process), 0.0065 % of one core at the background rate, 5.3 MB footprint, 0.17 wake-ups per sample | 0.03 ms per process; 0.1 % of a core |
| Space Analyzer, 200,000 files in 2,200 folders | 20.2 s, 76 MB peak memory, longest main-thread stall 31 ms | 150 MB; no stall over 100 ms |
| Duplicate Finder, 12,504 files, 502 groups | 10.7 s, 502 of 502 groups found, 0 look-alikes grouped, 43 MB peak, longest stall 25 ms | All groups found, none wrong; 100 MB |

## Release bundle
| Check | Result |
|---|---|
| Version and build | 1.0.0 (build number = commit count, for example 186) |
| Entitlements | None (`{}`), Hardened Runtime on |
| Icon and privacy manifest | `Assets.car`, `AppIcon.icns`, `PrivacyInfo.xcprivacy` (no tracking, no collected data) present |
| Release DMG (Release workflow) | Builds, mounts, and holds a valid signed app with an Applications link; SHA-256 published with it. Ad-hoc signed until the Developer ID secrets exist |
| Guardrails | No networking, process control, dynamic lookup, or file-changing API outside the allowed files; forbidden symbols absent from the binary |
| String Catalog | In sync with the source on every PR (Strings workflow) |

## Found and fixed by these tests
- In a right-to-left layout (Arabic), macOS 15 started MacPulse with only its menu bar item and no window (shown by CI's window list). MacPulse now opens its window at launch when none is visible.
- In Arabic the text was translated but the layout stayed left to right. The layout direction now follows the app's language; the Arabic UI test checks that the sidebar is on the right.
- About 40 user-facing strings weren't localizable (sidebar titles, badges, battery recommendations, error messages), and one sentence was built from two pieces. These were found when the catalog was generated.

## Not verified by CI
- Developer ID signing and notarization (waiting for enrolment).
- macOS 14, a clean Mac without Xcode, real battery hardware, and Apple silicon versus Intel energy reporting.
- Privacy prompts, the Trash and Put Back without Full Disk Access, open at login and notifications on a signed build.
- The Battery-screen contrast audit. After the neutral badge border and 85 % secondary text, `battery.health` and `battery.cycleCount` passed, and one run passed completely. Later runs flagged two unnamed elements (probably chart labels), so the check stays non-blocking until it is checked with Accessibility Inspector.
- A native-speaker review of the Arabic strings.
