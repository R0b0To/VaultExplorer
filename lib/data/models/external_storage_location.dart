class ExternalStorageLocation {
  final String id;
  final String path;
  final String? treeUri;
  final String displayName;
  final int volId;

  const ExternalStorageLocation({
    required this.id,
    required this.path,
    this.treeUri,
    required this.displayName,
    required this.volId,
  });

  ExternalStorageLocation copyWith({
    String? id,
    String? path,
    String? treeUri,
    String? displayName,
    int? volId,
  }) {
    return ExternalStorageLocation(
      id: id ?? this.id,
      path: path ?? this.path,
      treeUri: treeUri ?? this.treeUri,
      displayName: displayName ?? this.displayName,
      volId: volId ?? this.volId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    if (treeUri != null) 'treeUri': treeUri,
    'displayName': displayName,
    'volId': volId,
  };

  factory ExternalStorageLocation.fromJson(Map<String, dynamic> json) {
    return ExternalStorageLocation(
      id: json['id'] as String,
      path: json['path'] as String,
      treeUri: json['treeUri'] as String?,
      displayName: json['displayName'] as String? ?? '',
      volId: json['volId'] as int,
    );
  }

  /// The URI that should actually be used to open/list this location.
  ///
  /// Always prefers [treeUri] when one is present: it's a SAF tree URI
  /// backed by a persisted `takePersistableUriPermission` grant (see
  /// `VaultPickerHandlers.pickExtractFolderLauncher`), so it works
  /// regardless of whether `MANAGE_EXTERNAL_STORAGE` ("All files access")
  /// is granted. [path] -- a best-effort raw filesystem path -- is only
  /// used as a fallback when no tree URI could be resolved at pick time.
  ///
  /// Do NOT reintroduce a `path.startsWith('/storage/emulated/0')`-style
  /// "is this internal storage" check here: under scoped storage (API 30+)
  /// that prefix covers the entire shared-storage volume, not just
  /// app-private space, so raw [path] access to it still requires "All
  /// files access" and silently fails to list anything without it.
  String get resolvedUri => (treeUri != null && treeUri!.isNotEmpty) ? treeUri! : path;
}