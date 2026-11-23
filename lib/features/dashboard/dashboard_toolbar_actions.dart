import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Entry points of the Home dashboard, published for the desktop toolbar.
///
/// The Home app bar is built by the shell (const, outside the dashboard's
/// widget subtree), so it cannot reach [VaultDashboardState] directly. The
/// live dashboard registers its actions here and the toolbar listens. A null
/// value means no dashboard is mounted, and the toolbar buttons disable
/// themselves.
class DashboardToolbarActions {
  /// Opens the "Add a vault" options (mount existing, create new, USB).
  final ValueNotifier<VoidCallback?> addVault = ValueNotifier(null);

  /// What the toolbar's search field holds. The dashboard filters its vault
  /// list by it; an empty string means no filter.
  final ValueNotifier<String> searchQuery = ValueNotifier('');
}

final dashboardToolbarActionsProvider = Provider<DashboardToolbarActions>(
  (ref) => DashboardToolbarActions(),
);
