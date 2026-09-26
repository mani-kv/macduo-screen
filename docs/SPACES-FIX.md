# Follow-up: effect only appears on the first desktop

The user reports the same failure in Test Desktop on Desktop 2 and 3 with no external monitor attached. This narrows the issue to the shared desktop capture/presentation path, rather than the physical lid sensor alone.

The installed app identifies itself as 0.1.1, but inspection of its executable confirms that both the overlay and Test Desktop already set `canJoinAllApplications` alongside `canJoinAllSpaces`. Merely installing the existing 0.1.2 source is therefore not a new fix.

The remaining window-policy mismatch is that the effect uses an ordinary `NSWindow`, and Test Desktop uses an activating panel. [Apple's guidance for overlays across Spaces](https://developer.apple.com/forums/thread/826308) specifies an accessory app with a nonactivating `NSPanel`, all-Spaces and all-apps collection behavior, and a screen-saver window level. MacFold already had the other pieces.

The effect now uses a nonactivating floating panel that cannot become key or main. Test Desktop also uses a nonactivating floating panel so interacting with it need not activate the app's Settings Space. The effect checks `isOnActiveSpace` as well as `isVisible` before deciding whether to order its window forward. Existing snapshot refresh and stale-capture cancellation remain in place. Spaces support is automatic; no setting is required.

Validation: all 14 tests passed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test.sh`. Restoring the old NSWindow type and style caused the new regression test to fail on three expectations (panel type, nonactivating style, floating behavior); restoring the fix passed the entire suite again. The Command Line Tools initially failed to load Swift Testing macros during an incremental test build; the Xcode-selected run passed. `git diff --check` also passed.

The regression test checks the production overlay panel's native window policy without showing an overlay or switching the user's desktops. It cannot establish that WindowServer presents the effect correctly on every Space.

Packaging check: the current Swift Build toolchain emits a resource bundle with `Contents/Resources/FoldShader.metal`, whereas the older installed build used a flat bundle. The packaged renderer previously hard-coded the flat path. Resource lookup now uses `Bundle.url(forResource:withExtension:)` with a flat-layout fallback, still confined to the installed app. The first install also retained a stale shader file from the old layout and failed signature verification; replacing the app with a clean copy resolved the stale resource. The installer now mirrors the bundle with `rsync --delete` so obsolete files are removed on upgrades. The previous installed app was backed up under `.context/` before replacement.

The optimized app was installed and relaunched at `/Applications/MacFold.app`. Strict signature verification passed, its executable matches the release build, and saved effect preferences are byte-for-byte unchanged. The installed app passed the offscreen darkness-mask, Retina blur/fold, eight-frame, fully closed, and exact angle-reversal checks. These checks verify the packaged shader loader and rendering, not visual behavior across Spaces.

User confirmation — September 26, 2026: after installing this build and retrying Test Desktop across desktop Spaces, the user confirmed, “Yes, it works across desktops now.” This verifies the reported multi-desktop failure is resolved on the affected Mac with no external monitor attached.

Additional coverage remains for another app's full-screen Space, rapid Space changes while reopening, and physical full close/sleep/wake. These scenarios were not part of the user's confirmation.
