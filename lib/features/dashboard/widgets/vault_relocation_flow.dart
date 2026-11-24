import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/data/services/vault_relocation_providers.dart';
import 'package:vaultexplorer/data/services/vault_relocation_service.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Whether [record] can be moved between a picked location and app storage at all: app storage is an
/// Android feature, and a USB drive or composite vault has no single file or folder to copy.
bool canRelocateVault(ContainerRecord record) =>
    Platform.isAndroid && !record.isUsbSource && !record.isCompositeSource;

bool _isFolderVault(String containerFormat) =>
    ContainerFormat.isCryptomatorWire(containerFormat) ||
    ContainerFormat.isGocryptfsWire(containerFormat) ||
    ContainerFormat.isCryfsWire(containerFormat);

/// The user-facing message for a failed move.
String relocationFailureMessage(AppLocalizations l10n, RelocationException e) {
  switch (e.reason) {
    case RelocationFailure.vaultUnlocked:
      return l10n.relocateErrorUnlocked;
    case RelocationFailure.unsupportedSource:
      return l10n.relocateErrorUnsupported;
    case RelocationFailure.splitContainer:
      return l10n.relocateErrorSplit;
    case RelocationFailure.notAVaultFolder:
      return l10n.relocateErrorNotVaultFolder;
    case RelocationFailure.destinationNotEmpty:
      return l10n.selectEmptyDestinationFolderFirst;
    case RelocationFailure.insufficientSpace:
      final needed = e.neededBytes;
      final available = e.availableBytes;
      if (needed != null && available != null) {
        return l10n.insufficientSpaceForContainer(
          formatBytes(needed),
          formatBytes(available),
        );
      }
      return l10n.relocateErrorGeneric(e.message ?? '');
    case RelocationFailure.verifyFailed:
      return l10n.relocateErrorVerifyFailed;
    case RelocationFailure.recordSwitchFailed:
      return l10n.relocateErrorSwitchFailed;
    case RelocationFailure.cancelled:
    case RelocationFailure.alreadyInAppStorage:
    case RelocationFailure.notInAppStorage:
    case RelocationFailure.sourceMissing:
    case RelocationFailure.noPicker:
    case RelocationFailure.busy:
    case RelocationFailure.io:
      return l10n.relocateErrorGeneric(e.message ?? '');
  }
}

/// Moves [record]'s vault into app storage ([toAppStorage]) or back out to a location the user picks.
///
/// Asks for confirmation (with the choice of deleting the original), shows progress with a cancel button
/// while the copy is made and verified, then switches the vault over. Returns true if the vault was moved.
/// On success the dashboard list is updated; the caller should close any screen that still holds the
/// old location (the settings screen does).
Future<bool> runVaultRelocation(
  BuildContext context,
  WidgetRef ref, {
  required ContainerRecord record,
  required bool toAppStorage,
}) async {
  final l10n = context.l10n;
  final service = ref.read(vaultRelocationServiceProvider);
  final repository = ref.read(containerRepositoryProvider);
  final dashboard = ref.read(vaultDashboardControllerProvider.notifier);
  final lock = ref.read(sessionLockControllerProvider);

  if (ref.read(vaultDashboardControllerProvider).mounted.any((m) => m.uri == record.uri)) {
    showAppSnackBar(context, message: l10n.relocateErrorUnlocked, tone: AppBannerTone.warning);
    return false;
  }

  final deleteOriginal = await showDialog<bool>(
    context: context,
    builder: (_) => _RelocationConfirmDialog(toAppStorage: toAppStorage),
  );
  if (deleteOriginal == null || !context.mounted) return false;

  final progress = ValueNotifier<_RelocationProgress>(const _RelocationProgress());
  var dialogOpen = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: _RelocationProgressDialog(
          title: toAppStorage ? l10n.relocateToAppStorageTitle : l10n.relocateFromAppStorageTitle,
          progress: progress,
          onCancel: () => unawaited(service.cancel()),
        ),
      ),
    ),
  );

  void closeProgress() {
    if (!dialogOpen) return;
    dialogOpen = false;
    if (context.mounted) Navigator.of(context).pop();
  }

  RelocationOutcome? outcome;
  RelocationException? failure;
  try {
    outcome = await lock.withLockSuppression(() {
      void onPhase(RelocationPhase p) =>
          progress.value = progress.value.copyWith(phase: p);
      void onBytes(int done, int total) =>
          progress.value = progress.value.copyWith(done: done, total: total);
      return toAppStorage
          ? service.moveToAppStorage(
              uri: record.uri,
              displayName: record.label,
              isFolderVault: _isFolderVault(record.containerFormat),
              deleteOriginal: deleteOriginal,
              onPhase: onPhase,
              onProgress: onBytes,
            )
          : service.moveOutOfAppStorage(
              uri: record.uri,
              displayName: record.label,
              isFolderVault: _isFolderVault(record.containerFormat),
              deleteOriginal: deleteOriginal,
              onPhase: onPhase,
              onProgress: onBytes,
            );
    });
  } on RelocationException catch (e) {
    failure = e;
  } catch (e) {
    failure = RelocationException(RelocationFailure.io, message: '$e');
  } finally {
    closeProgress();
  }

  if (failure != null) {
    if (failure.reason != RelocationFailure.cancelled && context.mounted) {
      showAppSnackBar(
        context,
        message: relocationFailureMessage(l10n, failure),
        tone: AppBannerTone.error,
      );
    }
    return false;
  }

  final done = outcome;
  if (done == null || !done.completed) return false; // the destination picker was dismissed

  // The repository already holds the new registration; bring the visible list in line with it.
  final moved = (await repository.loadAll())[done.newUri];
  if (moved != null) dashboard.replaceVaultUri(record.uri, moved);

  if (!context.mounted) return true;
  final notes = <String>[
    if (done.biometricsDropped) l10n.relocateNoteBiometricsDropped,
    if (done.automationReset) l10n.relocateNoteAutomationReset,
    if (done.originalLeftBehind) l10n.relocateNoteOriginalLeftBehind,
  ];
  final message = toAppStorage ? l10n.relocatedToAppStorage : l10n.relocatedFromAppStorage;
  if (notes.isEmpty) {
    showAppSnackBar(context, message: message, tone: AppBannerTone.success);
  } else {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(message),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(n),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.done),
          ),
        ],
      ),
    );
  }
  return true;
}

/// "Remove" for a vault that lives in app storage. Forgetting the entry would strand the files where
/// nothing can reach them, so removing it deletes the vault, after asking, and offers to move it out first.
Future<void> removeAppStorageVault(
  BuildContext context,
  WidgetRef ref, {
  required ContainerRecord record,
}) async {
  final l10n = context.l10n;
  final storage = ref.read(vaultStorageApiProvider);
  final dashboard = ref.read(vaultDashboardControllerProvider.notifier);

  if (ref.read(vaultDashboardControllerProvider).mounted.any((m) => m.uri == record.uri)) {
    showAppSnackBar(context, message: l10n.lockBeforeRemovingWarning, tone: AppBannerTone.warning);
    return;
  }

  final choice = await showDialog<_DeleteChoice>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(l10n.deleteAppStorageVaultTitle),
        content: Text(l10n.deleteAppStorageVaultBody(record.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DeleteChoice.cancel),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DeleteChoice.moveOut),
            child: Text(l10n.deleteAppStorageVaultMoveOut),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DeleteChoice.delete),
            child: Text(l10n.delete, style: TextStyle(color: cs.error)),
          ),
        ],
      );
    },
  );
  if (choice == null || choice == _DeleteChoice.cancel || !context.mounted) return;

  if (choice == _DeleteChoice.moveOut) {
    await runVaultRelocation(context, ref, record: record, toAppStorage: false);
    return;
  }

  var deleted = false;
  try {
    deleted = await storage.deleteAppStorageVault(record.uri);
  } on PlatformException catch (e) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: e.code == 'VAULT_UNLOCKED'
            ? l10n.lockBeforeRemovingWarning
            : l10n.deleteAppStorageVaultFailed,
        tone: AppBannerTone.error,
      );
    }
    return;
  }
  if (!deleted) {
    if (context.mounted) {
      showAppSnackBar(context, message: l10n.deleteAppStorageVaultFailed, tone: AppBannerTone.error);
    }
    return;
  }
  // The files are gone; only now forget the entry (no undo: there is nothing left to restore).
  await dashboard.removeVaultNow(record.uri);
}

enum _DeleteChoice { cancel, moveOut, delete }

class _RelocationProgress {
  const _RelocationProgress({this.phase = RelocationPhase.copying, this.done = 0, this.total = 0});
  final RelocationPhase phase;
  final int done;
  final int total;

  /// 0..1, or null while the size is not known yet. Copy and verify each count once, so this is
  /// the overall progress of the move, not of one pass.
  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);

  _RelocationProgress copyWith({RelocationPhase? phase, int? done, int? total}) => _RelocationProgress(
    phase: phase ?? this.phase,
    done: done ?? this.done,
    total: total ?? this.total,
  );
}

class _RelocationConfirmDialog extends StatefulWidget {
  const _RelocationConfirmDialog({required this.toAppStorage});
  final bool toAppStorage;

  @override
  State<_RelocationConfirmDialog> createState() => _RelocationConfirmDialogState();
}

class _RelocationConfirmDialogState extends State<_RelocationConfirmDialog> {
  bool _deleteOriginal = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final toApp = widget.toAppStorage;
    return AlertDialog(
      title: Text(toApp ? l10n.relocateToAppStorageTitle : l10n.relocateFromAppStorageTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(toApp ? l10n.relocateToAppStorageBody : l10n.relocateFromAppStorageBody),
            if (toApp) ...[
              const SizedBox(height: 12),
              Text(l10n.appStorageRiskNote, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _deleteOriginal,
              onChanged: (v) => setState(() => _deleteOriginal = v ?? true),
              title: Text(l10n.relocateDeleteOriginal),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _deleteOriginal),
          child: Text(l10n.relocateMoveButton),
        ),
      ],
    );
  }
}

class _RelocationProgressDialog extends StatelessWidget {
  const _RelocationProgressDialog({
    required this.title,
    required this.progress,
    required this.onCancel,
  });

  final String title;
  final ValueListenable<_RelocationProgress> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<_RelocationProgress>(
      valueListenable: progress,
      builder: (context, p, _) {
        final fraction = p.fraction;
        final label = switch (p.phase) {
          RelocationPhase.copying => l10n.relocatePhaseCopying,
          RelocationPhase.switching => l10n.relocatePhaseSwitching,
          RelocationPhase.finishing => l10n.relocatePhaseFinishing,
        };
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: p.phase == RelocationPhase.copying ? fraction : null,
              ),
              if (p.phase == RelocationPhase.copying && fraction != null) ...[
                const SizedBox(height: 8),
                Text('${(fraction * 100).floor()}%'),
              ],
            ],
          ),
          actions: [
            // Once the copy is verified the vault is being switched over, which must not be interrupted.
            if (p.phase == RelocationPhase.copying)
              TextButton(onPressed: onCancel, child: Text(l10n.cancel)),
          ],
        );
      },
    );
  }
}
