# Prototype validation — September 10, 2026

## Passed

- Swift debug and optimized release builds on macOS 26.6.2 / Mac15,13, using Swift 6.3.3 Command Line Tools.
- Nine Swift Testing tests covering HID decoding, invalid reports/settings, normalized angles, stationary/reversed input, failed capture retries, and invalidation after reopen/disable/sleep.
- Real sensor: 10,801 samples over 180 seconds at 60.0 polls/s with a stationary lid. A later 10-second trace covered 48–103° in both directions at 59.2 polls/s.
- Real Metal and MPS rendering: eight frames at 90°, 60°, 30°, and 5°, in blur and folding modes. Verified a black closed frame and byte-identical output when returning to a previous angle.
- Visually inspected the GPU contact sheet: upright image, progressive blur/dimming, and perspective anchored at the bottom.
- Native settings UI inspected with accessibility and screenshots. Live angle, defaults, enabled/disabled folding controls, preview, and permission state are present and readable.
- Native preview moved from 102° to 35° and visibly blurred/dimmed the sample image.
- Launch-at-login registration enabled through the checkbox, and still reported enabled after restarting the release app.
- Verified an unshown Metal window can acquire its first drawable, which the overlay needs before becoming visible.
- Release app passed strict code-signature verification and reran the GPU checks using its own shader resource. The `.app` resource path deliberately never falls back to `.build`.
- Shell syntax, Info.plist validation, and whitespace checks passed.

## Remaining physical / OS checks

- The release app launched through Finder/LaunchServices still needs its own Screen Recording permission. Terminal-launched development processes can inherit the terminal's capture access; that is not evidence that the installed app has permission.
- After granting access, verify real desktop capture and full-screen blur while closing, holding, and reopening the lid.
- Verify full close → sleep → wake, another full-screen Space, and an external display on the intended setup.
- Measure actual capture latency and perceived responsiveness while moving the lid. Polling rate alone does not establish end-to-end latency.
- Sign out and back in to verify actual login launch. Registration status was checked without signing the user out.

The app currently resides in `dist/MacFold.app`. For long-term startup use, move it to a stable application folder, then re-enable launch at login from that copy.

## Follow-up: missing real-screen effect and app installation

The user reported that closing the lid showed no effect after granting permission. Relaunching the unchanged binary confirmed valid sensor readings and active permission. Raising the start angle triggered capture, but macOS logs reported both failed drawable allocation and an attempt to present a drawable more than once.

The renderer had accessed `MTKView.currentDrawable` directly without going through the view's drawing cycle. [Apple documents that the view replaces its cached drawable only after its drawing callback returns](https://developer.apple.com/documentation/metalkit/mtkview/currentdrawable). This also explains why the earlier offscreen image tests passed without detecting the real window failure.

Changes and verification:

- Rendering now calls `MTKView.draw()` and encodes the frame in `MTKViewDelegate.draw(in:)`, releasing each frame correctly.
- Added a native window regression check that starts with a zero-sized window, resizes it, presents successive angles, hides it, and repeats. Both debug and release builds passed all 21 frames with fresh drawable IDs.
- The release build also passed the eight-frame GPU image check and exact reversal check again.
- Ten logic tests now pass, including recovering from a rendering failure after reopening.
- The controller retries a transient missing frame and shows an error after repeated failure, instead of silently reporting a working effect.
- Installed the app at `/Applications/MacFold.app`. Launch at login was switched off and on from that installed copy.
- Finder/Spotlight launches now open Settings every time; automatic login launches remain quiet. `scripts/run.sh` now installs the app before opening it.
- Preserved the user's effect settings: 66° start, 2° end, blur 30 points, folding enabled.

The updated local ad-hoc signature requires refreshing the existing Screen Recording grant. macOS requested Touch ID while refreshing that grant. The real desktop / physical lid test remains pending that OS approval; no full close/sleep/wake claim is made.

## Follow-up: user reports dimming without blur or perspective

The installed app subsequently reported Screen Recording access granted. With the user's settings (88° start, 2° end, 30-point blur, folding enabled), the sample preview visibly showed Gaussian blur and perspective at 40°. The actual fullscreen overlay could not be visually verified: its screenshot was blank while `sharingType` was `.none`. That does not establish what appeared on the physical screen. The user requested that further visual tests be performed manually, so UI automation was stopped.

Changes prepared for manual verification:

- The overlay now orders its window in at zero opacity before acquiring its first drawable and reveals it after frame submission. The debug label is a sibling of the Metal view rather than a subview of it.
- Removed the screenshot-sharing restriction so the user can capture the fullscreen result for debugging. ScreenCaptureKit still explicitly excludes MacFold windows to prevent feedback.
- Added **Test Desktop…**, which sends slider angles through the actual controller, capture service, session, and fullscreen overlay. It preserves saved thresholds and restores sensor control on Done/Escape/close.
- Restored the user's 88°/2° thresholds after the earlier temporary live test; retained all other effect preferences.

The fullscreen changes require the user's manual test. A successful sample preview or build alone is not evidence that the physical lid effect is fixed.

Verification after these changes: debug and release builds passed, all ten logic tests passed, shell syntax checks passed, and the signed release was installed at `/Applications/MacFold.app`. No further Computer Use or automated window test was performed after the user's request.

## Follow-up: immediate dark screen at the start threshold

The user reported the same problem in Test Desktop and clarified that crossing the start threshold looks like full closure. Saved settings at this point were 57° start / 0° end. A new regression test verifies that crossing to 56° stays in `folding` at about 1.75%, then advances through 25%, 50%, 75%, and only enters `closed` at 0°. All eleven logic tests pass. This confirms the isolated progress/session calculation; it does not prove live presentation.

Replaced the fullscreen MTKView presentation with AppKit displaying a completed offscreen Metal image. GPU errors now propagate to the visible status instead of submission alone counting as success. The output texture is reused between frames. The sample preview still uses MTKView. Status now includes effect percentage to distinguish an actual progress jump from incorrect output.

Release GPU checks passed independent blur and perspective at 3456×2234 with dimming disabled, plus the existing eight sample frames, black closure, and exact reverse-angle reproduction. The fullscreen replacement incurs a pixel readback per changed angle. No Computer Use testing was performed; the user must verify fullscreen appearance and responsiveness.

## Top darkness and edge feathering

Following the user's screenshot feedback, the shader now masks the uncovered perspective area to solid black rather than blending residual clamped desktop colors into it. A dark horizon descends with the projection, with a broad inward top feather, softer sides toward the upper corners, and a narrow bottom feather. The fully open frame bypasses the mask.

An offscreen white-source GPU regression verifies a black top and outer side, increasing brightness across the top feather, an unaffected interior, and an unchanged open endpoint. Retina rendering, full-black closure, and exact reversal checks also pass. Inspected the generated sample frame only; no Computer Use or physical-lid testing was performed.

## Organic focus and corner transitions

Reviewed all six user-provided reference images. Replaced the multiplied rectangular edge masks with a single rounded extinction field, a gently bowed top boundary, and broader side/top feathers. Feathering starts earlier than the perspective displacement, so early motion does not reveal a sharp rectangular frame. The rational stretch varies with distance from the hinge; frost builds earlier and is strongest in the upper corners, with smooth interpolation between Gaussian levels. No temporal noise or animation was added.

The white-source GPU regression additionally checks rounded symmetric corner attenuation and a broad partial-brightness band at 10% progress. Existing open/closed endpoints, black exterior, Retina rendering, and exact reversal remain covered. Visual review uses generated sample images only; the user continues physical testing.

## Smooth entry at the lid threshold

The fullscreen window previously appeared at full opacity on the first nonzero progress value, immediately exposing the snapshot and its dark edge mask. The overlay now blends in using a smoothstep opacity curve over the first 10% of normalized lid travel and reverses the same curve on opening. The image is marked for display before the window is revealed. This adds no timer-based animation and preserves the established appearance after the entry interval.

Thirteen logic tests pass, including low opacity on the first degree below representative thresholds, monotonic entry, and symmetric reversal. The optimized app build passes. Physical entry smoothness remains for user testing; no Computer Use was performed.
