import 'package:flutter/foundation.dart';

/// A singleton that holds clipboard items that can survive navigation back
/// to the dashboard and into a different container.
///
/// FIX: Now extends [ChangeNotifier] so widgets that display clipboard state
/// (VaultDashboard's status strip, FileBrowserScreen's app bar) receive
/// automatic rebuild notifications when the clipboard changes, eliminating
/// stale UI state after clear() or set() calls.
///
/// Usage:
///   ListenableBuilder(
///     listenable: CrossContainerClipboard.instance,
///     builder: (context, _) { ... },
///   )
class CrossContainerClipboard extends ChangeNotifier {
  CrossContainerClipboard._();
  static final instance = CrossContainerClipboard._();

  // FIX: Store only minimal identity (volId + displayName) rather than the
  // full MountedContainer object, preventing a strong reference that would
  // keep the container alive in memory after it is locked.
  int? sourceVolId;
  String? sourceDisplayName;

  bool isCutOperation = false;

  /// Each entry: {'path': String, 'isDir': bool, 'size': int?}
  List<Map<String, dynamic>> items = [];

  bool get hasItems => items.isNotEmpty;

  /// Returns true if the clipboard was populated from [volId].
  bool isFromVolume(int volId) => sourceVolId == volId;

  /// Sets the clipboard contents and notifies all listeners.
  void set({
    required int volId,
    required String displayName,
    required bool cut,
    required List<Map<String, dynamic>> clipItems,
  }) {
    sourceVolId       = volId;
    sourceDisplayName = displayName;
    isCutOperation    = cut;
    items             = List.from(clipItems);
    notifyListeners(); // FIX: widgets rebuild immediately
  }

  /// Clears the clipboard and notifies all listeners.
  void clear() {
    sourceVolId       = null;
    sourceDisplayName = null;
    isCutOperation    = false;
    items             = [];
    notifyListeners(); // FIX: widgets rebuild immediately
  }

  /// Human-readable summary label for any UI that needs it.
  String get summary {
    if (!hasItems) return '';
    final verb = isCutOperation ? 'Moving' : 'Copying';
    final from = sourceDisplayName ?? '?';
    return '$verb ${items.length} item(s) from "$from"';
  }
}