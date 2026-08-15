// Shared formatting helpers used across dialogs and tabs.

/// Human-readable, compact duration such as `30s`, `5m 3s` or `2h 5m`.
///
/// Negative durations render as `0s`. Seconds are omitted once hours are
/// present. Used for recording lengths and satellite pass timing.
String formatDurationCompact(Duration d) {
  if (d.isNegative) return '0s';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// Clock-style duration such as `05:03` or `1:05:03`.
///
/// Hours are only shown once the duration reaches one hour. Used for
/// playback position/length displays.
String formatDurationClock(Duration d) {
  final totalSeconds = d.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours >= 1 ? '$hours:$mm:$ss' : '$mm:$ss';
}
