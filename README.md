# MacPulse

A native macOS utility that helps MacBook users understand battery health and energy use,
see what is filling their disk, find duplicate files and clean up safely. Everything runs
locally: no account, no uploads.

> **Status:** Phases 1–7 done, Phase 8 (signed, notarized release) next.
> Battery Monitor, Energy (per-app activity and drain alerts), Space Analyzer,
> Duplicate Finder (content-verified), Cleaner (Trash only, always confirmed, Put Back),
> menu bar companion and Settings. Not yet signed with a Developer ID.

## What MacPulse never does

- Delete anything permanently: the Cleaner only moves items to the Trash, after you
  confirm, re-checking each item first (ADR-015).
- Use the network, run other programs, ask for admin rights or Full Disk Access (ADR-010).
- Read your documents' contents, except to compare files you asked the Duplicate Finder
  to compare. Files that are only in iCloud are skipped, and reads run with macOS told
  not to download placeholders, so a search doesn't download them (ADR-014, ADR-018).

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build and run

```sh
git clone https://github.com/mrismail/MacPulse.git
cd MacPulse
xcodegen generate          # creates MacPulse.xcodeproj from project.yml
open MacPulse.xcodeproj    # then ⌘R
```

Run `xcodegen generate` again whenever `project.yml` changes.

## Diagnostics

```sh
MACPULSE_DIAGNOSTICS=1 MacPulse.app/Contents/MacOS/MacPulse --macpulse-process-access-probe
MACPULSE_DIAGNOSTICS=1 MacPulse.app/Contents/MacOS/MacPulse --macpulse-overhead-benchmark
MACPULSE_DIAGNOSTICS=1 MACPULSE_SCAN_FILES=1000000 MacPulse.app/Contents/MacOS/MacPulse --macpulse-scan-benchmark
MACPULSE_DIAGNOSTICS=1 MacPulse.app/Contents/MacOS/MacPulse --macpulse-duplicate-benchmark
```

Each prints one JSON line (counts and timings only, no names) and exits. The two
benchmarks create and remove their own files in the temporary folder.

## Tests

```sh
swift build
swift test                                   # unit + integration tests
xcodegen generate && xcodebuild test \
  -project MacPulse.xcodeproj -scheme MacPulse -destination 'platform=macOS'   # UI tests
```

## Project layout

```
App/            @main app (MacPulseApp) and composition root (Core)
Domain/         Models, repository protocols, use cases, policies
Infrastructure/ macOS integration (IOKit, libproc, filesystem, Trash)
Features/       Screens and view models
Shared/         Design system, utilities, logging
Tests/          Unit and integration tests
Documentation/  Architecture and decision records
```

See [Documentation/ARCHITECTURE.md](Documentation/ARCHITECTURE.md) and
[Documentation/DECISIONS.md](Documentation/DECISIONS.md).

## Privacy

MacPulse never uploads file names, file contents or usage data, needs no account and
does not ask for administrator access. It runs with the Hardened Runtime and no special
entitlements, and will be distributed as a Developer ID–signed, notarized download
(Phase 8; see ADR-010). To find battery-draining apps it reads the list of your running
processes and their CPU, memory and energy use — what Activity Monitor shows.
