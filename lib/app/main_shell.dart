import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_screen.dart';
import 'package:vaultexplorer/features/settings/app_settings_screen.dart';
import 'package:vaultexplorer/features/tools/tools_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final ValueNotifier<List<MountedContainer>> _mountedNotifier =
      ValueNotifier(const []);
  final GlobalKey<VaultDashboardState> _dashboardKey =
      GlobalKey<VaultDashboardState>();

  @override
  void initState() {
    super.initState();
    // 1. Ensure screenshot protection is active in the real vault
    AppSettingsService.loadSettings().then((settings) {
      SecureScreenPolicy.apply(preference: settings.blockScreenshots);
    });
  }

  @override
  void dispose() {
    _mountedNotifier.dispose();
    // 2. When leaving the vault and returning to decoy mode, re-enable screenshots
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

    // Landscape: a side rail keeps navigation reachable without spending
    // any of the window's (now scarce) vertical space on a bar across the
    // bottom. Gated on orientation alone -- unlike the two-column content
    // layouts elsewhere, a slim rail comfortably fits any landscape width.
    if (context.screen.isLandscape) {
      return Scaffold(
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
    }

    return Scaffold(
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

/// Left-hand rail shown instead of the bottom bar in landscape. Mirrors the
/// bottom bar's icon-over-label destinations and pill-shaped selection
/// indicator, just rotated into a column that costs width -- which
/// landscape has to spare -- instead of height, which it doesn't.
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
