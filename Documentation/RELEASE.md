# Releasing MacPulse

MacPulse is distributed outside the Mac App Store as a DMG on GitHub Releases, signed
with a Developer ID and notarized by Apple (ADR-002, ADR-010, ADR-019). There is no
auto-update: users download new versions from the Releases page.

## One-time setup (owner)

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/).
2. In Xcode > Settings > Accounts, create a **Developer ID Application** certificate.
   Export it from Keychain Access as a `.p12` file with a password.
3. In [App Store Connect](https://appstoreconnect.apple.com/) > Users and Access >
   Integrations > App Store Connect API, create a key with the **Developer** role. Download
   the `.p8` file (only possible once) and note the key ID and issuer ID.
4. In GitHub > Settings > Environments, create an environment named **release**:
   - Required reviewers: yourself. No tag build can sign anything until you approve it.
   - Deployment branches and tags: selected tags only, pattern `v*.*.*`.
   - Environment secrets (not repository secrets, so pull requests and manual runs never see them):

| Secret | Value |
|---|---|
| `MACPULSE_TEAM_ID` | Your 10-character team ID (Membership details) |
| `MACPULSE_CERTIFICATE_P12` | `base64 -i DeveloperID.p12` output |
| `MACPULSE_CERTIFICATE_PASSWORD` | The `.p12` password |
| `MACPULSE_NOTARY_KEY` | `base64 -i AuthKey_XXXX.p8` output |
| `MACPULSE_NOTARY_KEY_ID` | The API key ID |
| `MACPULSE_NOTARY_ISSUER_ID` | The issuer ID |

   If the keychain holds more than one Developer ID Application certificate for the team,
   also set `MACPULSE_SIGNING_IDENTITY` (its full name or SHA-1) when building locally.
5. Run `scripts/repo/apply-protection.sh` once (ADR-021). It applies the rulesets in
   `.github/rulesets/`:
   - **Protect main** (branch ruleset): pull request required, merge commits only, the
     checks "Build, test and launch", "String Catalog in sync" and "CLA signed", branch up
     to date, conversations resolved, no force pushes or deletion.
   - **Release tags** (tag ruleset, `v*.*.*`): only repository admins may create, update
     or delete them.
6. The same script turns off squash and rebase merging, as CLAUDE.md requires.

A tagged build fails unless all six secrets are present. To publish an **ad-hoc** release
on purpose (before enrolment), set the repository variable `MACPULSE_ALLOW_ADHOC_RELEASE`
to `true`; the draft release then says it isn't notarized and how to open it. Pull requests
and manual runs always build ad-hoc, without secrets.

## Making a release

1. Update `Documentation/RELEASE_NOTES.md`.
2. Set the version: `scripts/release/bump-version.sh 1.0.1`, commit, open a PR and merge it
   once CI is green.
3. Tag `main`: `git tag v1.0.1 && git push origin v1.0.1`.
4. The **Release** workflow checks that the tag matches the version, is on `main` and
   passed CI, waits for your approval of the release environment, then builds the app
   (build number = commit count, Apple silicon and Intel), signs it, notarizes and staples
   the app and the DMG, and creates a **draft** GitHub release with the DMG and its SHA-256.
   Notarization waits at most 30 minutes; if Apple doesn't accept it, the job prints
   Apple's log.
5. Download the DMG, check it on a clean Mac (`Documentation/OWNER_CHECKLIST.md`), then
   publish the draft.

## Building locally

```sh
brew install xcodegen
scripts/release/build-release.sh          # ad-hoc, or Developer ID with MACPULSE_TEAM_ID set
scripts/release/make-dmg.sh               # build/release/MacPulse-<version>.dmg
# With an API key:
MACPULSE_NOTARY_KEY_PATH=~/keys/AuthKey_XXXX.p8 MACPULSE_NOTARY_KEY_ID=… MACPULSE_NOTARY_ISSUER_ID=… \
  scripts/release/notarize.sh build/release/export/MacPulse.app
```

## Localization

`App/MacPulseApp/Resources/Localizable.xcstrings` is generated from the compiler's
extracted strings by `scripts/sync-strings.sh`; the **Strings** workflow keeps it in sync on
every PR. Translations are edited in Xcode's catalog editor. Arabic is a draft marked
"Needs Review" until a native speaker reviews it.
