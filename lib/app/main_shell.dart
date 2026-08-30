import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_screen.dart';
import 'package:vaultexplorer/features/settings/app_settings_screen.dart';
import 'package:vaultexplorer/features/tools/tools_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;
  final ValueNotifier<List<MountedContainer>> _mountedNotifier =
      ValueNotifier(const []);
  final GlobalKey<VaultDashboardState> _dashboardKey =
      GlobalKey<VaultDashboardState>();

  @override
  void initState() {
    super.initState();
    ref.read(appSettingsServiceProvider).loadSettings().then((settings) {
      SecureScreenPolicy.apply(preference: settings.blockScreenshots);
    });
  }

  @override
  void dispose() {
    _mountedNotifier.dispose();
    disguiseModeApi.getMode().then((mode) {
      if (mode == DisguiseMode.decoy) {
        SecureScreenPolicy.disableForDecoy();
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
            SafeArea(
              right: false,
              child: _NavRail(
                destinations: destinations,
                selectedIndex: _index,
                onTap: _onTabTap,
              ),
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