# Contributing to MacPulse

Thank you for helping. MacPulse moves people's files and reads their activity, so it is
built with more care than a typical app: every change goes through a pull request, CI, and
the safety rules below.

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report security problems
privately, as described in [SECURITY.md](SECURITY.md), never in a public issue.

## Before you start
- **Bugs:** open an issue with the bug form first, unless the fix is small and obvious.
- **Features:** open a feature request and wait for agreement before writing code. Features
  that need network access, entitlements, admin rights or permanent deletion are out of
  scope unless an ADR accepts them (see [DECISIONS.md](Documentation/DECISIONS.md)).
- **Contributor License Agreement:** your first pull request asks you to sign the
  [CLA](CLA.md) by posting one sentence as a comment. You keep your copyright. The CLA
  lets the project owner, and only the owner, offer MacPulse under other licences;
  everyone else receives it under GPL-3.0-or-later. A pull request can't be merged until
  every author has signed.

## Set up
- macOS 14 or later, Xcode 16 or later, and `brew install xcodegen`.
- `xcodegen generate && open MacPulse.xcodeproj`, then ⌘R. Run `xcodegen generate` again
  whenever `project.yml` changes. Never commit `MacPulse.xcodeproj`.
- Tests: `swift test` (unit and integration) and `xcodebuild test -project MacPulse.xcodeproj
  -scheme MacPulse -destination 'platform=macOS'` (UI). See the README for the benchmarks.

## Branches and commits
- Branch from `main`: `fix/<topic>`, `feature/<topic>`, `chore/<topic>`, `docs/<topic>`
  (the owner uses `phase/<n>-<name>` for planned phases).
- **One logical change per commit** (a model, a service, a view, its tests, docs).
- **Every commit builds and passes the tests on its own.** Run
  `swift build -Xswiftc -warnings-as-errors && swift test` before each push.
- Write the subject in the imperative ("Skip dataless files in the duplicate search"),
  70 characters at most; explain *why* in the body.
- Don't rewrite history that is already in a pull request someone has reviewed.

## Pull requests
- Fill in the pull request template, including the safety checklist.
- Keep a pull request to one feature or fix.
- `main` is protected: a pull request needs the checks **Build, test and launch**,
  **String Catalog in sync** and **CLA signed** to pass, conversations resolved, and the
  branch up to date. Direct pushes and force pushes are refused.
- Pull requests are merged with a **merge commit** (squash and rebase are turned off), so
  the small commits stay on `main`.
- The owner reviews every change. Changes to `CODEOWNERS`, workflows, release scripts and
  the safety code get the closest look.

## Code rules
These are enforced by the compiler, the package structure or CI; the reasons are in the ADRs.
- **Swift 6 with strict concurrency, zero warnings.**
- **Layers:** `Features` never import `MacPulseInfrastructure`; they use Domain protocols
  injected through `AppDependencies`. `Domain` is Foundation-only.
- **Honest numbers:** every displayed value is a `Metric<T>` with provenance (measured,
  estimated or unavailable). Never present CPU % as battery use (ADR-011).
- **Fakes and preview data** are `#if DEBUG` only.
- **Logging:** log `AppError` with `Logger.log(_:context:)`; never log a path or file name
  as public.
- **Tests:** Swift Testing (`import Testing`) for unit and integration tests, XCTest for UI
  tests. Avoid fixed sleeps; wait for a condition instead.

## Safety rules (never break these)
- **No permanent deletion.** User items move only through the Trash service, only after the
  user confirms, and only after each item is checked again (ADR-015, ADR-017, ADR-018). CI
  allows exactly one `trashItem` call and one move-back call in the app.
- **No network code, no running other programs, no private APIs, no entitlements, no App
  Sandbox changes and no admin prompts** without an accepted ADR (ADR-010). CI checks the
  sources and the binary.
- **Protected locations stay protected.** Never widen `CleanupSafetyPolicy`, the scan
  exclusions or the pick rules without tests that show what stays refused.
- **Privacy prompts:** read Desktop, Documents, Downloads, iCloud Drive and other apps'
  data only after the user picks them.

## Strings and translations
- Write user-facing text with `String(localized:)`, `Text("…")` and similar, never by
  joining pieces of sentences. Package code passes `bundle: .module`.
- Don't edit English in `Localizable.xcstrings` by hand: `scripts/sync-strings.sh`
  regenerates it, and the Strings workflow syncs it on pull requests.
- Arabic is a draft until a native speaker reviews it. Mark new Arabic strings
  "needs review", and keep format specifiers identical.

## Documentation
- Record a decision as a new ADR in `Documentation/DECISIONS.md`.
- Record scope moved later in `Documentation/DEFERRED.md`.
- Add user-visible changes to `CHANGELOG.md` under **Unreleased**.
- Never claim something is verified unless a test or recorded evidence proves it.

## Licence
By contributing you agree that your work is distributed under the
[GNU General Public License v3.0 or later](LICENSE), and you accept the [CLA](CLA.md).
