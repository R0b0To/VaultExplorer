import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'container_repair_controller.g.dart';

class ContainerRepairState {
  final RepairTarget? target;
  final bool diagnosing;
  final RepairDiagnosis? diagnosis;
  final bool actionRunning;
  final bool? actionSucceeded;
  final String? error;
  final List<String> logLines;
  final bool folderVaultChecking;
  final FolderVaultCheckReport? folderVaultReport;
  final bool folderVaultRepairing;
  final FolderVaultRepairReport? folderVaultRepairReport;

  bool get isWorking =>
      diagnosing || actionRunning || folderVaultChecking || folderVaultRepairing;

  const ContainerRepairState({
    this.target,
    this.diagnosing = false,
    this.diagnosis,
    this.actionRunning = false,
    this.actionSucceeded,
    this.error,
    this.logLines = const [],
    this.folderVaultChecking = false,
    this.folderVaultReport,
    this.folderVaultRepairing = false,
    this.folderVaultRepairReport,
  });

  ContainerRepairState _copy({
    RepairTarget? target,
    bool clearTarget = false,
    bool? diagnosing,
    RepairDiagnosis? diagnosis,
    bool clearDiagnosis = false,
    bool? actionRunning,
    bool? actionSucceeded,
    bool clearActionSucceeded = false,
    String? error,
    bool clearError = false,
    List<String>? logLines,
    bool? folderVaultChecking,
    FolderVaultCheckReport? folderVaultReport,
    bool clearFolderVaultReport = false,
    bool? folderVaultRepairing,
    FolderVaultRepairReport? folderVaultRepairReport,
    bool clearFolderVaultRepairReport = false,
  }) => ContainerRepairState(
    target: clearTarget ? null : (target ?? this.target),
    diagnosing: diagnosing ?? this.diagnosing,
    diagnosis: clearDiagnosis ? null : (diagnosis ?? this.diagnosis),
    actionRunning: actionRunning ?? this.actionRunning,
    actionSucceeded: clearActionSucceeded ? null : (actionSucceeded ?? this.actionSucceeded),
    error: clearError ? null : (error ?? this.error),
    logLines: logLines ?? this.logLines,
    folderVaultChecking: folderVaultChecking ?? this.folderVaultChecking,
    folderVaultReport: clearFolderVaultReport ? null : (folderVaultReport ?? this.folderVaultReport),
    folderVaultRepairing: folderVaultRepairing ?? this.folderVaultRepairing,
    folderVaultRepairReport: clearFolderVaultRepairReport ? null : (folderVaultRepairReport ?? this.folderVaultRepairReport),
  );
}

@riverpod
class ContainerRepair extends _$ContainerRepair {
  @override
  ContainerRepairState build() => const ContainerRepairState();

  void appendLogLine(String message) {
    final newLogs = List<String>.from(state.logLines)..add(message);
    state = state._copy(logLines: newLogs);
  }

  void resetDiagnosis({bool keepTarget = false}) {
    state = state._copy(
      clearTarget: !keepTarget,
      diagnosing: false,
      clearDiagnosis: true,
      actionRunning: false,
      clearActionSucceeded: true,
      clearError: true,
      logLines: const [],
      folderVaultChecking: false,
      clearFolderVaultReport: true,
      folderVaultRepairing: false,
      clearFolderVaultRepairReport: true,
    );
  }

  void changeTarget() => resetDiagnosis(keepTarget: false);

  Future<void> pickUnmountedFile() async {
    final picked = await ref.read(vaultLifecycleApiProvider).pickContainer();
    if (picked == null || !ref.mounted) return;
    state = state._copy(
      target: UnmountedFileTarget(uri: picked.uri, displayName: picked.displayName),
    );
    resetDiagnosis(keepTarget: true);
  }

  void pickMountedVolume(MountedContainer container) {
    state = state._copy(
      target: MountedVolumeTarget(
        volId: container.volId,
        displayName: container.displayName,
      ),
    );
    resetDiagnosis(keepTarget: true);
  }

  void pickMountedFolderVault(MountedContainer container) {
    state = state._copy(
      target: FolderVaultTarget(
        treeUri: container.uri,
        displayName: container.displayName,
        format: container.containerFormat,
        mountedVolId: container.volId,
      ),
    );
    resetDiagnosis(keepTarget: true);
  }

  void setFolderVaultTarget(FolderVaultTarget target) {
    state = state._copy(target: target);
    resetDiagnosis(keepTarget: true);
  }

  Future<void> runDiagnosis(AppLocalizations l10n) async {
    final target = state.target;
    if (target == null) return;
    resetDiagnosis(keepTarget: true);
    state = state._copy(diagnosing: true);
    try {
      final result = await ref.read(containerToolServiceProvider).diagnoseTarget(
        target,
        onLogLine: appendLogLine,
      );
      if (!ref.mounted) return;
      state = state._copy(diagnosing: false, diagnosis: result);
    } on UnimplementedError {
      if (ref.mounted) {
        state = state._copy(diagnosing: false, error: l10n.toolNotImplementedYetMessage);
      }
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(diagnosing: false, error: '$e');
      }
    }
  }

  Future<void> restoreBackupHeader({
    String? password,
    required Future<String?> Function() onPromptPassword,
    required AppLocalizations l10n,
  }) async {
    final target = state.target;
    if (target == null) return;
    state = state._copy(logLines: const []);
    await _executeRestoreBackupHeader(
      target: target,
      password: password,
      onPromptPassword: onPromptPassword,
      l10n: l10n,
    );
  }

  Future<void> _executeRestoreBackupHeader({
    required RepairTarget target,
    String? password,
    required Future<String?> Function() onPromptPassword,
    required AppLocalizations l10n,
  }) async {
    state = state._copy(actionRunning: true, clearError: true);
    try {
      final ok = await ref.read(containerToolServiceProvider).restoreBackupHeader(
        target,
        password: password,
        onLogLine: appendLogLine,
      );
      if (!ref.mounted) return;
      state = state._copy(actionRunning: false, actionSucceeded: ok);
    } on RepairPasswordRequiredException {
      if (!ref.mounted) return;
      state = state._copy(actionRunning: false);
      final entered = await onPromptPassword();
      if (!ref.mounted || entered == null || entered.isEmpty) return;
      await _executeRestoreBackupHeader(
        target: target,
        password: entered,
        onPromptPassword: onPromptPassword,
        l10n: l10n,
      );
    } on UnimplementedError {
      if (ref.mounted) {
        state = state._copy(actionRunning: false, error: l10n.toolNotImplementedYetMessage);
      }
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(actionRunning: false, error: '$e');
      }
    }
  }

  Future<void> runFilesystemCheck(AppLocalizations l10n) async {
    final target = state.target;
    if (target is! MountedVolumeTarget) return;
    state = state._copy(
      actionRunning: true,
      clearError: true,
      logLines: const [],
    );
    try {
      final ok = await ref.read(containerToolServiceProvider).runFilesystemCheck(
        target,
        onLogLine: appendLogLine,
      );
      if (!ref.mounted) return;
      state = state._copy(actionRunning: false, actionSucceeded: ok);
    } on UnimplementedError {
      if (ref.mounted) {
        state = state._copy(actionRunning: false, error: l10n.toolNotImplementedYetMessage);
      }
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(actionRunning: false, error: '$e');
      }
    }
  }

  Future<void> runFolderVaultCheck({
    String? password,
    required Future<String?> Function() onPromptPassword,
    required AppLocalizations l10n,
  }) async {
    final target = state.target;
    if (target is! FolderVaultTarget) return;
    state = state._copy(
      folderVaultChecking: true,
      clearError: true,
      clearFolderVaultReport: true,
      logLines: const [],
    );
    try {
      final report = await ref.read(containerToolServiceProvider).checkFolderVault(
        target,
        password: password,
        onLogLine: appendLogLine,
      );
      if (!ref.mounted) return;
      state = state._copy(folderVaultChecking: false, folderVaultReport: report);
    } on RepairIncorrectPasswordException {
      if (!ref.mounted) return;
      state = state._copy(folderVaultChecking: false);
      final entered = await onPromptPassword();
      if (!ref.mounted || entered == null || entered.isEmpty) return;
      await runFolderVaultCheck(
        password: entered,
        onPromptPassword: onPromptPassword,
        l10n: l10n,
      );
    } on FolderVaultInvalidException catch (e) {
      if (ref.mounted) {
        state = state._copy(folderVaultChecking: false, error: '$e');
      }
    } on UnimplementedError {
      if (ref.mounted) {
        state = state._copy(folderVaultChecking: false, error: l10n.toolNotImplementedYetMessage);
      }
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(folderVaultChecking: false, error: '$e');
      }
    }
  }

  Future<void> runFolderVaultRepair({
    String? password,
    required Future<String?> Function() onPromptPassword,
  }) async {
    final target = state.target;
    if (target is! FolderVaultTarget) return;

    if (!target.isAlreadyMounted && (password == null || password.isEmpty)) {
      final entered = await onPromptPassword();
      if (!ref.mounted || entered == null || entered.isEmpty) return;
      password = entered;
    }

    state = state._copy(
      folderVaultRepairing: true,
      clearError: true,
      clearFolderVaultRepairReport: true,
      logLines: const [],
    );

    try {
      final report = await ref.read(containerToolServiceProvider).repairFolderVault(
        target,
        password: password,
        onLogLine: appendLogLine,
      );
      if (!ref.mounted) return;
      state = state._copy(
        folderVaultRepairing: false,
        folderVaultRepairReport: report,
        folderVaultReport: FolderVaultCheckReport(
          format: report.format,
          filesScanned: state.folderVaultReport?.filesScanned ?? 0,
          issues: report.remainingIssues,
          deepScanPerformed: true,
        ),
      );
    } on RepairIncorrectPasswordException {
      if (!ref.mounted) return;
      state = state._copy(folderVaultRepairing: false);
      final entered = await onPromptPassword();
      if (!ref.mounted || entered == null || entered.isEmpty) return;
      await runFolderVaultRepair(
        password: entered,
        onPromptPassword: onPromptPassword,
      );
    } on FolderVaultInvalidException catch (e) {
      if (ref.mounted) {
        state = state._copy(folderVaultRepairing: false, error: '$e');
      }
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(folderVaultRepairing: false, error: '$e');
      }
    }
  }
}
