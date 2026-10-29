import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/utils/sensitive_clipboard.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/biometric_enrollment_guard.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/lock/duress_settings_service.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_setup_sheet.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_pin_verify_sheet.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_setup_sheet.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/data/services/settings_backup_service.dart';
import 'package:vaultexplorer/features/dashboard/widgets/quick_password_generator_sheet.dart';
import 'package:vaultexplorer/features/authenticator/authenticator_settings_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_toolbar_settings_screen.dart';
import 'package:vaultexplorer/features/settings/about_screen.dart';
import 'package:vaultexplorer/features/settings/app_skin_settings_screen.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/emergency_settings_screen.dart';
import 'package:vaultexplorer/features/settings/quick_capture_settings_screen.dart';
import 'package:vaultexplorer/features/settings/logcat_screen.dart';
import 'package:vaultexplorer/features/settings/file_manager_skin_screen.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_screen.dart';
import 'package:vaultexplorer/features/settings/search/settings_search_index.dart';
import 'package:vaultexplorer/features/settings/search/settings_search_matcher.dart';
import 'package:vaultexplorer/features/settings/search/settings_search_models.dart';
import 'package:vaultexplorer/features/settings/search/settings_search_target.dart';
import 'package:vaultexplorer/features/settings/search/settings_search_widgets.dart';
import 'package:vaultexplorer/features/settings/settings_live_refresh.dart';
import 'package:vaultexplorer/features/settings/widgets/global_thumbnail_defaults_tiles.dart';
import '../../app/vault_explorer_app.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';

class AppSettingsScreen extends ConsumerStatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

const _kAndroidSdkR = 30;
const _kAndroidSdkS = 31;

/// The settings hubs shown in the persistent sidebar on wide/landscape
/// layouts. Order and membership mirror the hub tiles used in the narrow,
/// single-column layout.
enum _SettingsSection {
  security,
  storage,
  fileHandling,
  fileManager,
  appearance,
  advanced,
  about,
}

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen>
    with WidgetsBindingObserver {
  // Which hub is shown in the detail pane when the sidebar layout is
  // active. Only used on wide/landscape layouts; the narrow layout
  // navigates with the app's normal Navigator instead.
  _SettingsSection _selectedSection = _SettingsSection.security;

  // ── Settings search ──────────────────────────────────────────────────────
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _searchQuery = '';

  // The resolved search index, rebuilt when the app language or the Android
  // version it was built for changes.
  List<ResolvedSettingsEntry>? _searchIndex;
  Locale? _searchIndexLocale;
  int _searchIndexSdk = -1;

  // Set when a search result is opened on the wide layout and consumed, once,
  // by the detail pane's Navigator when it builds its initial routes.
  // [_detailNonce] gives each opened result a fresh Navigator.
  int _detailNonce = 0;
  SettingsDestination? _pendingDestination;
  SettingsSearchTarget? _pendingTarget;

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appSettingsControllerProvider.notifier).checkStoragePermission();
    }
  }

  // ───────────────────────────── Settings search ─────────────────────────────

  List<ResolvedSettingsEntry> _resolveSearchIndex(int androidSdkInt) {
    final locale = Localizations.localeOf(context);
    final cached = _searchIndex;
    if (cached != null &&
        _searchIndexLocale == locale &&
        _searchIndexSdk == androidSdkInt) {
      return cached;
    }
    final index = resolveSettingsSearchIndex(
      context.l10n,
      androidSdkInt: androidSdkInt,
    );
    _searchIndex = index;
    _searchIndexLocale = locale;
    _searchIndexSdk = androidSdkInt;
    return index;
  }

  List<ResolvedSettingsEntry> _searchResults() {
    final sdk = ref.read(appSettingsControllerProvider).androidSdkInt;
    return searchSettingsIndex(_searchQuery, _resolveSearchIndex(sdk));
  }

  Widget _buildSearchField() {
    return SettingsSearchField(
      controller: _searchController,
      focusNode: _searchFocus,
      onChanged: (value) => setState(() => _searchQuery = value),
      onSubmitted: () {
        final results = _searchResults();
        if (results.isNotEmpty) _openSearchResult(results.first);
      },
    );
  }

  Widget _buildSearchResults() {
    return SettingsSearchResults(
      results: _searchResults(),
      onOpen: _openSearchResult,
    );
  }

  /// Opens the screen a search result lives on and scrolls to its row.
  void _openSearchResult(ResolvedSettingsEntry result) {
    _searchFocus.unfocus();
    final destination = result.destination;
    final target = result.scrollTo
        ? SettingsSearchTarget(
            text: result.title,
            section: result.section,
            fallback: result.fallback,
            unavailableMessage: context.l10n.settingsSearchUnavailable,
          )
        : null;

    if (context.screen.useWideLayout) {
      // Select the result's hub in the sidebar and open it (and, for a
      // sub-screen, the sub-screen on top of it) in the detail pane.
      setState(() {
        _selectedSection = _sectionFor(destination.hub);
        _detailNonce++;
        _pendingDestination = destination;
        _pendingTarget = target;
      });
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsSearchTargetScope(
          target: target,
          child: SkinAreaScope(
            area: SkinArea.settings,
            child: _screenFor(destination, embedded: false),
          ),
        ),
      ),
    );
  }

  _SettingsSection _sectionFor(SettingsHub hub) => switch (hub) {
    SettingsHub.security => _SettingsSection.security,
    SettingsHub.storage => _SettingsSection.storage,
    SettingsHub.fileHandling => _SettingsSection.fileHandling,
    SettingsHub.fileManager => _SettingsSection.fileManager,
    SettingsHub.appearance => _SettingsSection.appearance,
    SettingsHub.advanced => _SettingsSection.advanced,
    SettingsHub.about => _SettingsSection.about,
  };

  SettingsDestination _destinationFor(_SettingsSection section) =>
      switch (section) {
        _SettingsSection.security => SettingsDestination.security,
        _SettingsSection.storage => SettingsDestination.storage,
        _SettingsSection.fileHandling => SettingsDestination.fileHandling,
        _SettingsSection.fileManager => SettingsDestination.fileManager,
        _SettingsSection.appearance => SettingsDestination.appearance,
        _SettingsSection.advanced => SettingsDestination.advanced,
        _SettingsSection.about => SettingsDestination.about,
      };

  /// The screen for a search destination. [embedded] is true for hubs shown in
  /// the wide layout's detail pane (drawn without their own app bar).
  Widget _screenFor(SettingsDestination destination, {required bool embedded}) {
    return switch (destination) {
      SettingsDestination.security => SecuritySettingsScreen(
        embedded: embedded,
      ),
      SettingsDestination.storage => StorageServicesSettingsScreen(
        embedded: embedded,
      ),
      SettingsDestination.fileHandling => FileHandlingSettingsScreen(
        embedded: embedded,
      ),
      SettingsDestination.fileManager => const FileManagerToolbarSettingsScreen(),
      SettingsDestination.appearance => AppearanceSettingsScreen(
        embedded: embedded,
      ),
      SettingsDestination.advanced => AdvancedSettingsScreen(
        embedded: embedded,
      ),
      SettingsDestination.about => AboutScreen(embedded: embedded),
      SettingsDestination.emergency => const EmergencySettingsScreen(),
      SettingsDestination.quickCapture => const QuickCaptureSettingsScreen(),
      SettingsDestination.authenticator => const AuthenticatorSettingsScreen(),
      SettingsDestination.appSkin => const AppSkinSettingsScreen(),
      SettingsDestination.fileManagerSkin => const FileManagerSkinScreen(),
      SettingsDestination.mediaPlayer =>
        const MediaViewerToolbarSettingsScreen(),
      SettingsDestination.logcat => const LogcatScreen(),
    };
  }

  Widget _buildHubTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool selected = false,
    bool showChevron = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      selected: selected,
      selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.4),
      shape: selected
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
          : null,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            )
          : null,
      trailing: showChevron
          ? Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            )
          : null,
      onTap: onTap,
    );
  }

  /// The persistent sidebar shown alongside the detail pane on
  /// wide/landscape layouts -- same hubs as the narrow layout's list, but
  /// selecting one swaps the detail pane in place instead of pushing a
  /// full-screen route.
  Widget _buildSidebar() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      children: [
        _buildSearchField(),
        const SizedBox(height: 12),
        if (_isSearching)
          _buildSearchResults()
        else ...[
          SectionCard(
            children: [
              _buildHubTile(
                icon: Icons.shield_rounded,
                iconColor: cs.primary,
                title: context.l10n.sectionSecurityPrivacy,
                subtitle: context.l10n.settingsHubSecuritySubtitle,
                selected: _selectedSection == _SettingsSection.security,
                showChevron: false,
                onTap: () =>
                    setState(() => _selectedSection = _SettingsSection.security),
              ),
              _buildHubTile(
                icon: Icons.settings_input_composite_rounded,
                iconColor: cs.secondary,
                title: context.l10n.sectionKeyStorageIntegration,
                subtitle: context.l10n.settingsHubStorageSubtitle,
                selected: _selectedSection == _SettingsSection.storage,
                showChevron: false,
                onTap: () =>
                    setState(() => _selectedSection = _SettingsSection.storage),
              ),
              _buildHubTile(
                icon: Icons.folder_copy_rounded,
                iconColor: cs.tertiary,
                title: context.l10n.sectionVaultFileHandling,
                subtitle: context.l10n.settingsHubFileHandlingSubtitle,
                selected: _selectedSection == _SettingsSection.fileHandling,
                showChevron: false,
                onTap: () => setState(
                  () => _selectedSection = _SettingsSection.fileHandling,
                ),
              ),
              _buildHubTile(
                icon: Icons.tune_rounded,
                iconColor: Colors.blueAccent,
                title: context.l10n.fileManagerSettingsTitle,
                subtitle: '${context.l10n.browserLayoutSectionHeader}, ${context.l10n.toolbarLayoutSectionHeader}',
                selected: _selectedSection == _SettingsSection.fileManager,
                showChevron: false,
                onTap: () => setState(
                  () => _selectedSection = _SettingsSection.fileManager,
                ),
              ),
              _buildHubTile(
                icon: Icons.palette_rounded,
                iconColor: Colors.deepPurpleAccent,
                title: context.l10n.sectionAppearanceInterface,
                subtitle: context.l10n.settingsHubAppearanceSubtitle,
                selected: _selectedSection == _SettingsSection.appearance,
                showChevron: false,
                onTap: () => setState(
                  () => _selectedSection = _SettingsSection.appearance,
                ),
              ),
              _buildHubTile(
                icon: Icons.terminal_rounded,
                iconColor: Colors.teal,
                title:
                    '${context.l10n.sectionBackupRestore} & ${context.l10n.sectionDebug}',
                subtitle: context.l10n.settingsHubAdvancedSubtitle,
                selected: _selectedSection == _SettingsSection.advanced,
                showChevron: false,
                onTap: () =>
                    setState(() => _selectedSection = _SettingsSection.advanced),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(
            children: [
              _buildHubTile(
                icon: Icons.info_outline_rounded,
                iconColor: cs.primary,
                title: context.l10n.aboutAppTitle,
                subtitle: context.l10n.versionInfoSubtitle(appVersion),
                selected: _selectedSection == _SettingsSection.about,
                showChevron: false,
                onTap: () =>
                    setState(() => _selectedSection = _SettingsSection.about),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// The right-hand detail pane on wide/landscape layouts.
  Widget _buildDetailPane() {
    return Navigator(
      key: ValueKey((_selectedSection, _detailNonce)),
      onGenerateInitialRoutes: (navigator, initialRoute) {
        // A search result opened on this layout leaves its destination and
        // row here; take them once so later rebuilds don't replay them.
        final destination = _pendingDestination;
        final target = _pendingTarget;
        _pendingDestination = null;
        _pendingTarget = null;
        final subScreen = (destination != null && !destination.isHub)
            ? destination
            : null;

        return [
          MaterialPageRoute<void>(
            builder: (_) => SettingsSearchTargetScope(
              target: subScreen == null ? target : null,
              child: SkinAreaScope(
                area: SkinArea.settings,
                child: _screenFor(
                  _destinationFor(_selectedSection),
                  embedded: true,
                ),
              ),
            ),
          ),
          if (subScreen != null)
            MaterialPageRoute<void>(
              builder: (_) => SettingsSearchTargetScope(
                target: target,
                child: SkinAreaScope(
                  area: SkinArea.settings,
                  child: _screenFor(subScreen, embedded: false),
                ),
              ),
            ),
        ];
      },
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => SkinAreaScope(
          area: SkinArea.settings,
          child: _screenFor(_destinationFor(_selectedSection), embedded: true),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appSettingsControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          context.l10n.appSettingsTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : SafeArea(
              child: context.screen.useWideLayout
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: context.screen.secondaryPaneWidth(),
                          child: _buildSidebar(),
                        ),
                        const VerticalDivider(width: 0.2),
                        Expanded(child: _buildDetailPane()),
                      ],
                    )
                  : _buildNarrowHubList(cs, textTheme),
            ),
    );
  }

  /// The narrow-layout hub list: tapping a hub pushes its screen as a full-screen route.
  Widget _buildNarrowHubList(ColorScheme cs, TextTheme textTheme) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            _buildSearchField(),
            const SizedBox(height: 12),
            if (_isSearching)
              _buildSearchResults()
            else ...[
              // Grouped Settings Hubs in a single SectionCard
              SectionCard(
                children: [
                  _buildHubTile(
                    icon: Icons.shield_rounded,
                    iconColor: cs.primary,
                    title: context.l10n.sectionSecurityPrivacy,
                    subtitle: context.l10n.settingsHubSecuritySubtitle,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const SecuritySettingsScreen()),
                      ),
                    ),
                  ),
                  _buildHubTile(
                    icon: Icons.settings_input_composite_rounded,
                    iconColor: cs.secondary,
                    title: context.l10n.sectionKeyStorageIntegration,
                    subtitle: context.l10n.settingsHubStorageSubtitle,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const StorageServicesSettingsScreen()),
                      ),
                    ),
                  ),
                  _buildHubTile(
                    icon: Icons.folder_copy_rounded,
                    iconColor: cs.tertiary,
                    title: context.l10n.sectionVaultFileHandling,
                    subtitle: context.l10n.settingsHubFileHandlingSubtitle,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const FileHandlingSettingsScreen()),
                      ),
                    ),
                  ),
                  _buildHubTile(
                    icon: Icons.tune_rounded,
                    iconColor: Colors.blueAccent,
                    title: context.l10n.fileManagerSettingsTitle,
                    subtitle: '${context.l10n.browserLayoutSectionHeader}, ${context.l10n.toolbarLayoutSectionHeader}',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const FileManagerToolbarSettingsScreen()),
                      ),
                    ),
                  ),
                  _buildHubTile(
                    icon: Icons.palette_rounded,
                    iconColor: Colors.deepPurpleAccent,
                    title: context.l10n.sectionAppearanceInterface,
                    subtitle: context.l10n.settingsHubAppearanceSubtitle,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const AppearanceSettingsScreen()),
                      ),
                    ),
                  ),
                  _buildHubTile(
                    icon: Icons.terminal_rounded,
                    iconColor: Colors.teal,
                    title:
                        '${context.l10n.sectionBackupRestore} & ${context.l10n.sectionDebug}',
                    subtitle: context.l10n.settingsHubAdvancedSubtitle,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const AdvancedSettingsScreen()),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // About Card in its own matching SectionCard
              SectionCard(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: cs.primary,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      context.l10n.aboutAppTitle,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.versionInfoSubtitle(appVersion),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const AboutScreen())),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. SECURITY, PRIVACY & STEALTH SUB-PAGE
// ─────────────────────────────────────────────────────────────────────────────

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  /// True when this screen is embedded in the wide-layout detail pane
  /// (drawn without its own AppBar/back button) rather than pushed as a
  /// full-screen route.
  final bool embedded;

  const SecuritySettingsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();
  bool _obscurePw = true;
  bool _obscureConfirm = true;
  final _localAuth = LocalAuthentication();
  bool _recentlyCreatedMasterCredential = false;

  /// Set while the inline master-password form is open: whether saving the
  /// password also makes it the method the gate shows first, and what to do
  /// once it is saved (e.g. go on to enable biometrics behind it).
  bool _pwSetupMakesActive = true;
  Future<void> Function()? _onPasswordSaved;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _openPasswordGenerator() async {
    final password = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (ctx) => const QuickPasswordGeneratorSheet(),
    );

    if (password != null && mounted) {
      setState(() {
        _pwCtrl.text = password;
        _pwConfirmCtrl.text = password;
        _obscurePw = false;
        _obscureConfirm = false;
      });
      await ref.read(sensitiveClipboardProvider).copy(password);
    }
  }

  Future<void> _confirmPassword() async {
    final pw = _pwCtrl.text;
    final confirm = _pwConfirmCtrl.text;
    if (pw.isEmpty) {
      ref
          .read(appSettingsControllerProvider.notifier)
          .setPwError(context.l10n.passwordCannotBeEmpty);
      return;
    }
    if (pw.length < 4) {
      ref
          .read(appSettingsControllerProvider.notifier)
          .setPwError(context.l10n.atLeast4CharsRequired);
      return;
    }
    if (pw != confirm) {
      ref
          .read(appSettingsControllerProvider.notifier)
          .setPwError(context.l10n.passwordsDoNotMatch);
      return;
    }

    final isDuress = await ref
        .read(duressSettingsServiceProvider)
        .verifyPassword(pw);
    if (isDuress) {
      ref
          .read(appSettingsControllerProvider.notifier)
          .setPwError(context.l10n.masterMatchesDuressPasswordError);
      return;
    }

    final ok = await ref
        .read(appSettingsControllerProvider.notifier)
        .saveMasterPassword(
          pw,
          context.l10n,
          makeActive: _pwSetupMakesActive,
        );

    if (ok && mounted) {
      _recentlyCreatedMasterCredential = true;
      _pwCtrl.clear();
      _pwConfirmCtrl.clear();
      showAppSnackBar(
        context,
        message: context.l10n.masterPasswordSetSnack,
        tone: AppBannerTone.success,
      );
      final onSaved = _onPasswordSaved;
      _onPasswordSaved = null;
      if (onSaved != null) await onSaved();
    }
  }

  /// Opens the inline password form. The lock flag goes on first because the
  /// stored hashes are only read back while it is on.
  Future<void> _beginPasswordSetup({
    required bool makeActive,
    Future<void> Function()? onSaved,
  }) async {
    final controller = ref.read(appSettingsControllerProvider.notifier);
    _pwSetupMakesActive = makeActive;
    _onPasswordSaved = onSaved;
    _pwCtrl.clear();
    _pwConfirmCtrl.clear();
    await controller.updateSettings((s) => s.copyWith(useMasterPassword: true));
    if (!mounted) return;
    controller.setShowPwFields(true);
  }

  /// Closes the inline password form. If nothing else is set up yet the lock
  /// goes back off, since a lock with no credential is no lock.
  void _cancelPasswordSetup() {
    _pwCtrl.clear();
    _pwConfirmCtrl.clear();
    _onPasswordSaved = null;
    final controller = ref.read(appSettingsControllerProvider.notifier);
    controller.setShowPwFields(false);
    if (!ref.read(appSettingsControllerProvider).settings.hasMasterCredential) {
      controller.updateSettings((s) => s.copyWith(useMasterPassword: false));
    }
  }

  Future<void> _selectMasterUnlockMethod(MasterUnlockMethod method) async {
    final settingsState = ref.read(appSettingsControllerProvider);
    if (method == settingsState.settings.masterUnlockMethod) return;

    // Skip verification if the user set a credential up in this session
    if (!_recentlyCreatedMasterCredential) {
      final verified = await _verifyCurrentUnlockCredential(settingsState);
      if (!verified || !mounted) return;
    }

    final controller = ref.read(appSettingsControllerProvider.notifier);

    if (method == MasterUnlockMethod.biometrics) {
      try {
        final authenticated = await _localAuth.authenticate(
          localizedReason: context.l10n.biometricUnlockTitle,
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );
        if (!authenticated) return;
      } catch (e) {
        VeLog.w('SecuritySettingsScreen', 'Biometric auth failed on toggle', e);
        return;
      }
      if (!mounted) return;
      if (!await controller.setMasterUnlockMethod(method)) {
        if (mounted) {
          showAppSnackBar(
            context,
            message: context.l10n.biometricNotAvailable,
            tone: AppBannerTone.error,
          );
        }
        return;
      }
      _recentlyCreatedMasterCredential = false;
      return;
    }

    if (settingsState.settings.hasMasterCredentialFor(method)) {
      await controller.setMasterUnlockMethod(method);
      _recentlyCreatedMasterCredential = false;
      return;
    }

    // Not set up yet: set it up now, and it becomes the active method.
    await _setUpCredential(method, makeActive: true);
    _recentlyCreatedMasterCredential = false;
  }

  /// Runs the setup flow for one credential. PIN and pattern open their sheet
  /// and return whether something was saved. The password uses the inline
  /// form, which finishes later: this returns false for it, and whatever
  /// should follow a successful save goes in [onPasswordSaved].
  Future<bool> _setUpCredential(
    MasterUnlockMethod credential, {
    required bool makeActive,
    Future<void> Function()? onPasswordSaved,
  }) async {
    switch (credential) {
      case MasterUnlockMethod.pin:
        return _setupMasterPin(makeActive: makeActive);
      case MasterUnlockMethod.pattern:
        return _setupMasterPattern(makeActive: makeActive);
      case MasterUnlockMethod.password:
        await _beginPasswordSetup(
          makeActive: makeActive,
          onSaved: onPasswordSaved,
        );
        return false;
      case MasterUnlockMethod.biometrics:
        return false;
    }
  }

  String _credentialName(BuildContext ctx, MasterUnlockMethod method) =>
      switch (method) {
        MasterUnlockMethod.password => ctx.l10n.masterCredentialPassword,
        MasterUnlockMethod.pin => ctx.l10n.masterCredentialPin,
        MasterUnlockMethod.pattern => ctx.l10n.masterCredentialPattern,
        MasterUnlockMethod.biometrics => method.getLocalizedLabel(ctx.l10n),
      };

  Future<MasterUnlockMethod?> _pickMasterMethod({
    required String title,
    String? message,
    required List<MasterUnlockMethod> options,
  }) {
    return showModalBottomSheet<MasterUnlockMethod>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      message,
                      style: textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                for (final m in options)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: Icon(m.icon),
                    title: Text(_credentialName(ctx, m)),
                    subtitle: Text(m.getLocalizedSubtitle(ctx.l10n)),
                    onTap: () => Navigator.pop(ctx, m),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Switching the master lock on: pick how to lock the app, then set that
  /// up on its own -- a PIN or a pattern needs no master password behind it.
  /// Biometrics are the one exception: they are not a credential, so picking
  /// them also asks for a password, PIN or pattern to fall back on.
  Future<void> _enableMasterLock() async {
    final biometricAvailable = ref
        .read(appSettingsControllerProvider)
        .biometricAvailable;
    final choice = await _pickMasterMethod(
      title: context.l10n.masterLockChooseTitle,
      options: [
        ...MasterUnlockMethod.credentials,
        if (biometricAvailable) MasterUnlockMethod.biometrics,
      ],
    );
    if (choice == null || !mounted) return;

    final withBiometrics = choice == MasterUnlockMethod.biometrics;
    var credential = choice;
    if (withBiometrics) {
      final backup = await _pickMasterMethod(
        title: context.l10n.masterLockBackupTitle,
        message: context.l10n.masterLockBackupMessage,
        options: MasterUnlockMethod.credentials,
      );
      if (backup == null || !mounted) return;
      credential = backup;
    }

    // The credential becomes the active method first. If the biometric step
    // that follows is cancelled, the lock simply stays on that credential.
    Future<void> finish() async {
      _recentlyCreatedMasterCredential = true;
      if (withBiometrics && mounted) {
        await _selectMasterUnlockMethod(MasterUnlockMethod.biometrics);
      }
    }

    // Stored hashes are only read back while the flag is on.
    await ref
        .read(appSettingsControllerProvider.notifier)
        .updateSettings((s) => s.copyWith(useMasterPassword: true));
    if (!mounted) return;

    final saved = await _setUpCredential(
      credential,
      makeActive: true,
      onPasswordSaved: finish,
    );
    if (!mounted) return;
    if (saved) {
      await finish();
    } else if (credential != MasterUnlockMethod.password) {
      // The sheet was dismissed: nothing was set up, so the lock goes back off.
      await _switchOffLockIfEmpty();
    }
  }

  Future<void> _switchOffLockIfEmpty() async {
    final settings = ref.read(appSettingsControllerProvider).settings;
    if (settings.hasMasterCredential) return;
    await ref
        .read(appSettingsControllerProvider.notifier)
        .updateSettings((s) => s.copyWith(useMasterPassword: false));
  }

  /// Set or change one credential, leaving the active method alone.
  Future<void> _changeCredential(MasterUnlockMethod credential) async {
    final state = ref.read(appSettingsControllerProvider);
    if (!_recentlyCreatedMasterCredential) {
      final verified = await _verifyCurrentUnlockCredential(state);
      if (!verified || !mounted) return;
    }
    _recentlyCreatedMasterCredential = false;
    await _setUpCredential(credential, makeActive: false);
  }

  /// Remove one credential, keeping the lock on (the last one cannot be
  /// removed; switch the lock off instead).
  Future<void> _removeCredential(MasterUnlockMethod credential) async {
    final state = ref.read(appSettingsControllerProvider);
    final verified = await _verifyStrongCredential(state);
    if (!verified || !mounted) return;
    _recentlyCreatedMasterCredential = false;
    await ref
        .read(appSettingsControllerProvider.notifier)
        .removeMasterCredential(credential);
  }

  List<Widget> _buildCredentialTiles(
    AppSettingsViewState state,
    TextTheme textTheme,
    ColorScheme cs,
  ) {
    final settings = state.settings;
    final canRemove = settings.configuredMasterCredentials.length > 1;
    return [
      for (final m in MasterUnlockMethod.credentials)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Icon(m.icon),
          title: Text(
            _credentialName(context, m),
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            settings.hasMasterCredentialFor(m)
                ? context.l10n.masterCredentialSet
                : context.l10n.masterCredentialNotSet,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          trailing: settings.hasMasterCredentialFor(m) && canRemove
              ? IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: context.l10n.remove,
                  onPressed: () => _removeCredential(m),
                )
              : null,
          onTap: () => _changeCredential(m),
        ),
    ];
  }

  /// Whether the master lock's biometric unlock may still be used. When the
  /// device's biometrics changed it has just been switched back to the master
  /// password: reload so the screen shows that, say why, and refuse.
  Future<bool> _masterBiometricsStillTrusted() async {
    final check = await ref
        .read(biometricEnrollmentGuardProvider)
        .checkMaster();
    if (!mounted) return false;
    switch (check) {
      case BiometricGuardResult.ok:
        return true;
      case BiometricGuardResult.reverted:
        await ref.read(appSettingsControllerProvider.notifier).load();
        if (!mounted) return false;
        showAppSnackBar(
          context,
          message: context.l10n.biometricsChangedFallbackMessage,
          tone: AppBannerTone.warning,
        );
        return false;
      case BiometricGuardResult.unavailable:
        showAppSnackBar(
          context,
          message: context.l10n.biometricNotAvailable,
          tone: AppBannerTone.error,
        );
        return false;
    }
  }

  /// Verifies the credential the gate currently shows first. Guards changing
  /// the master lock's method and credentials.
  Future<bool> _verifyCurrentUnlockCredential(AppSettingsViewState state) =>
      _verifyCredential(
        state,
        state.settings.masterUnlockMethod,
        title: context.l10n.masterPasswordTitle,
        message: context.l10n.enterMasterPasswordPrompt,
      );

  /// Like [_verifyCurrentUnlockCredential], but never satisfied by biometrics
  /// alone: with biometric unlock active it asks for the credential behind
  /// them. Guards the changes that cannot be undone from the lock screen --
  /// switching the lock off or removing a credential.
  Future<bool> _verifyStrongCredential(
    AppSettingsViewState state, {
    String? passwordTitle,
    String? passwordMessage,
  }) {
    final settings = state.settings;
    final active = settings.masterUnlockMethod;
    final credential =
        active.isCredential && settings.hasMasterCredentialFor(active)
        ? active
        : (settings.configuredMasterCredentials.firstOrNull ??
              MasterUnlockMethod.password);
    return _verifyCredential(
      state,
      credential,
      title: passwordTitle ?? context.l10n.masterPasswordTitle,
      message: passwordMessage ?? context.l10n.enterMasterPasswordPrompt,
    );
  }

  Future<bool> _verifyCredential(
    AppSettingsViewState state,
    MasterUnlockMethod credential, {
    required String title,
    required String message,
  }) async {
    switch (credential) {
      case MasterUnlockMethod.password:
        return _verifyCurrentMasterPassword(
          state,
          title: title,
          message: message,
        );
      case MasterUnlockMethod.biometrics:
        try {
          // This prompt guards changing or removing the master lock, so a
          // biometric enrolled after biometric unlock was set up must not
          // pass it.
          if (!await _masterBiometricsStillTrusted()) return false;
          final ok = await _localAuth.authenticate(
            localizedReason: context.l10n.authenticateToModifySettingsPrompt,
            biometricOnly: true,
            persistAcrossBackgrounding: true,
          );
          return ok && await _masterBiometricsStillTrusted();
        } catch (e) {
          VeLog.w('SecuritySettingsScreen', 'Biometric verification failed', e);
          return false;
        }
      case MasterUnlockMethod.pattern:
        final hash = state.settings.masterPatternHash;
        if (hash == null || !mounted) return true;
        final result = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          builder: (_) => PatternVerifySheet(storedHash: hash),
        );
        return result != null;
      case MasterUnlockMethod.pin:
        final hash = state.settings.masterPinHash;
        if (hash == null || !mounted) return true;
        final result = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          builder: (_) => PinVerifySheet(storedHash: hash),
        );
        return result != null;
    }
  }

  /// Opens the pattern sheet and saves what was drawn. False when the sheet
  /// was dismissed or saving failed.
  Future<bool> _setupMasterPattern({required bool makeActive}) async {
    final duressPatternHash = await ref
        .read(duressSettingsServiceProvider)
        .getPatternHash();
    if (!mounted) return false;
    final hash = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PatternSetupSheet(
        disallowedHash: duressPatternHash,
        disallowedMessage: context.l10n.masterMatchesDuressPatternError,
      ),
    );
    if (hash == null || !mounted) return false;
    return ref
        .read(appSettingsControllerProvider.notifier)
        .saveMasterPattern(hash, makeActive: makeActive);
  }

  /// Opens the PIN sheet and saves what was entered. False when the sheet was
  /// dismissed or saving failed.
  Future<bool> _setupMasterPin({required bool makeActive}) async {
    final duressPinHash = await ref
        .read(duressSettingsServiceProvider)
        .getPinHash();
    if (!mounted) return false;
    final hash = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PinSetupSheet(
        disallowedHash: duressPinHash,
        disallowedMessage: context.l10n.masterMatchesDuressPinError,
      ),
    );
    if (hash == null || !mounted) return false;
    return ref
        .read(appSettingsControllerProvider.notifier)
        .saveMasterPin(hash, makeActive: makeActive);
  }

  Future<void> _toggleMasterPassword(
    AppSettingsViewState state,
    bool enabled,
  ) async {
    final controller = ref.read(appSettingsControllerProvider.notifier);
    if (enabled) {
      await _enableMasterLock();
      return;
    }
    _recentlyCreatedMasterCredential = false;
    if (!state.settings.hasMasterCredential) {
      // Nothing was ever saved (the password form is still open): just drop
      // the flag again.
      _pwCtrl.clear();
      _pwConfirmCtrl.clear();
      _onPasswordSaved = null;
      controller.setShowPwFields(false);
      controller.updateSettings((s) => s.copyWith(useMasterPassword: false));
      return;
    }
    final verified = await _verifyStrongCredential(
      state,
      passwordTitle: context.l10n.removeMasterPasswordTitle,
      passwordMessage: context.l10n.confirmRemoveMasterPasswordMessage,
    );
    if (!verified) {
      controller.updateSettings((s) => s.copyWith(useMasterPassword: true));
      return;
    }
    _pwCtrl.clear();
    _pwConfirmCtrl.clear();
    _onPasswordSaved = null;
    await controller.clearMasterPassword();
  }

  Future<bool> _verifyCurrentMasterPassword(
    AppSettingsViewState state, {
    String? title,
    String? message,
  }) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            final ctrl = TextEditingController();
            String? errorMsg;
            return StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                title: Text(title ?? context.l10n.removeMasterPasswordTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message ??
                          context.l10n.confirmRemoveMasterPasswordMessage,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ctrl,
                      obscureText: true,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: context.l10n.masterPasswordTitle,
                        errorText: errorMsg,
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(context.l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final passwordHasher = ref.read(passwordHasherProvider);
                      final isValid = await passwordHasher.verify(
                        candidate: ctrl.text,
                        hash: state.settings.masterPasswordHash,
                        salt: state.settings.masterPasswordSalt,
                      );
                      if (isValid) {
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } else {
                        setDialogState(
                          () => errorMsg = context.l10n.incorrectPassword,
                        );
                      }
                    },
                    child: Text(context.l10n.continueButton),
                  ),
                ],
              ),
            );
          },
        ) ??
        false;
  }

  Future<void> _setDiscreteMode(bool enable) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: enable
          ? context.l10n.enableDiscreteModeTitle
          : context.l10n.disableDiscreteModeTitle,
      message: enable
          ? context.l10n.enableDiscreteModeMessage
          : context.l10n.disableDiscreteModeMessage,
      confirmLabel: enable ? context.l10n.enable : context.l10n.disable,
    );
    if (!confirmed || !mounted) return;

    final targetMode = enable ? DisguiseMode.decoy : DisguiseMode.vault;
    final ok = await ref
        .read(appSettingsControllerProvider.notifier)
        .setDiscreteMode(enable);

    if (ok) {
      await ref.read(sessionLockControllerProvider).prepareForModeSwitchExit();
      if (!mounted) return;
      applyDisguiseModeTaskSwitcherLabel(targetMode, context.l10n);
      showAppSnackBar(
        context,
        message: enable
            ? context.l10n.discreteModeEnabledSnack
            : context.l10n.discreteModeDisabledSnack,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      SystemNavigator.pop();
    } else if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.failedToChangeDiscreteMode,
        tone: AppBannerTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appSettingsControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. App Authentication
              SectionHeader(context.l10n.masterLockTitle),
              SectionCard(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        title: Text(
                          context.l10n.masterLockTitle,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          state.settings.masterLockActive
                              ? context.l10n.masterPasswordActiveSubtitle
                              : context.l10n.masterLockInactiveSubtitle,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        value: state.settings.useMasterPassword,
                        onChanged: (v) => _toggleMasterPassword(state, v),
                      ),
                      if (state.settings.useMasterPassword &&
                          state.showPwFields) ...[
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: AutofillGroup(
                            child: Column(
                              children: [
                                TextField(
                                  controller: _pwCtrl,
                                  obscureText: _obscurePw,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: cs.surfaceContainerHighest,
                                    labelText:
                                        context.l10n.masterPasswordFieldLabel,
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            Icons.auto_awesome_rounded,
                                            size: 20,
                                            color: cs.primary,
                                          ),
                                          tooltip: context
                                              .l10n
                                              .generateStrongPasswordTooltip,
                                          onPressed: _openPasswordGenerator,
                                        ),
                                        PasswordVisibilityToggle(
                                          obscured: _obscurePw,
                                          onToggle: () => setState(
                                            () => _obscurePw = !_obscurePw,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _pwConfirmCtrl,
                                  obscureText: _obscureConfirm,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: cs.surfaceContainerHighest,
                                    labelText:
                                        context.l10n.confirmPasswordLabel,
                                    suffixIcon: PasswordVisibilityToggle(
                                      obscured: _obscureConfirm,
                                      onToggle: () => setState(
                                        () =>
                                            _obscureConfirm = !_obscureConfirm,
                                      ),
                                    ),
                                  ),
                                ),
                                if (state.pwError != null) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      state.pwError!,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: cs.error,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: state.saving
                                            ? null
                                            : _cancelPasswordSetup,
                                        child: Text(context.l10n.cancel),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: state.saving
                                            ? null
                                            : _confirmPassword,
                                        child: state.saving
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : Text(context.l10n.setPassword),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (state.settings.masterLockActive &&
                      !state.showPwFields) ...[
                    OptionPickerTile<MasterUnlockMethod>(
                      label: context.l10n.unlockCredentialsLabel,
                      value: state.settings.masterUnlockMethod,
                      subtitle: state.settings.masterUnlockMethod
                          .getLocalizedSubtitle(context.l10n),
                      options: MasterUnlockMethod.values
                          .where(
                            (m) =>
                                m != MasterUnlockMethod.biometrics ||
                                state.biometricAvailable ||
                                state.settings.masterUnlockMethod == m,
                          )
                          .map((m) {
                            final isUnavailableBio =
                                m == MasterUnlockMethod.biometrics &&
                                !state.biometricAvailable;
                            return SelectOption(
                              value: m,
                              label: isUnavailableBio
                                  ? '${m.getLocalizedLabel(context.l10n)} ${context.l10n.unavailableSuffixLabel}'
                                  : m.getLocalizedLabel(context.l10n),
                              subtitle: m.getLocalizedSubtitle(context.l10n),
                            );
                          })
                          .toList(),
                      onChanged: _selectMasterUnlockMethod,
                    ),
                    ..._buildCredentialTiles(state, textTheme, cs),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // 2. App Lock Behavior
              if (state.settings.masterLockActive &&
                  !state.showPwFields) ...[
                SectionHeader(context.l10n.appLockBehaviorTitle),
                SectionCard(
                  children: [
                    OptionPickerTile<int>(
                      label: context.l10n.autoLockTimeoutLabel,
                      value: state.settings.appLockScreenLockOnly
                          ? kScreenLockOnlyAutoLockDuration
                          : state.settings.appLockAfterMins,
                      options: autoLockDurationOptions(
                        context,
                        zeroOption: SelectOption(
                          value: 0,
                          label: context.l10n.immediately,
                        ),
                        screenLockOnlyOption: SelectOption(
                          value: kScreenLockOnlyAutoLockDuration,
                          label: context.l10n.screenLockOnlyAutoLockOption,
                          subtitle:
                              context.l10n.screenLockOnlyAutoLockOptionSubtitle,
                        ),
                        currentMinutes: state.settings.appLockScreenLockOnly
                            ? kScreenLockOnlyAutoLockDuration
                            : state.settings.appLockAfterMins,
                      ),
                      onChanged: (v) {
                        if (v == kCustomAutoLockDuration) {
                          pickCustomAutoLockDuration(
                            context,
                            currentMinutes: state.settings.appLockAfterMins,
                            onPicked: (mins) => ref
                                .read(appSettingsControllerProvider.notifier)
                                .updateSettings(
                                  (s) => s.copyWith(
                                    appLockAfterMins: mins,
                                    appLockScreenLockOnly: false,
                                  ),
                                ),
                          );
                        } else if (v == kScreenLockOnlyAutoLockDuration) {
                          ref
                              .read(appSettingsControllerProvider.notifier)
                              .updateSettings(
                                (s) => s.copyWith(
                                  appLockAfterMins: 0,
                                  appLockScreenLockOnly: true,
                                ),
                              );
                        } else {
                          ref
                              .read(appSettingsControllerProvider.notifier)
                              .updateSettings(
                                (s) => s.copyWith(
                                  appLockAfterMins: v,
                                  appLockScreenLockOnly: false,
                                ),
                              );
                        }
                      },
                    ),
                    if (!state.settings.appLockScreenLockOnly)
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        title: Text(
                          context.l10n.lockAppOnScreenOffTitle,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.lockAppOnScreenOffSubtitle,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        value: state.settings.lockAppOnScreenLock,
                        onChanged: (v) => ref
                            .read(appSettingsControllerProvider.notifier)
                            .updateSettings(
                              (s) => s.copyWith(lockAppOnScreenLock: v),
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // 3. Auto-Lock & Screen Privacy (vault containers)
              SectionHeader(context.l10n.autoLockContainersTitle),
              SectionCard(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.autoLockContainersTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.autoLockContainersSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.settings.lockContainersOnScreenLock,
                    onChanged: (v) => ref
                        .read(appSettingsControllerProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWith(
                            lockContainersOnScreenLock: v,
                            autoLockMins: v && s.autoLockMins == 0
                                ? 5
                                : (!v ? 0 : s.autoLockMins),
                            autoLockScreenLockOnly: !v
                                ? false
                                : s.autoLockScreenLockOnly,
                          ),
                        ),
                  ),
                  if (state.settings.lockContainersOnScreenLock)
                    OptionPickerTile<int>(
                      label: context.l10n.autoLockTimeoutLabel,
                      value: state.settings.autoLockScreenLockOnly
                          ? kScreenLockOnlyAutoLockDuration
                          : state.settings.autoLockMins,
                      options: autoLockDurationOptions(
                        context,
                        zeroOption: SelectOption(
                          value: 0,
                          label: context.l10n.immediately,
                        ),
                        screenLockOnlyOption: SelectOption(
                          value: kScreenLockOnlyAutoLockDuration,
                          label: context.l10n.screenLockOnlyAutoLockOption,
                          subtitle:
                              context.l10n.screenLockOnlyAutoLockOptionSubtitle,
                        ),
                        currentMinutes: state.settings.autoLockScreenLockOnly
                            ? kScreenLockOnlyAutoLockDuration
                            : state.settings.autoLockMins,
                      ),
                      onChanged: (v) {
                        if (v == kCustomAutoLockDuration) {
                          pickCustomAutoLockDuration(
                            context,
                            currentMinutes: state.settings.autoLockMins,
                            onPicked: (mins) => ref
                                .read(appSettingsControllerProvider.notifier)
                                .updateSettings(
                                  (s) => s.copyWith(
                                    autoLockMins: mins,
                                    autoLockScreenLockOnly: false,
                                  ),
                                ),
                          );
                        } else if (v == kScreenLockOnlyAutoLockDuration) {
                          ref
                              .read(appSettingsControllerProvider.notifier)
                              .updateSettings(
                                (s) => s.copyWith(
                                  autoLockMins: 0,
                                  autoLockScreenLockOnly: true,
                                ),
                              );
                        } else {
                          ref
                              .read(appSettingsControllerProvider.notifier)
                              .updateSettings(
                                (s) => s.copyWith(
                                  autoLockMins: v,
                                  autoLockScreenLockOnly: false,
                                ),
                              );
                        }
                      },
                    ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.blockScreenshotsTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.blockScreenshotsSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.settings.blockScreenshots,
                    onChanged: (v) async {
                      await ref
                          .read(secureScreenPolicyProvider)
                          .apply(preference: v);
                      await ref
                          .read(appSettingsControllerProvider.notifier)
                          .updateSettings(
                            (s) => s.copyWith(blockScreenshots: v),
                          );
                    },
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.cacheDerivedKeysTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.cacheDerivedKeysSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.settings.defaultDerivedKeyCacheEnabled,
                    onChanged: (v) => ref
                        .read(appSettingsControllerProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWith(defaultDerivedKeyCacheEnabled: v),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3a. Mask Mode
              SectionHeader(context.l10n.sectionMaskMode),
              SectionCard(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.discreteModeTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      state.disguiseMode == DisguiseMode.decoy
                          ? context.l10n.discreteModeActiveSubtitle
                          : context.l10n.discreteModeInactiveSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.disguiseMode == DisguiseMode.decoy,
                    onChanged: _setDiscreteMode,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 3b. Emergency Panic & Duress
              SectionHeader(context.l10n.emergencyPanicTitle),
              SectionCard(
                children: [
                  ListTile(
                    leading: Icon(Icons.warning_amber_rounded, color: cs.error),
                    title: Text(
                      context.l10n.emergencyPanicTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.emergencyPanicSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const EmergencySettingsScreen()),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 3c. Quick Capture
              SectionHeader(context.l10n.quickCaptureSettingsTitle),
              SectionCard(
                children: [
                  ListTile(
                    leading: Icon(Icons.bolt_rounded, color: cs.primary),
                    title: Text(
                      context.l10n.quickCaptureSettingsTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.quickCaptureSettingsSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const QuickCaptureSettingsScreen()),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 3d. Authenticator (TOTP 2FA)
              SectionHeader(context.l10n.authenticatorSettingsTitle),
              SectionCard(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.authenticatorEnableTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.authenticatorEnableSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.settings.enableAuthenticator,
                    onChanged: (v) => ref
                        .read(appSettingsControllerProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWith(enableAuthenticator: v),
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.embedded) {
      return Scaffold(body: body);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.sectionSecurityPrivacy,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. STORAGE & SYSTEM INTEGRATION SUB-PAGE
// ─────────────────────────────────────────────────────────────────────────────

class StorageServicesSettingsScreen extends ConsumerWidget {
  final bool embedded;

  const StorageServicesSettingsScreen({super.key, this.embedded = false});

  Future<void> _toggleStoragePermission(
    BuildContext context,
    WidgetRef ref,
    AppSettingsViewState state,
    bool enable,
  ) async {
    final isLegacy = state.androidSdkInt < _kAndroidSdkR;
    if (enable) {
      final grant = await showAppConfirmDialog(
        context,
        title: isLegacy
            ? context.l10n.enableStoragePermissionLegacyTitle
            : context.l10n.enableFastStorageAccessTitle,
        message: isLegacy
            ? context.l10n.enableStoragePermissionLegacyMessage
            : context.l10n.enableFastStorageAccessMessage,
        confirmLabel: isLegacy
            ? context.l10n.continueButton
            : context.l10n.openSettings,
      );
      if (grant && context.mounted) {
        await ref
            .read(appSettingsControllerProvider.notifier)
            .requestStoragePermission();
      }
    } else {
      final revoke = await showAppConfirmDialog(
        context,
        title: context.l10n.disableStorageAccessTitle,
        message: isLegacy
            ? context.l10n.disableStoragePermissionLegacyMessage
            : context.l10n.disableStorageAccessMessage,
        confirmLabel: context.l10n.openSettings,
      );
      if (revoke && context.mounted) {
        await ref
            .read(appSettingsControllerProvider.notifier)
            .requestStoragePermission(openSettings: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appSettingsControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              SectionCard(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.fastStorageAccessTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      state.hasAllStorageAccess
                          ? context.l10n.fastStorageAccessGrantedSubtitle
                          : context.l10n.fastStorageAccessNotGrantedSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.hasAllStorageAccess,
                    onChanged: (v) =>
                        _toggleStoragePermission(context, ref, state, v),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.keepVaultsRunningInBackgroundTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.keepVaultsRunningInBackgroundSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.settings.keepVaultsRunningInBackground,
                    onChanged: (v) async {
                      if (v) {
                        final granted = await ref
                            .read(vaultLifecycleApiProvider)
                            .requestNotificationPermission();
                        if (!granted && context.mounted) {
                          showAppSnackBar(
                            context,
                            message: context
                                .l10n
                                .notificationPermissionDeniedMessage,
                            tone: AppBannerTone.warning,
                          );
                        }
                      }
                      await ref
                          .read(vaultLifecycleApiProvider)
                          .syncBackgroundService(enabled: v);
                      await ref
                          .read(appSettingsControllerProvider.notifier)
                          .updateSettings(
                            (s) => s.copyWith(keepVaultsRunningInBackground: v),
                          );
                    },
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.usbAttachPromptTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.usbAttachPromptSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.usbAttachPromptEnabled,
                    onChanged: (v) async {
                      final ok = await ref
                          .read(appSettingsControllerProvider.notifier)
                          .setUsbAttachPromptEnabled(v);
                      if (!ok && context.mounted) {
                        showAppSnackBar(
                          context,
                          message:
                              context.l10n.usbAttachPromptUpdateErrorMessage,
                          tone: AppBannerTone.warning,
                        );
                      }
                    },
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.androidFileProviderTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.androidFileProviderSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.settings.defaultDocumentProvider,
                    onChanged: (v) => ref
                        .read(appSettingsControllerProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWith(defaultDocumentProvider: v),
                        ),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.shareSheetIntegrationTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.shareSheetIntegrationSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.shareTargetEnabled,
                    onChanged: (v) async {
                      final ok = await ref
                          .read(appSettingsControllerProvider.notifier)
                          .setShareTargetEnabled(v);
                      if (!ok && context.mounted) {
                        showAppSnackBar(
                          context,
                          message: context
                              .l10n
                              .shareSheetIntegrationUpdateErrorMessage,
                          tone: AppBannerTone.warning,
                        );
                      }
                    },
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.autoLockOnShareImportTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.autoLockOnShareImportSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.settings.autoLockOnShareImport,
                    onChanged: (v) => ref
                        .read(appSettingsControllerProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWith(autoLockOnShareImport: v),
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (embedded) {
      return Scaffold(body: body);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.sectionKeyStorageIntegration,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. VAULT & FILE HANDLING SUB-PAGE
// ─────────────────────────────────────────────────────────────────────────────

class FileHandlingSettingsScreen extends ConsumerWidget {
  final bool embedded;

  const FileHandlingSettingsScreen({super.key, this.embedded = false});

  String _labelForAssociation(BuildContext context, String value) {
    if (value == 'editor') return context.l10n.fileAssocInAppTextEditor;
    if (value == 'media') return context.l10n.fileAssocInAppMediaViewer;
    if (value == 'document') return context.l10n.fileAssocDocumentViewer;
    if (value == 'installer') return context.l10n.apkOpenPackageInstaller;
    if (value == 'archive') return context.l10n.apkOpenAsZip;
    if (value.startsWith('package:')) {
      return context.l10n.fileAssocAppPrefix(value.substring(8));
    }
    return context.l10n.fileAssocExternalApp;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appSettingsControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              SectionCard(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.autoOpenOnUnlockTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      state.settings.autoOpenOnUnlock
                          ? context.l10n.autoOpenOnUnlockActiveSubtitle
                          : context.l10n.autoOpenOnUnlockInactiveSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.settings.autoOpenOnUnlock,
                    onChanged: (v) => ref
                        .read(appSettingsControllerProvider.notifier)
                        .updateSettings((s) => s.copyWith(autoOpenOnUnlock: v)),
                  ),
                  OptionPickerTile<DeleteAfterImportMode>(
                    label: context.l10n.deleteAfterImportLabel,
                    value: state.settings.deleteAfterImportMode,
                    subtitle: state.settings.deleteAfterImportMode
                        .getLocalizedSubtitle(context.l10n),
                    options: DeleteAfterImportMode.values.map((mode) {
                      return SelectOption(
                        value: mode,
                        label: mode.getLocalizedLabel(context.l10n),
                        subtitle: mode.getLocalizedSubtitle(context.l10n),
                      );
                    }).toList(),
                    onChanged: (v) => ref
                        .read(appSettingsControllerProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWith(deleteAfterImportMode: v),
                        ),
                  ),
                  const GlobalThumbnailDefaultsTiles(),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.enableJsHtmlTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      state.settings.htmlEnableJavaScript
                          ? context.l10n.jsEnabledSubtitle
                          : context.l10n.jsDisabledSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.settings.htmlEnableJavaScript,
                    onChanged: (v) => ref
                        .read(appSettingsControllerProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWith(htmlEnableJavaScript: v),
                        ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          context.l10n.fileAssociationsHeader,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (state.settings.extensionPreferences.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: Text(
                            context.l10n.noFileAssociationsYet,
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.3,
                            ),
                          ),
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                          child: Text(
                            context.l10n.defaultActionsHeader,
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        ...state.settings.extensionPreferences.entries.map((
                          entry,
                        ) {
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            title: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer.withValues(
                                      alpha: 0.3,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '.${entry.key.toUpperCase()}',
                                    style: textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: cs.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _labelForAssociation(context, entry.value),
                                    style: textTheme.bodyMedium,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: cs.error,
                                size: 20,
                              ),
                              tooltip: context.l10n.removeAssociationTooltip,
                              onPressed: () {
                                final newPrefs = Map<String, String>.from(
                                  state.settings.extensionPreferences,
                                )..remove(entry.key);
                                ref
                                    .read(
                                      appSettingsControllerProvider.notifier,
                                    )
                                    .updateSettings(
                                      (s) => s.copyWith(
                                        extensionPreferences: newPrefs,
                                      ),
                                    );
                              },
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (embedded) {
      return Scaffold(body: body);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.sectionVaultFileHandling,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. APPEARANCE & DASHBOARD SUB-PAGE
// ─────────────────────────────────────────────────────────────────────────────

class AppearanceSettingsScreen extends ConsumerWidget {
  final bool embedded;

  const AppearanceSettingsScreen({super.key, this.embedded = false});

  String _getNativeLanguageName(Locale locale) {
    const nativeNames = {
      'ar': 'العربية',
      'de': 'Deutsch',
      'en': 'English',
      'es': 'Español',
      'fr': 'Français',
      'it': 'Italiano',
      'ja': '日本語',
      'ko': '한국어',
      'pt': 'Português',
      'uk': 'Українська',
      'zh': '中文',
    };
    final code = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    return nativeNames[code] ??
        nativeNames[locale.languageCode] ??
        code.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appSettingsControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Theme & Styling
              SectionHeader(context.l10n.appThemeLabel),
              SectionCard(
                children: [
                  OptionPickerTile<ThemeMode>(
                    label: context.l10n.appThemeLabel,
                    value: state.settings.themeMode,
                    options: [
                      SelectOption(
                        value: ThemeMode.system,
                        label: context.l10n.systemDefault,
                      ),
                      SelectOption(
                        value: ThemeMode.light,
                        label: context.l10n.lightTheme,
                      ),
                      SelectOption(
                        value: ThemeMode.dark,
                        label: context.l10n.darkTheme,
                      ),
                    ],
                    onChanged: (v) {
                      appThemeModeNotifier.value = v;
                      ref
                          .read(appSettingsControllerProvider.notifier)
                          .updateSettings((s) => s.copyWith(themeMode: v));
                    },
                  ),
                  if (state.androidSdkInt >= _kAndroidSdkS)
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      title: Text(
                        context.l10n.useMaterialYouTitle,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        context.l10n.useMaterialYouSubtitle,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      value: state.settings.useDynamicColor,
                      onChanged: (v) {
                        appUseDynamicColorNotifier.value = v;
                        ref
                            .read(appSettingsControllerProvider.notifier)
                            .updateSettings(
                              (s) => s.copyWith(useDynamicColor: v),
                            );
                      },
                    ),
                  ListTile(
                    leading: Icon(Icons.palette_outlined, color: cs.primary),
                    title: Text(
                      context.l10n.skinAppSkin,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      ref.watch(appSkinSettingsProvider).preset ==
                              AppSkinPreset.custom
                          ? ref
                                .watch(appSkinSettingsProvider)
                                .customAppSkin
                                .name
                          : appSkinPresetLabel(
                              context,
                              ref.watch(appSkinSettingsProvider).preset,
                            ),
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const AppSkinSettingsScreen()),
                      ),
                    ),
                  ),
                  // Language Selection
                  OptionPickerTile<String>(
                    label: context.l10n.languageLabel,
                    value:
                        (state.settings.languageCode != null &&
                            state.settings.languageCode!.isNotEmpty)
                        ? state.settings.languageCode!
                        : 'system',
                    options: [
                      SelectOption(
                        value: 'system',
                        label: context.l10n.systemDefault,
                      ),
                      ...AppLocalizations.supportedLocales
                          .map((locale) => locale.languageCode)
                          .toSet()
                          .map((code) {
                            final locale = AppLocalizations.supportedLocales
                                .firstWhere((l) => l.languageCode == code);
                            return SelectOption(
                              value: code,
                              label: _getNativeLanguageName(locale),
                            );
                          }),
                    ],
                    onChanged: (v) {
                      final isSystem = v == 'system' || v.trim().isEmpty;
                      final code = isSystem ? null : v;
                      appLocaleNotifier.value = code != null
                          ? Locale(code)
                          : null;
                      ref
                          .read(appSettingsControllerProvider.notifier)
                          .updateSettings(
                            (s) => s.copyWith(
                              languageCode: code,
                              clearLanguageCode: isSystem,
                            ),
                          );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Dashboard Layout & Cards
              SectionHeader(context.l10n.navBarVaultsLabel),
              SectionCard(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.showStorageLocationsTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.showStorageLocationsSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.settings.showStorageLocationsInDrawer,
                    onChanged: (v) => ref
                        .read(appSettingsControllerProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWith(showStorageLocationsInDrawer: v),
                        ),
                  ),
                  OptionPickerTile<ContainerSortMode>(
                    label: context.l10n.sortContainersByLabel,
                    value: state.settings.containerSortMode,
                    options: ContainerSortMode.values.map((mode) {
                      return SelectOption(
                        value: mode,
                        label: mode.getLocalizedLabel(context.l10n),
                      );
                    }).toList(),
                    onChanged: (v) => ref
                        .read(appSettingsControllerProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWith(containerSortMode: v),
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (embedded) {
      return Scaffold(body: body);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.sectionAppearanceInterface,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. BACKUP & DIAGNOSTICS SUB-PAGE
// ─────────────────────────────────────────────────────────────────────────────

class AdvancedSettingsScreen extends ConsumerWidget {
  final bool embedded;

  const AdvancedSettingsScreen({super.key, this.embedded = false});

  /// Asks whether the export should also carry the custom themes. Themes are
  /// optional because they can be large and are often shared on their own from
  /// App skin. Returns null when the dialog is dismissed.
  Future<bool?> _chooseExport(BuildContext context) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.exportSettingsTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(dialogContext.l10n.exportSettingsOnlyTitle),
            subtitle: Text(dialogContext.l10n.exportSettingsOnlySubtitle),
            onTap: () => Navigator.pop(dialogContext, false),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(dialogContext.l10n.exportSettingsWithSkinsTitle),
            subtitle: Text(dialogContext.l10n.exportSettingsWithSkinsSubtitle),
            onTap: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    ),
  );

  Future<void> _exportSettings(
    BuildContext context,
    WidgetRef ref,
    AppSettingsViewState state,
  ) async {
    if (state.backupBusy) return;
    final includeThemes = await _chooseExport(context);
    if (includeThemes == null || !context.mounted) return;
    ref.read(appSettingsControllerProvider.notifier).setExportBusy(true);
    try {
      final ok = await ref
          .read(sessionLockControllerProvider)
          .withLockSuppression(
            () => ref
                .read(settingsBackupServiceProvider)
                .exportToFile(includeThemes: includeThemes),
          );
      if (!context.mounted) return;
      if (ok) {
        showAppSnackBar(
          context,
          message: context.l10n.exportSettingsSuccessMessage,
          tone: AppBannerTone.success,
        );
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.exportSettingsErrorMessage,
          tone: AppBannerTone.error,
        );
      }
    } finally {
      if (context.mounted) {
        ref.read(appSettingsControllerProvider.notifier).setExportBusy(false);
      }
    }
  }

  Future<void> _importSettings(
    BuildContext context,
    WidgetRef ref,
    AppSettingsViewState state,
  ) async {
    if (state.backupBusy) return;
    ref.read(appSettingsControllerProvider.notifier).setImportBusy(true);
    ImportedSettingsBundle? bundle;
    try {
      bundle = await ref
          .read(sessionLockControllerProvider)
          .withLockSuppression(
            () => ref.read(settingsBackupServiceProvider).pickAndParseFile(),
          );
    } on InvalidSettingsBackupException {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.importSettingsInvalidFileMessage,
          tone: AppBannerTone.error,
        );
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.importSettingsInvalidFileMessage,
          tone: AppBannerTone.error,
        );
      }
    }
    if (!context.mounted) return;
    if (bundle == null) {
      ref.read(appSettingsControllerProvider.notifier).setImportBusy(false);
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.importSettingsConfirmTitle,
      message: bundle.hasThemes
          ? context.l10n.importSettingsConfirmFullSkinsMessage
          : bundle.restoresInterface
          ? context.l10n.importSettingsConfirmFullMessage
          : context.l10n.importSettingsConfirmMessage,
      confirmLabel: context.l10n.importSettingsTitle,
      isDestructive: true,
    );
    if (!context.mounted) return;
    if (!confirmed) {
      ref.read(appSettingsControllerProvider.notifier).setImportBusy(false);
      return;
    }
    try {
      final applied = await ref
          .read(settingsBackupServiceProvider)
          .applyImportedBundle(bundle);
      if (!context.mounted) return;
      // Push what was actually persisted (this file only carries the
      // configuration half), not the partial settings parsed from it.
      await refreshLiveSettings(ref, applied.settings, applied.toolbarConfig);

      if (bundle.shareTargetEnabled != null) {
        await ref
            .read(appSettingsControllerProvider.notifier)
            .setShareTargetEnabled(bundle.shareTargetEnabled!);
      }
      if (bundle.usbAttachPromptEnabled != null) {
        await ref
            .read(appSettingsControllerProvider.notifier)
            .setUsbAttachPromptEnabled(bundle.usbAttachPromptEnabled!);
      }
      showAppSnackBar(
        context,
        message: context.l10n.importSettingsSuccessMessage,
        tone: AppBannerTone.success,
      );
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.importSettingsInvalidFileMessage,
          tone: AppBannerTone.error,
        );
      }
    } finally {
      if (context.mounted) {
        ref.read(appSettingsControllerProvider.notifier).setImportBusy(false);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appSettingsControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Backup & Restore
              SectionHeader(context.l10n.sectionBackupRestore),
              SectionCard(
                children: [
                  ListTile(
                    title: Text(
                      context.l10n.exportSettingsTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.exportSettingsSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: state.exportBusy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation(cs.primary),
                            ),
                          )
                        : null,
                    enabled: !state.backupBusy,
                    onTap: () => _exportSettings(context, ref, state),
                  ),
                  ListTile(
                    title: Text(
                      context.l10n.importSettingsTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.importSettingsSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: state.importBusy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation(cs.primary),
                            ),
                          )
                        : null,
                    enabled: !state.backupBusy,
                    onTap: () => _importSettings(context, ref, state),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Debug & Diagnostics
              SectionHeader(context.l10n.sectionDebug),
              SectionCard(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      context.l10n.debugLoggingTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.debugLoggingSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: state.settings.debugLoggingEnabled,
                    onChanged: (val) {
                      VeLog.enabled = val;
                      ref
                          .read(appSettingsControllerProvider.notifier)
                          .updateSettings(
                            (s) => s.copyWith(debugLoggingEnabled: val),
                          );
                    },
                  ),
                  ListTile(
                    title: Text(
                      context.l10n.logcatTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.logcatSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const LogcatScreen())),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (embedded) {
      return Scaffold(body: body);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${context.l10n.sectionBackupRestore} & ${context.l10n.sectionDebug}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: body,
    );
  }
}
