# Lid sensor validation

Probe command:

```sh
./scripts/swift.sh run lid-angle --seconds 10
```

Omit `--seconds` to keep printing while moving the lid. The probe requires neither screen capture permission nor root. It matches only the Apple orientation sensor, so it does not open keyboard or mouse devices.

## Discovered hardware

On the development machine (Mac15,13, macOS 26.6.2), the I/O Registry exposes:

| Property | Value |
| --- | --- |
| Registry class | AppleSPUHIDDevice |
| Vendor | `0x05AC` (1452, Apple) |
| Product | `0x8104` (33028) |
| Usage page | `0x0020` (Sensors) |
| Primary usage | `0x008A` (Orientation) |
| Angle element | `0x047F` |
| Report ID | `1` |
| Report size | 9 bits |
| Logical range | 0–360 |
| Physical range | 0–360 |

The descriptor places report ID 1 first, followed by an unsigned angle. The two payload bytes are interpreted little-endian: `report[1] | report[2] << 8`. Equal logical and physical ranges imply **one count per degree**, with integer-degree resolution. Printing a decimal digit does not imply sub-degree precision.

The report is requested using `IOHIDDeviceGetReport(..., kIOHIDReportTypeFeature, 1, ...)`, as demonstrated by the [sensor project's implementation](https://github.com/samhenrigold/LidAngleSensor/blob/main/LidAngleSensor/LidAngleSensor.swift), although its descriptor labels the element as input. This behavior is hardware-specific and undocumented by Apple; the app reports failure instead of inventing an angle when the sensor is unavailable.

The reader rejects short reports, wrong report IDs, and values above 360. The supported data range is not the mechanically achievable hinge range. Polling at 60 Hz does not establish that the hardware itself updates at 60 Hz.

## Observed results (September 10, 2026)

- Initial three-second probe: 181 successful samples, 60.0 polls/s, 118° (`01 76 00`).
- Three-minute stationary probe: 10,801 successful samples, 60.0 polls/s, stable 118° throughout.
- Ten-second physical movement probe: 592 samples, 59.2 polls/s, 48–103°. The trace includes 19 decreasing steps and 10 increasing steps, confirming readings in both directions.
- No fabricated or simulated readings were used for these measurements. Full close / sleep / wake and perceived end-to-end latency still need a separate physical check.

## Physical verification

Lower the lid gradually and reopen it. Check that readings decrease on closing, remain stable when held, and increase on reopening. Do not force the hinge to the descriptor's 360° maximum. Full close / sleep / wake and perceived latency require physical testing.

## Toolchain

The selected Xcode installation failed to load `libxcodebuildLoader.dylib` because of a CoreDevice/Mercury symbol mismatch. `scripts/swift.sh` selects the separately installed Command Line Tools for its own process. It does not modify the global `xcode-select` setting.
