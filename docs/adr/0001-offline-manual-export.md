# Offline-Only Manual File Export (No Strava API Integration)

GPX Lab exports edited GPX, TCX, FIT, and KML files locally for manual upload or sharing rather than integrating with the Strava Uploads API. This keeps the app 100% offline with zero backend, OAuth setup, API policy risk, or platform lock-in, and works with any destination platform.

## Consequences

- Strava's manual web uploader ignores activity titles in TCX and FIT files and does not accept KML files, so the export flow includes a one-tap copy helper for title and description on FIT, TCX, and GPX exports and surfaces Strava-compatibility warnings when exporting KML.
- The editing and export core stays decoupled from delivery so an optional API uploader could be added in a future version without redesigning the editor.
