// Decoy mode's main screen: the exact same file-manager UI used to browse
// an unlocked vault (toolbar, settings, bookmarks, thumbnails, text/image
// editor -- FileBrowserScreen and everything under features/browser/),
// pointed at real device storage instead. See local_file_io_backend.dart
// and the local-storage branches added throughout vault_file_io_api.dart
// for how the same screen serves both without knowing the difference.
//
// Replaces the old, separately-built DecoyLocalExplorerScreen (still
// present under this folder, now unused) as the "Files" content inside
// DecoyArchiveExplorerScreen.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_empty_state.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';
import 'package:vaultexplorer/features/decoy/widgets/hidden_vault_trigger.dart';

class DecoyFileManagerScreen extends ConsumerStatefulWidget {
  const DecoyFileManagerScreen({super.key});

  @override
  ConsumerState<DecoyFileManagerScreen> createState() => _DecoyFileManagerScreenState();
}

class _DecoyFileManagerScreenState extends ConsumerState<DecoyFileManagerScreen>
    with WidgetsBindingObserver {
  static const _repo = DecoyLocalRepository();
  bool _checkingAccess = true;
  bool _hasAccess = false;
  MountedContainer? _container;
  Future<void>? _accessCheckFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _accessCheckFuture ??= _checkAccessAndResolveRoot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccessAndResolveRoot();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkAccessAndResolveRoot() async {
    final hasAccess = await ref.read(vaultLifecycleApiProvider).hasAllFilesAccess();
    if (!mounted) return;
    if (!hasAccess) {
      setState(() {
        _checkingAccess = false;
        _hasAccess = false;
        _container = null;
      });
      return;
    }

    final root = await _repo.primaryRoot();
    if (!mounted) return;
    setState(() {
      _checkingAccess = false;
      _hasAccess = true;
      _container = buildLocalStorageContainer(
        rootPath: root.path,
        displayName: context.l10n.filesTabLabel,
      );
    });
  }

  Future<void> _requestAccess() async {
    await ref.read(vaultLifecycleApiProvider).requestAllFilesAccess(openSettings: true);
    if (!mounted) return;
    await _checkAccessAndResolveRoot();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccess) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasAccess) {
      return Scaffold(
        appBar: AppBar(
          title: HiddenVaultTrigger(child: Text(context.l10n.filesTabLabel)),
        ),
        body: AppEmptyState(
          icon: Icons.folder_off_outlined,
          title: context.l10n.archiveExplorerPermissionTitle,
          message: context.l10n.filesPermissionMessage,
          actionLabel: context.l10n.archiveExplorerGrantAccess,
          actionIcon: Icons.lock_open_rounded,
          onAction: _requestAccess,
        ),
      );
    }

    final container = _container;
    if (container == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return FileBrowserScreen(
      container: container,
      // Always the same fixed pseudo-container -- there's no unlock/lock
      // session for real device storage to re-resolve after.
      resolveContainer: (volId) => volId == kDecoyLocalVolId ? container : null,
      // No inactivity auto-lock timer to reset in decoy mode.
      onUserActivity: () {},
      // This screen IS the decoy's root/home content, with no dashboard
      // route beneath it to return to.
      showBackButton: false,
      // Preserves the same long-press-the-title gesture the old bespoke
      // decoy explorer used to reach the real vault.
      wrapAppBarTitle: (title) => HiddenVaultTrigger(child: title),
    );
  }
}
