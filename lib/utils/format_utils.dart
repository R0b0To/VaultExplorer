/// Formats a byte count into a human-readable string (e.g. "4.2 MB", "1 GB").
/// Shared across ContainerCard, FileBrowserScreen's _StatsBar, and any other
/// widget that previously carried its own copy of this logic.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  int idx = 0;
  while (size >= 1024 && idx < suffixes.length - 1) {
    size /= 1024;
    idx++;
  }
  return '${size.toStringAsFixed((size < 10 && idx > 0) ? 1 : 0)} ${suffixes[idx]}';
}

// ── Entry date formatting ────────────────────────────────────────────────────

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats a FAT/exFAT entry's modified-time (Unix seconds; 0 = unknown per
/// [RawEntry.modifiedSecs]'s own doc comment) into a short display string for
/// list rows: "14:32" for today, "Jan 5" for this year, "Jan 5, 2024"
/// otherwise. Returns "—" when unknown.
String formatEntryDate(int secs) {
  if (secs <= 0) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  final now = DateTime.now();

  final isToday =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;

  if (isToday) {
    final hr = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hr:$min';
  }

  final monthAbbr = _months[dt.month - 1];
  return dt.year == now.year
      ? '$monthAbbr ${dt.day}'
      : '$monthAbbr ${dt.day}, ${dt.year}';
}