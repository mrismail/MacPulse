# MacPulse

[![CI](https://github.com/mrismail/MacPulse/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/mrismail/MacPulse/actions/workflows/ci.yml)
[![License: GPL v3 or later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey.svg)

A native macOS utility that helps MacBook users understand battery health and energy use,
see what is filling their disk, find duplicate files and clean up safely. Everything runs
locally: no account, no uploads.

> **Status:** 1.0.0 release candidate (Phase 8).
> Battery Monitor, Energy (per-app activity and drain alerts), Space Analyzer,
> Duplicate Finder (content-verified), Cleaner (Trash only, always confirmed, Put Back),
> menu bar companion and Settings, in English and draft Arabic. Builds are ad-hoc signed
> until the Developer ID is in place.

## Install

Download the DMG from [Releases](https://github.com/mrismail/MacPulse/releases), open it and
drag MacPulse to **Applications**, then open it from there (not from the DMG). Until builds
are notarized, macOS blocks the first launch: open MacPulse once, then go to **System
Settings > Privacy & Security**, click **Open Anyway** next to the MacPulse message and
confirm with your password. See [release notes](Documentation/RELEASE_NOTES.md),
[known limitations](Documentation/KNOWN_LIMITATIONS.md), [privacy](PRIVACY.md) and
[support and uninstalling](SUPPORT.md).

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

## Release and localization

- [Releasing](Documentation/RELEASE.md): signing, notarization, DMG and the Release workflow.
- [Owner checklist](Documentation/OWNER_CHECKLIST.md): checks on a real Mac before publishing.
- [Test report](Documentation/TEST_REPORT.md).
- Strings: `scripts/sync-strings.sh` regenerates `Localizable.xcstrings` from the source.

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

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md); your first pull request asks you to sign the
[Contributor License Agreement](CLA.md). Report security issues privately, as described in
[SECURITY.md](SECURITY.md). Changes are listed in the [changelog](CHANGELOG.md).

## License

Copyright © 2026 Mohamed Ismail.

MacPulse is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3
of the License, or (at your option) any later version. It is distributed in the hope that
it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for details.

SPDX-License-Identifier: GPL-3.0-or-later
