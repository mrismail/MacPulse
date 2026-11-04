# MacPulse 1.0.0

The first release of MacPulse: battery health, app energy use and disk space on your
MacBook, with duplicate finding and cleanup that never delete anything permanently. It
runs entirely on your Mac: no account, no network access, no data collected.

## Features
- **Overview:** charge, health, free space, the most active apps, the last scan and the last cleanup.
- **Battery:** charge, health (current versus design capacity), cycle count, temperature, power draw and time remaining, with charge history. Every value is labeled as measured, estimated or unavailable.
- **Energy:** per-app CPU, memory and wake-ups, an energy-impact estimate, trends, and optional alerts when an app keeps using a lot of CPU. MacPulse never shows CPU use as battery use.
- **Space Analyzer:** scans a disk or folder (it doesn't follow links or cross onto other disks), with the largest files and folders, categories, exclusions and scan history.
- **Duplicate Finder:** groups files with identical content, checked byte for byte. Hard links are counted once. Files that are only in iCloud are skipped and never downloaded.
- **Cleaner:** caches, logs, old downloads, empty folders, large files and marked duplicates.
  - You review and confirm everything; items go to the Trash only.
  - Each item is checked again just before it moves.
  - Put Back works from the cleanup history.
- **Menu bar companion and Settings:** monitoring intervals, history retention, open at login (off by default), and cleanup preferences.
- **Languages:** English, plus a draft Arabic translation laid out right to left (being reviewed).

## Requirements
macOS 14 Sonoma or later, on Apple silicon or Intel.

## Install
Open the DMG and drag MacPulse to Applications. See `Documentation/KNOWN_LIMITATIONS.md` before you use the Cleaner.
