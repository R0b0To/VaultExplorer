import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Add / create entry points of the Home dashboard, published for the
/// desktop toolbar.
///
/// The Home app bar is built by the shell (const, outside the dashboard's
/// widget subtree), so it cannot reach [VaultDashboardState] directly. The
/// live dashboard registers its actions here and the toolbar listens. A null
/// value means no dashboard is mounted, and the toolbar buttons disable
/// themselves.
class DashboardToolbarActions {
  /// Mount / unlock an existing container or vault folder.
  final ValueNotifier<VoidCallback?> addVault = ValueNotifier(null);

  /// Create a new container.
  final ValueNotifier<VoidCallback?> createVault = ValueNotifier(null);
}

final dashboardToolbarActionsProvider = Provider<DashboardToolbarActions>(
  (ref) => DashboardToolbarActions(),
);
