# MacFold

A native macOS menu bar app that frosts and shades the built-in display as you close your MacBook. Reopening reverses the effect. The perspective stretch anchors at the keyboard, with progressive frost toward the top edge and a late fade to black. [Design references](docs/DESIGN-REFERENCES.md).

The physical lid angle is the animation timeline: holding the lid holds the visual state. There are no duration-based closing animations. The app reads the Apple HID sensor at 60 polls/s, takes one desktop snapshot per closing interaction, and renders changes with Metal and Metal Performance Shaders. It does not continuously record the screen or save captured desktop images.

## Download

Download the Apple Silicon macOS 14+ app from [the 0.1.1 preview release](https://github.com/mani-kv/macduo-screen/releases/tag/v0.1.1). Unzip it, move **MacFold.app** to Applications, and open it. This preview is ad-hoc signed and **not notarized**; installation details and known limitations are in the [release notes](docs/releases/0.1.1.md).

## Run from source

Requires macOS 14 or later and a MacBook exposing the Apple lid-angle HID sensor. Building requires Swift 6 or later via Xcode or Command Line Tools; no third-party dependencies.

```sh
./scripts/run.sh
```

This builds, installs, and opens **/Applications/MacFold.app** (or `~/Applications` if the system folder is not writable). Reopen it anytime from Finder → Applications → MacFold, or search for MacFold in Spotlight. The laptop icon in the menu bar opens a menu with the current angle, enable/pause, settings, reconnect, and quit. The app has no Dock icon. Updating through this script closes running MacFold instances first.

1. Open **Settings** from the menu bar.
2. Choose **Allow Screen Recording…**, then allow MacFold in macOS System Settings. If macOS requests a relaunch, quit and reopen MacFold.
3. Enable **Launch at login** to start it when you sign in. The checkbox reflects macOS's actual registration status. macOS may require approval in General → Login Items.
4. Slowly lower the lid below **90°**. Blur increases toward **5°**. Reopen it to remove the overlay.

The installed app stays available after this workspace is archived. If you previously enabled launch at login from a copy inside `dist`, switch it off and on in the installed copy to update the startup location. Local ad-hoc builds may require Screen Recording permission to be refreshed after an update.

**Preview…** provides a sample desktop and an angle slider, so you can inspect the effect without moving the lid or granting Screen Recording access. The preview uses the current settings when opened or its slider is moved.

**Test Desktop…** drives the real fullscreen capture and rendering path with an angle slider. With the effect enabled and Screen Recording allowed, drag below your start angle (try 40°), then back above it. The control panel stays above the effect; **Done**, **Esc**, or closing the panel returns control to the physical sensor. Your saved thresholds remain unchanged. This makes it possible to distinguish a capture/fullscreen problem from a sensor problem. The panel and other MacFold windows are excluded from the captured image.

## Settings

| Setting | Default |
| --- | --- |
| Effect enabled | On |
| Launch at login | Off until selected |
| Begin below | 90° |
| Fully faded at | 5° |
| Blur | 24 points |
| Dimming | 85% |
| Keep picture upright | Off |
| Perspective, when folding | 65% |
| Stretch, when perspective is enabled | 85% |
| Debug information | Off |

Thresholds always stay at least 5° apart. Preferences persist across launches. Restore Defaults resets effect settings; launch-at-login registration remains controlled by its own checkbox. The last part of closing fades to black regardless of dimming strength.

Adjust the appearance using the blur, dimming, perspective, and stretch sliders. Stretch compensates for the physical lid tilt; it no longer compresses the desktop into a small trapezoid.

## Sensor probe and checks

```sh
# Continuous raw reports and converted degrees; Ctrl-C to stop
./scripts/swift.sh run lid-angle

# Bounded sensor check
./scripts/swift.sh run lid-angle --seconds 10

# Unit tests: reports, thresholds, reversals, stale captures, failures, disabling
./scripts/test.sh

# Build a standalone app, then exercise the actual GPU using a sample image
./scripts/build-app.sh
dist/MacFold.app/Contents/MacOS/MacFold --render-check .context/render-check

# Exercise repeated frames in a small, briefly visible native Metal window
dist/MacFold.app/Contents/MacOS/MacFold --window-check
```

The GPU check writes sample frames and a contact sheet, checks independent blur and perspective at 3456×2234, checks that full closure is black, and verifies identical pixels when returning to an earlier angle. These images contain only the generated sample desktop. The window check verifies the sample preview's Metal drawable lifecycle across 21 frames. The fullscreen overlay instead presents a completed Metal-rendered image through AppKit, with GPU error checking before displaying each frame. This adds a pixel readback per changed angle; physical responsiveness still needs manual verification.

Hardware discovery and actual measurements are recorded in [docs/SENSOR.md](docs/SENSOR.md). This machine returned real readings between 48° and 118°, including both closing and opening movement. Its 0–360° descriptor range uses one count per degree; it does not provide fractional-degree accuracy.

## Architecture

```text
LidSensor / HIDAngleProvider → FoldController → FoldSession → OverlayWindow
                                  ↓                            ↓
                        ScreenCaptureService              MetalRenderer
                                  ↓                            ↓
                          one desktop image         Gaussian blur + fold shader
```

- `LidSensor` is independent of AppKit and exposes `LidAngleProvider` callbacks. Invalid reports fail safely; missing devices retry every two seconds.
- `FoldCore` owns validated settings and a deterministic session state machine. Generation tokens discard screenshots that finish after reopening, disabling, sleep, or a display change.
- The click-through overlay covers only the built-in display, including full-screen Spaces. External displays remain usable. It hides and releases its textures above the start threshold, when disabled, on sleep/session deactivation, and on sensor failure.
- Switching Spaces discards the previous desktop snapshot and immediately requests a new one at the current lid or Test Desktop angle. The overlay briefly hides while the new snapshot is prepared.
- Raw whole-degree readings drive rendering directly. The validated sensor was stable while held; no extra smoothing is applied that would continue moving the image after the lid stops.
- Screen capture permission is requested only through the settings button. Without it, the app still reports the lid angle and provides the sample preview.
- Login items use Apple's [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp); desktop snapshots use [`SCScreenshotManager`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager).

## Prototype limits

The sensor report is an undocumented hardware interface, so support must be detected on each Mac. This prototype does not prevent normal lid-close sleep. Full close/wake behavior, multiple Spaces, and end-to-end perceived latency need physical testing on the target setup. A snapshot freezes desktop content during the effect, so a video or clock underneath will jump back to its live state when reopening.

The default build is signed ad hoc for local use, with App Sandbox disabled for HID access. It is not notarized for distribution. For a distributable build, set `SIGNING_IDENTITY` to an installed Developer ID identity and complete Apple's notarization process. Builds use the host architecture.

To build a versioned release ZIP and SHA-256 checksum in `dist/`, run `./scripts/release.sh`. The version comes from `Resources/Info.plist`; the architecture comes from the built executable. Run `./scripts/test.sh` before publishing, and disclose signing/notarization status in the release notes. Release binaries are attached to GitHub Releases rather than committed to Git.

The scripts prefer Command Line Tools without changing global `xcode-select`. If its Swift Package Manager cannot launch, they fall back to Xcode's standalone Swift toolchain while retaining the Command Line Tools SDK. They follow the selected `MacOSX.sdk` symlink rather than automatically choosing a leftover newer beta SDK, and use the matching toolchain's Swift Testing framework. Set `DEVELOPER_DIR` or `SDKROOT` to override developer tools or SDK selection.
