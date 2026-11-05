## What and why
<!-- What does this change, and why? Link the issue: "Fixes #123". -->

## How it was tested
<!-- Tests added or changed, and anything checked by hand on a real Mac (macOS version, model). -->

## Checklist
- [ ] One logical change per commit, and every commit builds and passes the tests on its own.
- [ ] `swift build -Xswiftc -warnings-as-errors && swift test` pass locally.
- [ ] New behaviour has tests (Swift Testing; XCUITest for UI).
- [ ] User-facing text uses `String(localized:)` / `Text("…")`, with no joined sentence pieces.
- [ ] Displayed numbers are `Metric<T>` values with provenance.
- [ ] `CHANGELOG.md` updated under **Unreleased** for user-visible changes.
- [ ] Docs, ADR or `DEFERRED.md` updated if a decision or scope changed.

## Safety (tick each, or explain below)
- [ ] Doesn't add network code, process launching, private APIs, entitlements or admin prompts.
- [ ] Doesn't add any way to delete, move or change user files outside the Trash service.
- [ ] Doesn't widen the cleanup safety policy, exclusions or protected locations.
- [ ] Doesn't log paths or file names publicly.
- [ ] Doesn't change workflows, release scripts or signing.

<!-- First-time contributors: the CLA check will ask you to sign CLA.md with a comment. -->
