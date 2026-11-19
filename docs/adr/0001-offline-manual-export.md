# Offline-Only Manual File Export (No Strava API Integration)

Sync-It exports edited GPX, TCX, and FIT files locally for manual upload rather than integrating with the Strava Uploads API. This keeps the app 100% offline with zero backend, OAuth setup, API policy risk, or platform lock-in, and works with any destination platform.

## Consequences

- Strava's manual web uploader ignores activity titles in TCX and FIT files, so the export flow must include a one-tap copy helper for title and description alongside the exported file.
- The editing and export core stays decoupled from delivery so an optional API uploader could be added in a future version without redesigning the editor.
