/// Per-container music mode settings: whether it is on, and which folders it
/// indexes.
///
/// An empty [folders] list means the whole container. Folders are
/// container-relative paths without leading or trailing slashes, the same form
/// the file manager uses ("Music", "Media/Audiobooks"; "" is the root and is
/// represented by an empty list, never by an empty entry).
class MusicConfig {
  final bool enabled;
  final List<String> folders;

  const MusicConfig({this.enabled = false, this.folders = const []});

  static const MusicConfig off = MusicConfig();

  bool get wholeContainer => folders.isEmpty;

  /// The folders a scan starts from: the chosen ones, or the root.
  List<String> get scanRoots => folders.isEmpty ? const [''] : folders;

  MusicConfig copyWith({bool? enabled, List<String>? folders}) => MusicConfig(
        enabled: enabled ?? this.enabled,
        folders: folders == null ? this.folders : normalizeFolders(folders),
      );

  /// Cleans a folder list: slashes trimmed, blank entries dropped (names keep
  /// their own inner and edge spaces), duplicates
  /// collapsed, and any folder inside another selected one removed (scanning
  /// the parent already covers it, and scanning both would walk it twice).
  static List<String> normalizeFolders(Iterable<String> input) {
    final cleaned = <String>{};
    for (final raw in input) {
      final f = raw.replaceAll('\\', '/').split('/').where((s) => s.trim().isNotEmpty).join('/');
      if (f.isNotEmpty) cleaned.add(f);
    }
    final sorted = cleaned.toList()..sort();
    final out = <String>[];
    for (final f in sorted) {
      final covered = out.any((parent) => f == parent || f.startsWith('$parent/'));
      if (!covered) out.add(f);
    }
    return List.unmodifiable(out);
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        'enabled': enabled,
        'folders': folders,
      };

  /// Throws [FormatException] when [json] is not a config object.
  factory MusicConfig.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('music config is not an object');
    final enabled = json['enabled'];
    final folders = json['folders'];
    if (enabled is! bool) throw const FormatException('bad "enabled"');
    if (folders is! List || folders.any((e) => e is! String)) {
      throw const FormatException('bad "folders"');
    }
    return MusicConfig(
      enabled: enabled,
      folders: normalizeFolders(folders.cast<String>()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MusicConfig &&
      other.enabled == enabled &&
      _listEquals(other.folders, folders);

  @override
  int get hashCode => Object.hash(enabled, Object.hashAll(folders));

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
