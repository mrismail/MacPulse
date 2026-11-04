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
4. In GitHub > Settings > Secrets and variables > Actions, add:

| Secret | Value |
|---|---|
| `MACPULSE_TEAM_ID` | Your 10-character team ID (Membership details) |
| `MACPULSE_CERTIFICATE_P12` | `base64 -i DeveloperID.p12` output |
| `MACPULSE_CERTIFICATE_PASSWORD` | The `.p12` password |
| `MACPULSE_NOTARY_KEY` | `base64 -i AuthKey_XXXX.p8` output |
| `MACPULSE_NOTARY_KEY_ID` | The API key ID |
| `MACPULSE_NOTARY_ISSUER_ID` | The issuer ID |

Without these secrets every build is **ad-hoc signed**: it runs, but macOS asks users to
confirm the first launch, and it can't be notarized.

## Making a release

1. Update `Documentation/RELEASE_NOTES.md`.
2. Set the version: `scripts/release/bump-version.sh 1.0.1`, commit, open a PR and merge it
   once CI is green.
3. Tag `main`: `git tag v1.0.1 && git push origin v1.0.1`.
4. The **Release** workflow builds the app (build number = commit count), signs it,
   notarizes and staples the app and the DMG, and creates a **draft** GitHub release with
   the DMG and its SHA-256.
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
