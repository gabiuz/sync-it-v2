# Canonical Activity Model with Clean Re-Serialization

GPX Lab parses every imported GPX, TCX, FIT, and KML file into a single format-independent `Activity` model and serializes fresh output files on export, rather than patching original XML DOMs or binary FIT streams in place. This makes cross-format conversion, channel blending, sequential stitching, and channel stripping uniform and predictable across all four formats.

## Considered Options

- **Format-specific in-place patching**: Preserves proprietary vendor extensions (e.g., Garmin Running Dynamics or custom developer fields), but makes cross-format blending, stitching, and conversion brittle and duplicates transformation logic per format.

## Consequences

- Unrecognized vendor-proprietary extensions outside the standard supported channels are dropped on export; the UI surfaces an informational notice when an imported file contains ignored extensions.
