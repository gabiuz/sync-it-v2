# Sync-It

A mobile workbench for inspecting, combining, editing, and exporting fitness activity files before uploading them to platforms like Strava.

## Language

**Source File**:
An imported GPX, TCX, or FIT file exported from a watch or wellness app as input to an editing session.
_Avoid_: Raw file, track file, upload

**Export File**:
The generated GPX, TCX, or FIT file produced from an edited activity for manual upload to a target platform.
_Avoid_: Output file, download

**Activity**:
The format-independent representation of a single workout built from one or more source files for inspection, editing, and export.
_Avoid_: Workout, session, recording

**Trackpoint**:
A single timestamped sample along an activity's timeline carrying optional values for each channel.
_Avoid_: Record, waypoint, data point

**Lap**:
A contiguous time-bounded interval within an activity—such as an auto-split or stitch boundary—with its own summary metrics.
_Avoid_: Split, segment

**Channel**:
A single telemetry series within an activity—such as GPS position, elevation, cumulative distance, heart rate, cadence, or power—that can be kept, stripped, or selected independently.
_Avoid_: Stream, series, sensor track

**Base Timeline**:
The source file whose trackpoint timestamps serve as the master clock when aligning secondary channels during channel blending.
_Avoid_: Master file, primary file

**Channel Blending**:
Combining two or more source files recorded during the same workout by aligning them in time and choosing which source supplies each channel.
_Avoid_: Merge (unqualified)

**Sequential Stitching**:
Concatenating two or more back-to-back source files into one continuous activity.
_Avoid_: Merge (unqualified), join, append

**Strava Tax**:
The downward distance discrepancy that occurs when a target platform recalculates distance from raw GPS points or truncates fractional distance downward rather than honoring the source device's recorded total.
_Avoid_: Distance bug, GPS drift

**Distance Override**:
A user-specified target total distance that proportionally scales an activity's cumulative distance channel across its timeline.
_Avoid_: Distance hack, fake distance
