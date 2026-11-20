/// The decisions behind the metadata dialogs, free of widgets so they can be
/// tested.
library;

/// The keywords a file ends up with: [existing] plus [add], minus [remove],
/// compared without regard to case. Keeps the file's own order and spelling
/// for what stays, and adds new ones at the end.
List<String> mergeKeywords(
  List<String> existing,
  Iterable<String> add,
  Iterable<String> remove,
) {
  final removed = {for (final r in remove) r.trim().toLowerCase()};
  final seen = <String>{};
  final out = <String>[];
  for (final k in [...existing, ...add]) {
    final t = k.trim();
    if (t.isEmpty) continue;
    final key = t.toLowerCase();
    if (removed.contains(key) || !seen.add(key)) continue;
    out.add(t);
  }
  return out;
}

/// A wall-clock moment (year to second, no zone) from the digits [d].
DateTime? _valid(int y, int mo, int d, [int h = 0, int mi = 0, int s = 0]) {
  if (y < 1970 || y > 2100) return null;
  final t = DateTime.utc(y, mo, d, h, mi, s);
  if (t.year != y || t.month != mo || t.day != d || t.hour != h) return null;
  return t;
}

final RegExp _stampWithTime = RegExp(
  r'(?<!\d)((?:19|20)\d{2})[-_.:]?(0[1-9]|1[0-2])[-_.:]?(0[1-9]|[12]\d|3[01])'
  r'[-_ T.]?([01]\d|2[0-3])[-_.:]?([0-5]\d)[-_.:]?([0-5]\d)',
);
final RegExp _stampDateOnly = RegExp(
  r'(?<!\d)((?:19|20)\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])(?!\d)',
);

/// The date and time a camera or messaging app put in a file's [name]
/// (`IMG_20230714_183205.jpg`, `2023-07-14 18.32.05.png`,
/// `PXL_20230714_183205123.jpg`), as a wall-clock moment; a name with only a
/// date gives midnight. Null when the name holds no plausible date.
DateTime? dateFromFileName(String name) {
  final base = name.contains('/') ? name.substring(name.lastIndexOf('/') + 1) : name;
  final withTime = _stampWithTime.firstMatch(base);
  if (withTime != null) {
    final v = _valid(
      int.parse(withTime[1]!),
      int.parse(withTime[2]!),
      int.parse(withTime[3]!),
      int.parse(withTime[4]!),
      int.parse(withTime[5]!),
      int.parse(withTime[6]!),
    );
    if (v != null) return v;
  }
  final dateOnly = _stampDateOnly.firstMatch(base);
  if (dateOnly != null) {
    return _valid(
      int.parse(dateOnly[1]!),
      int.parse(dateOnly[2]!),
      int.parse(dateOnly[3]!),
    );
  }
  return null;
}

/// [secs] (seconds since the epoch) as the wall clock of the device's own
/// zone, in the form the gallery keeps dates (components read as UTC).
DateTime wallClockOfEpochSecs(int secs) {
  final l = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  return DateTime.utc(l.year, l.month, l.day, l.hour, l.minute, l.second);
}

/// The inverse of [wallClockOfEpochSecs]: the epoch second at which the
/// device's clock showed [wall].
int epochSecsOfWallClock(DateTime wall) =>
    DateTime(wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second)
        .millisecondsSinceEpoch ~/
    1000;

/// [wall] moved by [delta] without any zone or daylight-saving change.
DateTime shiftWallClock(DateTime wall, Duration delta) {
  final t = DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  ).add(delta);
  return t;
}
