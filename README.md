# FluxClone

A minimal f.lux-style menu bar app for macOS. It warms and optionally dims your screen from sunset to sunrise.

## Build & run
```sh
./build.sh            # builds build/FluxClone.app (needs only the Xcode Command Line Tools)
open build/FluxClone.app
./build.sh --install  # copies to ~/Applications and launches (needed for "Start at Login")
```

## Usage (menu bar sun/moon icon)
- **Enabled**: master on/off switch (⌘E).
- **Night colour**: 1900K–6500K (10K steps). **Night brightness**: 10–100% (0.1% steps). While you drag either slider, it previews the full night look.
- **Disable for an hour / until sunrise**, then **Resume**.
- **Start at Login**.

The schedule follows the sun's elevation at your location. It fades over roughly 1 hour around sunset and sunrise, from +3° down to −6° civil twilight. Location is requested once and cached. If you deny it, the app approximates your location from the time zone (see System Settings › Privacy & Security › Location Services).

## Notes
- The app uses the public gamma-table API (`CGSetDisplayTransferByTable`). The screen goes back to normal when you quit, or if the app is killed.
- Turn off macOS Night Shift so the two don't stack.
- Debug commands: `build/FluxClone --print-schedule [lat lon]` prints today's curve, and `FLUX_FAKE_HOUR=21 build/FluxClone.app/Contents/MacOS/FluxClone` runs the app with a fake time of day.

## Uninstall
Quit from the menu, then delete `FluxClone.app`.
