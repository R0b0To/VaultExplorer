import 'dart:ui';

import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/sync/services/sync_status.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Shows sync progress in the "keep vaults running" notification.
///
/// The notification has a single progress slot, shared with file transfers.
/// Transfers own it while any is running (their service pushes its own
/// state, and would overwrite this), so sync only writes to it when no
/// transfer is active, and only clears it if it was the one showing.
///
/// Wording is deliberately generic -- counts only, never a folder or file
/// name: with Mask Mode on, that text is what the notification shows under
/// the disguised app identity.
///
/// There is no BuildContext here (syncs start on unlock, in the
/// background), so the strings are resolved from the saved language
/// setting, falling back to the device language.
class SyncNotificationBridge {
  static const Duration _minPushGap = Duration(milliseconds: 800);

  final VaultLifecycleApi _lifecycle;
  final FileOperationService _fileOps;
  final AppSettingsService _settings;

  AppLocalizations? _l10n;
  DateTime? _lastPush;
  bool _showing = false;

  SyncNotificationBridge({
    required VaultLifecycleApi lifecycle,
    required FileOperationService fileOps,
    required AppSettingsService settings,
  }) : _lifecycle = lifecycle,
       _fileOps = fileOps,
       _settings = settings;

  Future<void> update(SyncStatus status) async {
    final fraction = status.fraction;
    if (!status.running || fraction == null) {
      await clear();
      return;
    }
    if (_fileOps.activeOperations.isNotEmpty) return;

    final now = DateTime.now();
    final last = _lastPush;
    if (last != null && now.difference(last) < _minPushGap) return;
    _lastPush = now;

    final l10n = _l10n ??= await _resolveL10n();
    _showing = true;
    await _lifecycle.updateBackgroundServiceProgress(
      hasActive: true,
      title: l10n.autoSyncNotificationTitle,
      text: l10n.autoSyncNotificationProgress(
        status.doneActions,
        status.totalActions,
      ),
      progress: (fraction * 1000).round().clamp(0, 1000),
      max: 1000,
    );
  }

  Future<void> clear() async {
    _lastPush = null;
    _l10n = null;
    if (!_showing) return;
    _showing = false;
    if (_fileOps.activeOperations.isNotEmpty) return; // they own it now
    await _lifecycle.updateBackgroundServiceProgress(hasActive: false);
  }

  Future<AppLocalizations> _resolveL10n() async {
    String? code;
    try {
      code = (await _settings.loadSettings()).languageCode;
    } catch (_) {
      code = null;
    }
    final Locale wanted = (code != null && code.isNotEmpty)
        ? Locale(code)
        : PlatformDispatcher.instance.locale;
    // Same rule the app's localeResolutionCallback uses.
    final match = AppLocalizations.supportedLocales.firstWhere(
      (l) => l.languageCode == wanted.languageCode,
      orElse: () => const Locale('en'),
    );
    return lookupAppLocalizations(match);
  }
}
