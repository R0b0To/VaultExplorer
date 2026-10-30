import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';

/// What a directory viewport tells the tiles and gesture containers inside it.
///
/// - [interactionLocked]: another viewport started a drag, so this one only
///   acts as a drop target (tiles ignore taps/holds, selection is frozen).
/// - [revealNames]/[revealToken]: names of items a drop just placed in this
///   viewport's folder; tiles with those names flash while it is non-empty.
class BrowserPaneScope extends InheritedWidget {
  final TabId tabId;
  final bool interactionLocked;
  final Set<String> revealNames;
  final int revealToken;

  const BrowserPaneScope({
    super.key,
    required this.tabId,
    required this.interactionLocked,
    required this.revealNames,
    required this.revealToken,
    required super.child,
  });

  /// Registers a dependency: the caller rebuilds when the scope changes.
  static BrowserPaneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BrowserPaneScope>();

  /// Reads the current scope without subscribing, for gesture callbacks.
  static BrowserPaneScope? peek(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BrowserPaneScope>();

  @override
  bool updateShouldNotify(BrowserPaneScope oldWidget) =>
      tabId != oldWidget.tabId ||
      interactionLocked != oldWidget.interactionLocked ||
      revealToken != oldWidget.revealToken ||
      !setEquals(revealNames, oldWidget.revealNames);
}
