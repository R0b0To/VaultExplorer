import '../models/mounted_container.dart';

/// A singleton that holds clipboard items that can survive navigation back
/// to the dashboard and into a different container.
class CrossContainerClipboard {
  CrossContainerClipboard._();
  static final instance = CrossContainerClipboard._();

  MountedContainer? sourceContainer;
  bool isCutOperation = false;
  List<Map<String, dynamic>> items = []; // {'path': String, 'isDir': bool}

  bool get hasItems => items.isNotEmpty;

  /// Returns true if the clipboard belongs to [container].
  bool isFromContainer(MountedContainer container) =>
      sourceContainer?.volId == container.volId;

  void set({
    required MountedContainer container,
    required bool cut,
    required List<Map<String, dynamic>> clipItems,
  }) {
    sourceContainer = container;
    isCutOperation = cut;
    items = List.from(clipItems);
  }

  void clear() {
    sourceContainer = null;
    isCutOperation = false;
    items = [];
  }

  /// Human-readable summary label for any UI that needs it.
  String get summary {
    if (!hasItems) return '';
    final verb = isCutOperation ? 'Moving' : 'Copying';
    final from = sourceContainer?.displayName ?? '?';
    return '$verb ${items.length} item(s) from "$from"';
  }
}