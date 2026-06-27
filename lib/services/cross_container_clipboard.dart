/// A singleton that holds clipboard items that can survive navigation back
/// to the dashboard and into a different container.
///
/// FIX: Stores only [sourceVolId] and [sourceDisplayName] instead of the
///      full [MountedContainer] object, preventing a strong reference that
///      would keep the container alive in memory after it is locked.
class CrossContainerClipboard {
  CrossContainerClipboard._();
  static final instance = CrossContainerClipboard._();

  // FIX: Do NOT hold MountedContainer — store minimal identity only.
  int? sourceVolId;
  String? sourceDisplayName;

  bool isCutOperation = false;
  List<Map<String, dynamic>> items = []; // {'path': String, 'isDir': bool, 'size': int?}

  bool get hasItems => items.isNotEmpty;

  /// Returns true if the clipboard was populated from [volId].
  bool isFromVolume(int volId) => sourceVolId == volId;

  void set({
    required int volId,
    required String displayName,
    required bool cut,
    required List<Map<String, dynamic>> clipItems,
  }) {
    sourceVolId         = volId;
    sourceDisplayName   = displayName;
    isCutOperation      = cut;
    items               = List.from(clipItems);
  }

  void clear() {
    sourceVolId         = null;
    sourceDisplayName   = null;
    isCutOperation      = false;
    items               = [];
  }

  /// Human-readable summary label for any UI that needs it.
  String get summary {
    if (!hasItems) return '';
    final verb = isCutOperation ? 'Moving' : 'Copying';
    final from = sourceDisplayName ?? '?';
    return '$verb ${items.length} item(s) from "$from"';
  }
}