# Release checklist on a real Mac (owner)

CI runs on macOS 15 virtual machines with Xcode installed and full disk access. CI can't prove the items below. Tick each one on the release build (the DMG from the Release workflow), and record the Mac, macOS version and date.

## Install
- [ ] A clean Mac (or a new user account) without Xcode: open the DMG, drag MacPulse to Applications and open it. Notarized builds open without a warning. Ad-hoc builds: the first launch is blocked; System Settings > Privacy & Security > Open Anyway lets it run (macOS 15 no longer offers right-click > Open).
- [ ] Opened straight from the DMG (translocated): MacPulse runs; note whether Open at login fails, as documented.
- [ ] Nothing asks for permission at launch: privacy prompts appear only when you choose a protected folder or turn on alerts.
- [ ] Opening a second copy brings the running one to the front instead of starting another.
- [ ] macOS 14 Sonoma: MacPulse launches and every screen opens.
- [ ] macOS 15 or later: the same.
- [ ] The app icon appears in Finder, the Dock and the menu bar companion's About.

## Battery and Energy
- [ ] The battery values match System Information > Power (charge, cycle count, condition).
- [ ] With Firefox or a video playing, the top apps in Energy roughly match Activity Monitor's CPU tab.
- [ ] The overhead benchmark stays within budget on this Mac: `MACPULSE_DIAGNOSTICS=1 /Applications/MacPulse.app/Contents/MacOS/MacPulse --macpulse-overhead-benchmark`.
- [ ] A one-hour battery session records history without gaps (lid open).

## Storage
- [ ] Scanning the home folder works; choosing Documents or Desktop shows the macOS permission prompt once, and refusing it is reported clearly.
- [ ] The Duplicate Finder on the home folder finishes; files that are only in iCloud are listed as skipped and are **not** downloaded (watch the iCloud status in Finder).

## Cleaner (without Full Disk Access)
- [ ] Move a test file to the Trash with the Cleaner, then Put Back from history. Note whether MacPulse or Finder had to put it back.
- [ ] Confirm that nothing outside the confirmed list moved.

## System integration
- [ ] Turn on Open at login, log out and back in: MacPulse starts with its window and the menu bar item. Turn it off again.
- [ ] Drain alerts: allow notifications, then run a CPU-heavy app; one alert appears.
- [ ] Closing the window keeps the menu bar companion running; Quit stops it.
- [ ] Close the window, quit from the menu bar, then open MacPulse from Finder: the window
      appears (CI once saw a launch with no window after the app had been killed; the menu
      bar's "Open MacPulse" and a Dock click must bring it back).

## Accessibility and language
- [ ] Use Accessibility Inspector's audit on the Battery screen and note any contrast findings (DEFERRED).
- [ ] VoiceOver reads the battery values with their "measured" or "estimated" labels.
- [ ] System Settings > Language: Arabic. The layout is right to left and the text is translated. A native speaker reviews `Localizable.xcstrings` and marks strings as reviewed.

## Updating and uninstalling
- [ ] Install 1.0.0, use it for a day, then install the next build over it: battery, app usage, scan and cleanup history are still there, and settings are kept.
- [ ] From an ad-hoc build to the first Developer ID build: note which permissions macOS asks for again (expected, KNOWN_LIMITATIONS).
- [ ] Uninstall as described in SUPPORT.md: no MacPulse files are left and the login item is gone.

## Right to left and VoiceOver
- [ ] Arabic with the menu bar item turned off (Settings): the window still opens at launch.
- [ ] Arabic: alerts, the folder picker and menus read right to left; charts' time axes run in the expected direction.
- [ ] VoiceOver can reach and read every screen, not only Battery: sidebar, Energy table, Space Analyzer rows, duplicate checkboxes, Cleaner list and dialog, Settings.
