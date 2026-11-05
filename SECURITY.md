# Security

## Reporting a vulnerability
Please report security issues privately through GitHub's **Report a vulnerability**
(Security > Advisories) on <https://github.com/mrismail/MacPulse>, not in a public issue.

## How MacPulse is built to be safe without the App Sandbox
MacPulse can't use the App Sandbox: the sandbox blocks the per-app CPU and energy figures
that the Energy screen needs (ADR-009, ADR-010). Instead:
- **No entitlements, Hardened Runtime, Developer ID and notarization.** CI fails if the
  Release build has any entitlement or lacks Hardened Runtime.
- **No network code and no running other programs.** CI rejects networking, process
  control, dynamic lookup and process-spawning APIs in the sources and in the binary.
- **No permanent deletion.**
  - User items leave their place only through one Trash service, after you confirm.
  - Each item is checked again just before it moves: identity, links, the safety policy, and for duplicates the kept copy.
  - Items are checked once more after the move.
  - CI allows exactly one `trashItem` call and one move-back call in the whole app (ADR-015, ADR-017, ADR-018).
- **Protected locations.** System folders, other apps' data, hidden items, your standard folders and MacPulse's own data are never offered for cleanup. Folders you pick are judged by their real path.
- **Least privilege for privacy prompts.** Desktop, Documents, Downloads and iCloud Drive are read only when you choose them.
- **Release pipeline.**
  - Signing secrets live in a protected GitHub environment that needs the owner's approval.
  - Only tags on `main` with green CI are signed.
  - Pull requests build without secrets and with a read-only token.
  - Actions and tools are pinned.
