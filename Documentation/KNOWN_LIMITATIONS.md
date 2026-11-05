# Known limitations (1.0.0)

- **Not yet notarized.** Until the Apple Developer ID is in place, the build is ad-hoc signed and macOS blocks its first launch.
  - Copy MacPulse to Applications first and open it from there. Run from the DMG, macOS starts it from a hidden temporary location, and open at login won't work.
  - Open it once; macOS says it can't be opened. Go to System Settings > Privacy & Security, click Open Anyway next to the MacPulse message, and confirm with your password. (On macOS 15 and later, right-click > Open no longer does this.)
  - Each ad-hoc build counts as a new app to macOS. After an update, it may ask again for folder access and notifications, and open at login may need turning on again.
  - Notarized builds open normally and keep these settings across updates.
- **No automatic updates.** MacPulse has no network access. Check GitHub Releases for new versions.
- **Monitoring only while MacPulse runs.** History is recorded while the app or its menu bar companion is running; nothing is recorded after you quit. Open at login is off unless you turn it on.
- **Battery energy per app is an estimate.** macOS reports CPU time, not battery use per app. On Intel Macs it reports no per-app energy at all, so MacPulse shows CPU activity and labels it that way.
- **Trash access.**
  - MacPulse doesn't ask for Full Disk Access. Without it, macOS hides the Trash from apps, so MacPulse can't show what is in it or empty it.
  - Put Back may then need Finder (Finder's Put Back always works).
  - This behaviour still has to be confirmed on a signed build.
- **Protected folders.** Desktop, Documents, Downloads and iCloud Drive are scanned only when you choose them, and macOS may ask for permission first.
- **iCloud items.** Moving an item from an iCloud-synced Desktop or Documents folder to the Trash removes it from iCloud on all your devices.
- **Scan results are a snapshot.** Results reflect the moment of the scan; scan again after large changes.
- **Arabic is a draft.** It is pending review by a native speaker.
- **Accessibility.** The contrast of some Battery-screen text is still being checked.

The full list of moved scope is in `Documentation/DEFERRED.md`.
