# MacPulse privacy policy

MacPulse runs entirely on your Mac. It has no account, no network code, no analytics and
no crash reporter, so nothing it reads or records leaves your Mac (ADR-010). CI checks
the app for networking APIs on every change.

## What MacPulse reads
- **Battery:** charge, health, cycle count, temperature and power figures that macOS reports.
- **Apps:** the names and locations of your running apps and how much CPU, memory and
  energy each uses — the same information Activity Monitor shows. It never reads what is
  inside your apps or documents, and it can't see other users' processes.
- **Files:** names, sizes and dates of files in folders you scan. Only the Duplicate Finder
  reads file contents, and only of files in folders you chose, to compare them.

## What MacPulse stores (on this Mac only)
In `~/Library/Application Support/MacPulse/History`:
- `Battery`: battery history, kept 7, 30 or 90 days.
- `Usage`: hourly CPU and energy per app, kept 7, 14 or 30 days. It holds app names and locations only.
- `Scans`: scan totals and the five biggest folders, kept 180 days. It never holds file names.
- `Cleanup`: what each cleanup moved to the Trash and where, kept 30 days, so items can be put back.

Settings are kept in MacPulse's preferences. You can clear each history in Settings at any
time. Files are readable only by your user account.

## What MacPulse never does
- It never sends data anywhere, and never shows ads or tracks you.
- It never deletes files permanently: the Cleaner only moves items you confirmed to the Trash.
- It never asks for administrator rights or Full Disk Access.

The app's privacy manifest (`PrivacyInfo.xcprivacy`) declares no tracking and no
collected data.

Questions: see [SUPPORT.md](SUPPORT.md).
