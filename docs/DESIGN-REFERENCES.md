# Duo-inspired closing effect

References reviewed September 10, 2026:

- [Apple's iPhone Duo announcement](https://images.apple.com/ca/newsroom/2026/09/apple-unveils-iphone-duo/) establishes the folding-device reference. This implementation is an interpretation for a single MacBook display, not Apple's implementation.
- [Bendy](https://trybendy.app/) demonstrates a Mac desktop that appears to hold its place as the lid moves, with adjustable perspective, frost, and shading.
- [macTilt](https://github.com/lqSky7/iphone-duo-macos-animation) publishes a native Mac implementation and shader. Its spatial projection and progressive frost were reviewed as references. No source files were imported into MacFold.

The previous MacFold shader compressed the desktop into a hard-edged trapezoid, exposing a large black area above it. The revised shader samples a bottom-anchored perspective compensation: content stretches along the panel as it tilts, instead of shrinking down it. The projection stays bounded. Side edges soften, frost increases with distance from the keyboard, and shading favors the far edge. Full black is reserved for the final closing interval.

Three Gaussian levels are generated from the original snapshot and reused while the angle changes. The fragment shader blends neighboring blur levels per pixel, producing a spatially varying frost. Angle uses a smoothstep mapping; no timer-based easing continues after the lid stops. The working Metal-to-AppKit image presentation remains unchanged.

The optional `--duo-look` launch preset sets blur to 36 points, dimming to 35%, perspective to 40%, and stretch to 78%, with perspective enabled. It preserves start/end thresholds, enabled state, and debug preference. Installation with `./scripts/install.sh --duo-look` applies it once at launch; ordinary subsequent launches retain the user's settings. There is no preset button in Settings; the sliders control the appearance.

Validation: twelve logic tests, optimized build, and offscreen Retina GPU checks. The user handles all physical-lid and fullscreen visual testing; Computer Use is not used.
