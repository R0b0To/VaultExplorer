import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Keeps the Linux accessibility tree out of a window.
///
/// On Linux the engine runs one accessibility bridge per view, and with the
/// app's multi-window setup it rejects semantics updates over and over:
///
///     [ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)]
///     Failed to update ui::AXTree, error: Nodes left pending by the update
///
/// Every rejected update is logged and the next one re-sends the whole tree,
/// which keeps the platform thread busy: navigation and input stall, then the
/// queued inputs fire all at once. Excluding the semantics of the window's
/// content means the framework has nothing to send, so nothing can be
/// rejected.
///
/// The price is that a Linux screen reader sees an empty window. Start the app
/// with `VE_LINUX_A11Y=1` in the environment (or build with
/// `--dart-define=VE_LINUX_A11Y=true`) to keep accessibility on and accept the
/// errors. Other platforms are untouched.
class DesktopSemanticsGate extends StatelessWidget {
  const DesktopSemanticsGate({super.key, required this.child, bool? exclude})
    : _exclude = exclude;

  final Widget child;
  final bool? _exclude;

  /// Whether windows leave their semantics out on this platform.
  static bool get excludesByDefault {
    if (kIsWeb || !Platform.isLinux) return false;
    if (const bool.fromEnvironment('VE_LINUX_A11Y')) return false;
    return Platform.environment['VE_LINUX_A11Y'] != '1';
  }

  @override
  Widget build(BuildContext context) {
    final exclude = _exclude ?? excludesByDefault;
    if (!exclude) return child;
    return ExcludeSemantics(child: child);
  }
}
