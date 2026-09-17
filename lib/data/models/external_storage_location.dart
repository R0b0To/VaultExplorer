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
}