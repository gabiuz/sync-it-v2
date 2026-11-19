/// Shared display formatters for Activity metrics in the UI layer.
String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// Formats pace in seconds per kilometer as `M:SS /km`.
String formatPace(double secondsPerKm) {
  final totalSeconds = secondsPerKm.round();
  final mins = totalSeconds ~/ 60;
  final secs = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$mins:$secs /km';
}
