# Support

## Getting help
Open an issue at <https://github.com/mrismail/MacPulse/issues> with your macOS version, Mac
model and MacPulse version (Settings > About). Never paste file paths you consider private.

## Reporting a crash
MacPulse has no crash reporter, because it has no network access. If it quits unexpectedly:
1. Open **Console**, choose **Crash Reports**, and find the newest `MacPulse` report (the
   files are in `~/Library/Logs/DiagnosticReports`).
2. Attach the report to an issue. Reports can contain paths from your Mac; remove anything
   you don't want to share.

For other problems, **Settings > About > Copy Diagnostics** copies version and hardware
details without any file names.

## Uninstalling
1. In MacPulse Settings, turn off **Open MacPulse at login** (or remove it in System
   Settings > General > Login Items).
2. Quit MacPulse from its menu bar item, then move `/Applications/MacPulse.app` to the Trash.
3. To remove its data too, move these to the Trash:
   - `~/Library/Application Support/MacPulse` (history)
   - `~/Library/Preferences/com.mrismail.MacPulse.plist` (settings)
   - `~/Library/Saved Application State/com.mrismail.MacPulse.savedState`, if present
4. Items MacPulse moved to the Trash stay there until you empty it.

Security issues: see [SECURITY.md](SECURITY.md).
