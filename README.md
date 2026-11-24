# GPX Lab

Offline mobile workbench for inspecting, combining, editing, and exporting fitness activity files (`GPX`, `TCX`, and `FIT`) before uploading them to platforms like Strava.

## Highlights

- **100% Offline & Private**: Parses, blends, stitches, and exports **Source Files** locally on-device with zero backend or account setup.
- **Channel Blending & Sequential Stitching**: Align overlapping sensor **Channels** onto a **Base Timeline** or concatenate back-to-back parts into a single continuous **Activity**.
- **Strava Tax Diagnostics & Distance Override**: Detect downward distance discrepancies and proportionally scale cumulative distance before exporting.
- **Privacy & Channel Stripping**: Selectively strip GPS position, heart rate, cadence, power, elevation, or device info with lossy-export safety rails.

## Development

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```
