# Release checklist on a real Mac (owner)

CI runs on macOS 15 virtual machines with Xcode installed and full disk access. CI can't prove the items below. Tick each one on the release build (the DMG from the Release workflow), and record the Mac, macOS version and date.

## Install
- [ ] A clean Mac (or a new user account) without Xcode: open the DMG, drag MacPulse to Applications and open it. Notarized builds open without a warning; ad-hoc builds need right-click > Open.
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
- [ ] Turn on Open at login, log out and back in: MacPulse starts in the menu bar. Turn it off again.
- [ ] Drain alerts: allow notifications, then run a CPU-heavy app; one alert appears.
- [ ] Closing the window keeps the menu bar companion running; Quit stops it.
- [ ] Close the window, quit from the menu bar, then open MacPulse from Finder: the window
      appears (CI once saw a launch with no window after the app had been killed; the menu
      bar's "Open MacPulse" and a Dock click must bring it back).

## Accessibility and language
- [ ] Use Accessibility Inspector's audit on the Battery screen and note any contrast findings (DEFERRED).
- [ ] VoiceOver reads the battery values with their "measured" or "estimated" labels.
- [ ] System Settings > Language: Arabic. The layout is right to left and the text is translated. A native speaker reviews `Localizable.xcstrings` and marks strings as reviewed.
