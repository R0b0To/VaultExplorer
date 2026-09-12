import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_screen.dart';
import 'package:vaultexplorer/features/settings/app_settings_screen.dart';
import 'package:vaultexplorer/features/share_import/share_import_flow.dart';
import 'package:vaultexplorer/features/tools/tools_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  final bool hideDashboardUntilShareHandled;

  const MainShell({
    super.key,
    this.hideDashboardUntilShareHandled = false,
  });

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;
  late bool _hideDashboard = widget.hideDashboardUntilShareHandled;
  final ValueNotifier<List<MountedContainer>> _mountedNotifier =
      ValueNotifier(const []);
  final GlobalKey<VaultDashboardState> _dashboardKey =
      GlobalKey<VaultDashboardState>();

  // Cached synchronously while the widget is mounted
  late final _secureScreenPolicy = ref.read(secureScreenPolicyProvider);
  late final _vaultEngineEvents = ref.read(vaultEngineEventsProvider);

  // Guards against the narrow race where a share intent arrives right as
  // MainShell is first built: the listener below and
  // _checkPendingShareOnStart's post-frame pull could otherwise both end
  // up resolving the same still-pending request and call
  // presentIncomingShareImport twice.
  bool _handlingShareRequest = false;
  int _shareSeq = 0;
  Route<dynamic>? _activeShareRoute;
  IncomingShareRequest? _lastHandledShareRequest;
  final DateTime _shellCreatedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    final policy = _secureScreenPolicy; // Eagerly evaluate while mounted
    ref.read(appSettingsServiceProvider).loadSettings().then((settings) {
      policy.apply(
        preference: settings.blockScreenshots,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkPendingShareOnStart();
    });
    _vaultEngineEvents.addIncomingShareRequestListener(_onIncomingShareRequest);
  }

  Future<void> _checkPendingShareOnStart() async {
    final request = await ref
        .read(vaultFileIoApiProvider)
        .checkPendingShareRequest();
    if (request == null || !mounted) {
      if (_hideDashboard) {
        setState(() => _hideDashboard = false);
      }
      return;
    }
    // If the push listener already began presenting this share request,
    // avoid tearing down and recreating the share sheet.
    if (_handlingShareRequest) return;
    _onIncomingShareRequest(request);
  }

  bool _isSameShareRequest(IncomingShareRequest? a, IncomingShareRequest? b) {
    if (a == null || b == null) return false;
    if (identical(a, b) || a == b) return true;
    if (a.toString() != "Instance of 'IncomingShareRequest'" &&
        a.toString() == b.toString()) {
      return true;
    }
    // Startup safety window: two incoming share triggers within 2 seconds
    // of shell creation represent the duplicate push/pull cold start race.
    if (DateTime.now().difference(_shellCreatedAt) < const Duration(seconds: 2)) {
      return true;
    }
    return false;
  }

  void _onIncomingShareRequest(IncomingShareRequest request) {
    if (!mounted) return;

    // Deduplicate push/pull races while a share route is already active
    if (_handlingShareRequest &&
        _activeShareRoute != null &&
        _activeShareRoute!.isActive &&
        _isSameShareRequest(_lastHandledShareRequest, request)) {
      return;
    }
    _lastHandledShareRequest = request;

    final mySeq = ++_shareSeq;
    if (_activeShareRoute != null && _activeShareRoute!.isActive) {
      _activeShareRoute!.navigator?.removeRoute(_activeShareRoute!);
      _activeShareRoute = null;
    }
    _handlingShareRequest = true;
    presentIncomingShareImport(
      context,
      ref,
      request,
      onRouteCreated: (route) => _activeShareRoute = route,
      isCurrent: () => mounted && _shareSeq == mySeq,
    ).whenComplete(() {
      if (!mounted) return;
      if (_shareSeq == mySeq) {
        _handlingShareRequest = false;
        _activeShareRoute = null;
        _lastHandledShareRequest = null;
        if (_hideDashboard) {
          setState(() => _hideDashboard = false);
        }
      }
    });
  }

  @override
  void dispose() {
    _mountedNotifier.dispose();
    _vaultEngineEvents.removeIncomingShareRequestListener(_onIncomingShareRequest);
    disguiseModeApi.getMode().then((mode) {
      if (mode == DisguiseMode.decoy) {
        // Safe: calling the cached service directly without using `ref`
        _secureScreenPolicy.disableForDecoy();
      }
    });
    super.dispose();
  }

  void _onTabTap(int newIndex) {
    if (_index != newIndex) {
      setState(() => _index = newIndex);
      if (newIndex == 0) {
        _dashboardKey.currentState?.reloadDashboard();
      }
    }
  }

  List<_NavDestination> _destinations(BuildContext context) => [
        _NavDestination(
          icon: Icons.lock_outline_rounded,
          selectedIcon: Icons.lock_rounded,
          label: context.l10n.navBarVaultsLabel,
        ),
        _NavDestination(
          icon: Icons.build_outlined,
          selectedIcon: Icons.build_rounded,
          label: context.l10n.navBarToolsLabel,
        ),
        _NavDestination(
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
          label: context.l10n.settingsTooltip,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // While an incoming share handoff is being presented, keep the underlying
    // dashboard hidden to avoid a momentary visual flash before the share sheet opens.
    if (_hideDashboard) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: const SizedBox.expand(),
      );
    }

    final destinations = _destinations(context);
    final body = IndexedStack(
      index: _index,
      children: [
        VaultDashboard(key: _dashboardKey, mountedNotifier: _mountedNotifier),
        ToolsScreen(mountedContainers: _mountedNotifier),
        const AppSettingsScreen(),
      ],
    );

    final Widget scaffold;
    if (context.screen.isLandscape) {
      scaffold = Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
           
             
              _NavRail(
                destinations: destinations,
                selectedIndex: _index,
                onTap: _onTabTap,
              ),
            
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: cs.outlineVariant.withValues(alpha: 0.4),
            ),
            Expanded(child: body),
          ],
        ),
      );
    } else {
      scaffold = Scaffold(
        body: body,
        bottomNavigationBar: Material(
          color: cs.surfaceContainer,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 68,
              child: Row(
                children: [
                  for (int i = 0; i < destinations.length; i++)
                    _MainBottomBarItem(
                      icon: destinations[i].icon,
                      selectedIcon: destinations[i].selectedIcon,
                      label: destinations[i].label,
                      selected: _index == i,
                      onTap: () => _onTabTap(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _onTabTap(0);
      },
      child: scaffold,
    );
  }
}

class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class _NavRail extends StatelessWidget {
  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const _NavRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return NavigationRail(
      backgroundColor: cs.surfaceContainer,
      groupAlignment: 0.0,
      selectedIndex: selectedIndex,
      onDestinationSelected: onTap,
      labelType: NavigationRailLabelType.all,
      useIndicator: true,
      indicatorColor: cs.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      selectedIconTheme: IconThemeData(color: cs.onSecondaryContainer, size: 22),
      unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant, size: 22),
      selectedLabelTextStyle: textTheme.labelSmall?.copyWith(
        color: cs.onSecondaryContainer,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: textTheme.labelSmall?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
      destinations: [
        for (final d in destinations)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: Text(d.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

class _MainBottomBarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MainBottomBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                decoration: BoxDecoration(
                  color: selected ? cs.secondaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(selected ? selectedIcon : icon, color: color, size: 22),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}