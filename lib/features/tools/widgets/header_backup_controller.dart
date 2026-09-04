import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/features/tools/services/container_tool_service.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'header_backup_controller.g.dart';

enum HeaderBackupMode { export, restore }

class HeaderBackupState {
  final HeaderBackupMode mode;

  /// [UnmountedFileTarget] or [FolderVaultTarget] only -- Header Backup
  /// doesn't operate on a [MountedVolumeTarget] (see this tool's doc
  /// comment on [ContainerToolService.exportContainerHeader]).
  final RepairTarget? target;

  /// Export flow only: set after a pre-export diagnosis of a
  /// [UnmountedFileTarget] comes back unhealthy, so the sheet can show a
  /// "back up anyway?" confirmation before [confirmExportDespiteUnhealthy]
  /// actually runs the export. Folder vault targets skip this gate
  /// entirely (see [runExport]'s doc comment).
  final RepairDiagnosis? unhealthyDiagnosis;

  final bool busy;
  final String? error;
  final List<String> logLines;

  /// Export flow: the freshly exported backup, ready for [HeaderBackupSheet]
  /// to offer a save location for.
  final HeaderBackupFile? exportedBackup;
  final bool exportSaved;

  /// Restore flow: the backup file the person picked, already structurally
  /// validated and checksum-verified by [ContainerToolService.loadHeaderBackupFile].
  final HeaderBackupFile? loadedBackup;
  final bool restoreSucceeded;

  const HeaderBackupState({
    this.mode = HeaderBackupMode.export,
    this.target,
    this.unhealthyDiagnosis,
    this.busy = false,
    this.error,
    this.logLines = const [],
    this.exportedBackup,
    this.exportSaved = false,
    this.loadedBackup,
    this.restoreSucceeded = false,
  });

  HeaderBackupState _copy({
    HeaderBackupMode? mode,
    RepairTarget? target,
    bool clearTarget = false,
    RepairDiagnosis? unhealthyDiagnosis,
    bool clearUnhealthyDiagnosis = false,
    bool? busy,
    String? error,
    bool clearError = false,
    List<String>? logLines,
    HeaderBackupFile? exportedBackup,
    bool clearExportedBackup = false,
    bool? exportSaved,
    HeaderBackupFile? loadedBackup,
    bool clearLoadedBackup = false,
    bool? restoreSucceeded,
  }) => HeaderBackupState(
    mode: mode ?? this.mode,
    target: clearTarget ? null : (target ?? this.target),
    unhealthyDiagnosis: clearUnhealthyDiagnosis ? null : (unhealthyDiagnosis ?? this.unhealthyDiagnosis),
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    logLines: logLines ?? this.logLines,
    exportedBackup: clearExportedBackup ? null : (exportedBackup ?? this.exportedBackup),
    exportSaved: exportSaved ?? this.exportSaved,
    loadedBackup: clearLoadedBackup ? null : (loadedBackup ?? this.loadedBackup),
    restoreSucceeded: restoreSucceeded ?? this.restoreSucceeded,
  );
}

@riverpod
class HeaderBackup extends _$HeaderBackup {
  @override
  HeaderBackupState build() => const HeaderBackupState();

  void appendLogLine(String message) {
    final newLogs = List<String>.from(state.logLines)..add(message);
    state = state._copy(logLines: newLogs);
  }

  void setMode(HeaderBackupMode mode) {
    state = HeaderBackupState(mode: mode);
  }

  void changeTarget() {
    state = state._copy(
      clearTarget: true,
      clearUnhealthyDiagnosis: true,
      clearError: true,
      logLines: const [],
      clearExportedBackup: true,
      exportSaved: false,
      restoreSucceeded: false,
    );
  }

  Future<void> pickUnmountedFile() async {
    final picked = await ref.read(vaultLifecycleApiProvider).pickContainer();
    if (picked == null || !ref.mounted) return;
    changeTarget();
    state = state._copy(target: UnmountedFileTarget(uri: picked.uri, displayName: picked.displayName));
  }

  Future<void> pickFolderVault() async {
    try {
      final picked = await ref.read(containerToolServiceProvider).pickFolderVaultForRepair();
      if (picked == null || !ref.mounted) return;
      changeTarget();
      state = state._copy(target: picked);
    } on FolderVaultInvalidException catch (e) {
      if (ref.mounted) state = state._copy(error: '$e');
    }
  }

  /// Runs the export. For a [UnmountedFileTarget], diagnoses it first --
  /// backing up an already-corrupted header defeats the tool's purpose --
  /// and if that comes back unhealthy, stops short and sets
  /// [HeaderBackupState.unhealthyDiagnosis] instead, waiting for
  /// [confirmExportDespiteUnhealthy]. A [FolderVaultTarget] skips this gate:
  /// there's no cheap non-destructive diagnosis for a folder vault (the
  /// real check, [ContainerToolService.checkFolderVault], is a full scan
  /// that optionally wants a password) so this just exports directly --
  /// [exportFolderVaultConfig] already fails on its own if the config file
  /// isn't there to read.
  Future<void> runExport(AppLocalizations l10n) async {
    final target = state.target;
    if (target == null) return;
    state = state._copy(
      busy: true,
      clearError: true,
      clearUnhealthyDiagnosis: true,
      logLines: const [],
    );
    if (target is UnmountedFileTarget) {
      try {
        final diagnosis = await ref.read(containerToolServiceProvider).diagnoseTarget(target);
        if (!ref.mounted) return;
        if (diagnosis != RepairDiagnosis.healthy) {
          state = state._copy(busy: false, unhealthyDiagnosis: diagnosis);
          return;
        }
      } on UnimplementedError {
        if (ref.mounted) state = state._copy(busy: false, error: l10n.toolNotImplementedYetMessage);
        return;
      } catch (e) {
        if (ref.mounted) state = state._copy(busy: false, error: '$e');
        return;
      }
    }
    await _performExport(target);
  }

  Future<void> confirmExportDespiteUnhealthy() async {
    final target = state.target;
    if (target == null) return;
    state = state._copy(busy: true, clearUnhealthyDiagnosis: true, clearError: true);
    await _performExport(target);
  }

  Future<void> _performExport(RepairTarget target) async {
    try {
      final backup = switch (target) {
        UnmountedFileTarget() => await ref
            .read(containerToolServiceProvider)
            .exportContainerHeader(target, onLogLine: appendLogLine),
        FolderVaultTarget() => await ref.read(containerToolServiceProvider).exportFolderVaultConfig(target),
        MountedVolumeTarget() => throw StateError('Header Backup does not operate on a mounted volume.'),
      };
      if (!ref.mounted) return;
      state = state._copy(busy: false, exportedBackup: backup);
    } catch (e) {
      if (ref.mounted) state = state._copy(busy: false, error: '$e');
    }
  }

  Future<void> saveExportedBackup({
    required String? destinationPath,
    required String? destinationTreeUri,
    required String fileName,
  }) async {
    final backup = state.exportedBackup;
    if (backup == null) return;
    state = state._copy(busy: true, clearError: true);
    try {
      await ref
          .read(containerToolServiceProvider)
          .saveHeaderBackupFile(
            backup,
            destinationPath: destinationPath,
            destinationTreeUri: destinationTreeUri,
            fileName: fileName,
          );
      if (!ref.mounted) return;
      state = state._copy(busy: false, exportSaved: true);
    } catch (e) {
      if (ref.mounted) state = state._copy(busy: false, error: '$e');
    }
  }

  /// Reuses [VaultLifecycleApi.pickKeyfiles] -- the same generic
  /// multi-select `ACTION_OPEN_DOCUMENT` picker the Keyfile & Passphrase
  /// Generator and standalone Encrypt/Decrypt tools already use for "pick
  /// a file from anywhere" -- taking the first (only) pick, rather than
  /// adding a near-duplicate single-file native picker for this one case.
  Future<void> pickBackupFile() async {
    final picked = await ref.read(vaultLifecycleApiProvider).pickKeyfiles();
    if (picked.isEmpty || !ref.mounted) return;
    state = state._copy(busy: true, clearError: true, clearLoadedBackup: true, restoreSucceeded: false);
    try {
      final backup = await ref.read(containerToolServiceProvider).loadHeaderBackupFile(picked.first.uri);
      if (!ref.mounted) return;
      state = state._copy(busy: false, loadedBackup: backup);
    } catch (e) {
      if (ref.mounted) state = state._copy(busy: false, error: '$e');
    }
  }

  Future<void> runRestore({
    String? password,
    required Future<String?> Function() onPromptPassword,
    required AppLocalizations l10n,
  }) async {
    final target = state.target;
    final backup = state.loadedBackup;
    if (target == null || backup == null) return;
    state = state._copy(logLines: const []);
    await _executeRestore(
      target: target,
      backup: backup,
      password: password,
      onPromptPassword: onPromptPassword,
      l10n: l10n,
    );
  }

  Future<void> _executeRestore({
    required RepairTarget target,
    required HeaderBackupFile backup,
    String? password,
    required Future<String?> Function() onPromptPassword,
    required AppLocalizations l10n,
  }) async {
    state = state._copy(busy: true, clearError: true);
    try {
      switch (target) {
        case UnmountedFileTarget():
          final ok = await ref
              .read(containerToolServiceProvider)
              .restoreContainerHeader(target, backup, password: password, onLogLine: appendLogLine);
          if (!ref.mounted) return;
          state = state._copy(busy: false, restoreSucceeded: ok);
        case FolderVaultTarget():
          await ref.read(containerToolServiceProvider).restoreFolderVaultConfig(target, backup);
          if (!ref.mounted) return;
          state = state._copy(busy: false, restoreSucceeded: true);
        case MountedVolumeTarget():
          throw StateError('Header Backup does not operate on a mounted volume.');
      }
    } on RepairPasswordRequiredException {
      if (!ref.mounted) return;
      state = state._copy(busy: false);
      final entered = await onPromptPassword();
      if (!ref.mounted || entered == null || entered.isEmpty) return;
      await _executeRestore(
        target: target,
        backup: backup,
        password: entered,
        onPromptPassword: onPromptPassword,
        l10n: l10n,
      );
    } on UnimplementedError {
      if (ref.mounted) state = state._copy(busy: false, error: l10n.toolNotImplementedYetMessage);
    } catch (e) {
      if (ref.mounted) state = state._copy(busy: false, error: '$e');
    }
  }
}
