// Decoy mode's main screen: the exact same file-manager UI used to browse
// an unlocked vault (toolbar, settings, bookmarks, thumbnails, text/image
// editor -- FileBrowserScreen and everything under features/browser/),
// pointed at real device storage instead. See local_file_io_backend.dart
// and the local-storage branches added throughout vault_file_io_api.dart
// for how the same screen serves both without knowing the difference.
//
// Replaces the old, separately-built DecoyLocalExplorerScreen (still
// present under this folder, now unused) as the "Files" content inside
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_empty_state.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_share_import_flow.dart';
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

  // Android Share Sheet integration while Mask Mode's decoy identity is
  // active (see LocalIncomingShareBridge.kt/ShareIntentHandlers.kt and
  // decoy_share_import_flow.dart) -- the decoy counterpart of MainShell's
  // identically-shaped _handlingShareRequest guard, which the comment on
  // its initState explains in full: guards the narrow race where a share
  // request could otherwise be picked up by both the push listener below
  // and a pending-check pull and get handled twice.
  bool _handlingLocalShareRequest = false;

  // True for the stretch between knowing a share is waiting and the
  // picker actually taking over -- see _checkAccessAndResolveRoot's use
  // of this to skip mounting FileBrowserScreen (and therefore starting
  // its own listing of the same root the picker is about to list a
  // second time) for a view the person is about to never actually see.
  bool _deferBrowserForShare = false;
  int _shareSeq = 0;
  Route<dynamic>? _activeShareRoute;

  // Kicked off in initState, in parallel with _checkAccessAndResolveRoot's
  // own await chain below rather than after it -- this doesn't depend on
  // storage access or the resolved root, so there's no reason to wait for
  // either just to ask this one independent question. Consumed once, by
  // whichever of that chain's two awaits finishes second; every
  // subsequent resolution (resume, access just granted) asks fresh
  // instead, since a request arriving later shouldn't be answered from a
  // stale snapshot taken back at cold start.
  Future<IncomingShareRequest?>? _earlyPendingShareCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    disguiseModeApi.setLocalIncomingShareRequestListener(_onLocalIncomingShareRequest);
    _earlyPendingShareCheck = disguiseModeApi.checkPendingLocalShareRequest();
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
    disguiseModeApi.setLocalIncomingShareRequestListener(null);
    super.dispose();
  }

  Future<void> _checkAccessAndResolveRoot() async {
    final pendingShareFuture = _earlyPendingShareCheck != null
        ? _earlyPendingShareCheck!
        : (_hasAccess
            ? Future<IncomingShareRequest?>.value(null)
            : disguiseModeApi.checkPendingLocalShareRequest());
    _earlyPendingShareCheck = null;

    final results = await Future.wait([
      _repo.primaryRoot(),
      pendingShareFuture,
      ref.read(vaultLifecycleApiProvider).hasAllFilesAccess(),
    ]);
    if (!mounted) return;

    final root = results[0] as Directory;
    final pendingShare = results[1] as IncomingShareRequest?;
    final hasAccess = results[2] as bool;

    if (!hasAccess) {
      setState(() {
        _checkingAccess = false;
        _hasAccess = false;
        _container = null;
        _deferBrowserForShare = false;
      });
      return;
    }

    final container = buildLocalStorageContainer(
      rootPath: root.path,
      displayName: context.l10n.filesTabLabel,
    );

    setState(() {
      _checkingAccess = false;
      _hasAccess = true;
      _container = container;
      _deferBrowserForShare = pendingShare != null;
    });
    if (pendingShare != null) {
      _onLocalIncomingShareRequest(pendingShare);
    }
  }

  void _onLocalIncomingShareRequest(IncomingShareRequest request) {
    final container = _container;
    if (!mounted || container == null) return;
    final mySeq = ++_shareSeq;
    if (_activeShareRoute != null && _activeShareRoute!.isActive) {
      _activeShareRoute!.navigator?.removeRoute(_activeShareRoute!);
      _activeShareRoute = null;
    }
    _handlingLocalShareRequest = true;
    presentDecoyIncomingShareImport(
      context,
      request,
      container,
      onRouteCreated: (route) => _activeShareRoute = route,
      isCurrent: () => mounted && _shareSeq == mySeq,
    ).whenComplete(() {
      if (!mounted) return;
      if (_shareSeq == mySeq) {
        _handlingLocalShareRequest = false;
        _activeShareRoute = null;
        // The person is back looking at this screen either way (finished,
        // cancelled, or redirected into the vault and returned) -- resume
        // the normal browser view rather than the deferred spinner.
        setState(() => _deferBrowserForShare = false);
      }
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

    if (_deferBrowserForShare) {
      return Scaffold(
        appBar: AppBar(
          title: HiddenVaultTrigger(child: Text(context.l10n.filesTabLabel)),
        ),
        body: const Center(child: CircularProgressIndicator()),
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