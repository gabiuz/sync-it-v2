# Flutter (Dart) for Cross-Platform Mobile

We are building Sync-It with Flutter (Dart) to target both Android and iOS from a single codebase. Flutter avoids JS-bridge serialization overhead when parsing, blending, charting, and encoding multi-thousand-trackpoint XML and binary FIT files, and provides pure-Dart binary FIT read/write library support.

## Considered Options

- **React Native (Expo / TypeScript)**: Strong UI ecosystem, but Garmin's official JS FIT SDK is decoder-only and heavy binary/XML trackpoint processing adds bridge or native-module complexity.
- **Native Android (Kotlin) only**: Rejected because iOS support is desired in v1.
