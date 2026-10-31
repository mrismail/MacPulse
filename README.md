# MacPulse

A native macOS utility that helps MacBook users understand battery health and energy use,
see what is filling their disk, find duplicate files and clean up safely. Everything runs
locally: no account, no uploads.

> **Status:** Phase 1 (foundation) — app shell, navigation, design system, CI.
> Battery, Energy, Space Analyzer, Duplicate Finder and Cleaner arrive in Phases 2–6.

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

## Tests

```sh
swift build
swift test
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
does not ask for administrator access.
