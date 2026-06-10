# Contributing

## How it works

Brightness Overclock is built around macOS' Extended Dynamic Range (EDR) behavior on built-in XDR displays.

At a high level:

1. The app finds the built-in display with CoreGraphics (`CGGetOnlineDisplayList`, `CGDisplayIsBuiltin`).
2. It creates a hidden 1×1 px borderless `NSWindow` containing a Metal `MTKView`.
3. The Metal layer is configured for extended-range rendering (`rgba16Float`, extended linear sRGB, `wantsExtendedDynamicRangeContent`).
4. Keeping that tiny extended-range surface visible encourages WindowServer to keep XDR/EDR headroom active for the display.
5. Once EDR is active, the app reads the screen's current headroom via `NSScreen.maximumExtendedDynamicRangeColorComponentValue`.
6. It captures the display's current gamma tables with `CGGetDisplayTransferByTable`.
7. It applies a boost by scaling those gamma tables and writing them back with `CGSetDisplayTransferByTable`.
8. On shutdown or boost disable, it restores normal display color behavior with `CGDisplayRestoreColorSyncSettings`.

Brightness-key support is handled separately:

- A `CGEventTap` listens for `NX_SYSDEFINED` media-key events.
- The native backlight level is read via the private DisplayServices framework (`DisplayServicesGetBrightness`).
- Brightness Up is intercepted only once native brightness is effectively maxed.
- Brightness Down walks down the boost range before passing control back to macOS.

The app intentionally targets the built-in XDR display only. External displays and non-XDR panels are out of scope.

## Development

### Requirements

- macOS 14 or newer.
- Swift 5.9 or newer.
- Xcode command line tools.
- Optional but recommended: an Apple Development signing identity for stable Accessibility permissions across rebuilds.

### Common commands

| Task | Command |
| --- | --- |
| Run tests | `swift test` |
| Build release binary | `make build` |
| Build `.app` bundle | `make app` |
| Build and open locally | `make run` |
| Install to `/Applications` | `make install` |
| Remove build outputs | `make clean` |

### Project layout

- `Sources/BrightnessOverclock/` contains the SwiftUI menu bar app and launch-at-login UI.
- `Sources/OverclockCore/` contains display boosting, brightness-key interception, and pure boost state/math.
- `Tests/OverclockCoreTests/` covers the pure logic and the `BoostEngine` lifecycle through test seams.
- `Resources/Info.plist` is copied into the app bundle by the Makefile.

### Testing notes

Prefer keeping platform-heavy behavior behind small seams and testing the lifecycle from `BoostState` through `BoostEngine`. Pure logic such as boost math, key decisions, and key event pairing should stay deterministic and unit-tested.

Run the full suite before installing:

```sh
swift test
```

### Signing and permissions

`make app` signs the bundle with the first available Apple Development identity. If none is found, it falls back to ad-hoc signing.

Ad-hoc signing is fine for local testing, but macOS may treat each rebuild as a different app for Accessibility permission purposes. If brightness-key interception stops working after a rebuild, re-grant Accessibility permission or use an Apple Development certificate.
