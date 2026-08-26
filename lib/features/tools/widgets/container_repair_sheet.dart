// File: lib/features/tools/widgets/container_repair_sheet.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/container_tool_service.dart';

class ContainerRepairSheet extends StatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;

  const ContainerRepairSheet({super.key, required this.mountedContainers});

  @override
  State<ContainerRepairSheet> createState() => _ContainerRepairSheetState();
}

class _ContainerRepairSheetState extends State<ContainerRepairSheet> {
  RepairTarget? _target;
  bool _diagnosing = false;
  RepairDiagnosis? _diagnosis;
  bool _actionRunning = false;
  bool? _actionSucceeded;
  String? _error;
  final List<String> _logLines = [];
  final ScrollController _logScrollController = ScrollController();
  bool _folderVaultChecking = false;
  FolderVaultCheckReport? _folderVaultReport;
  bool _folderVaultRepairing = false;
  FolderVaultRepairReport? _folderVaultRepairReport;

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  bool get _isWorking =>
      _diagnosing || _actionRunning || _folderVaultChecking || _folderVaultRepairing;

  void _appendLogLine(String message) {
    if (!mounted) return;
    setState(() => _logLines.add(message));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScrollController.hasClients) return;
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickUnmountedFile() async {
    final picked = await vaultExplorerApi.pickContainer();
    if (picked == null || !mounted) return;
    setState(() {
      _target = UnmountedFileTarget(uri: picked.uri, displayName: picked.displayName);
      _resetDiagnosis();
    });
  }

  void _pickMountedVolume(MountedContainer container) {
    setState(() {
      _target = MountedVolumeTarget(
        volId: container.volId,
        displayName: container.displayName,
      );
      _resetDiagnosis();
    });
  }

  void _pickMountedFolderVault(MountedContainer container) {
    setState(() {
      _target = FolderVaultTarget(
        treeUri: container.uri,
        displayName: container.displayName,
        format: container.containerFormat,
        mountedVolId: container.volId,
      );
      _resetDiagnosis();
    });
  }

  Future<void> _pickFolderVault() async {
    try {
      final picked = await ContainerToolService.instance.pickFolderVaultForRepair();
      if (picked == null || !mounted) return;
      setState(() {
        _target = picked;
        _resetDiagnosis();
      });
    } on FolderVaultInvalidException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } on UnimplementedError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.toolNotImplementedYetMessage)),
      );
    }
  }

  void _resetDiagnosis() {
    _diagnosis = null;
    _actionSucceeded = null;
    _error = null;
    _logLines.clear();
    _folderVaultChecking = false;
    _folderVaultReport = null;
    _folderVaultRepairReport = null;
  }

  void _changeTarget() => setState(() {
        _target = null;
        _resetDiagnosis();
      });

  Future<void> _runDiagnosis() async {
    final target = _target;
    if (target == null) return;
    setState(() {
      _diagnosing = true;
      _resetDiagnosis();
    });
    try {
      final result = await ContainerToolService.instance.diagnoseTarget(
        target,
        onLogLine: _appendLogLine,
      );
      if (!mounted) return;
      setState(() {
        _diagnosing = false;
        _diagnosis = result;
      });
    } on UnimplementedError {
      if (mounted) {
        setState(() {
          _diagnosing = false;
          _error = context.l10n.toolNotImplementedYetMessage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _diagnosing = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _restoreBackupHeader() async {
    final target = _target;
    if (target == null) return;
    setState(() => _logLines.clear());
    await _runRestoreBackupHeader(target, password: null);
  }

  Future<void> _runRestoreBackupHeader(RepairTarget target, {String? password}) async {
    setState(() {
      _actionRunning = true;
      _error = null;
    });
    try {
      final ok = await ContainerToolService.instance.restoreBackupHeader(
        target,
        password: password,
        onLogLine: _appendLogLine,
      );
      if (mounted) {
        setState(() {
          _actionRunning = false;
          _actionSucceeded = ok;
        });
      }
    } on RepairPasswordRequiredException {
      if (!mounted) return;
      setState(() => _actionRunning = false);
      final entered = await _promptForPassword();
      if (!mounted) return;
      if (entered == null || entered.isEmpty) return;
      await _runRestoreBackupHeader(target, password: entered);
    } on UnimplementedError {
      if (mounted) {
        setState(() {
          _actionRunning = false;
          _error = context.l10n.toolNotImplementedYetMessage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _actionRunning = false;
          _error = '$e';
        });
      }
    }
  }

  Future<String?> _promptForPassword() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => const _PasswordPromptDialog(),
    );
  }

  Future<void> _runFilesystemCheck() async {
    final target = _target;
    if (target is! MountedVolumeTarget) return;
    setState(() {
      _actionRunning = true;
      _error = null;
      _logLines.clear();
    });
    try {
      final ok = await ContainerToolService.instance.runFilesystemCheck(target, onLogLine: _appendLogLine);
      if (mounted) {
        setState(() {
          _actionRunning = false;
          _actionSucceeded = ok;
        });
      }
    } on UnimplementedError {
      if (mounted) {
        setState(() {
          _actionRunning = false;
          _error = context.l10n.toolNotImplementedYetMessage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _actionRunning = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _runFolderVaultCheck({String? password}) async {
    final target = _target;
    if (target is! FolderVaultTarget) return;
    setState(() {
      _folderVaultChecking = true;
      _error = null;
      _folderVaultReport = null;
      _logLines.clear();
    });
    try {
      final report = await ContainerToolService.instance.checkFolderVault(
        target,
        password: password,
        onLogLine: _appendLogLine,
      );
      if (mounted) {
        setState(() {
          _folderVaultChecking = false;
          _folderVaultReport = report;
        });
      }
    } on RepairIncorrectPasswordException {
      if (!mounted) return;
      setState(() => _folderVaultChecking = false);
      final entered = await _promptForPassword();
      if (!mounted || entered == null || entered.isEmpty) return;
      await _runFolderVaultCheck(password: entered);
    } on FolderVaultInvalidException catch (e) {
      if (mounted) {
        setState(() {
          _folderVaultChecking = false;
          _error = '$e';
        });
      }
    } on UnimplementedError {
      if (mounted) {
        setState(() {
          _folderVaultChecking = false;
          _error = context.l10n.toolNotImplementedYetMessage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _folderVaultChecking = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _promptForPasswordAndDeepScan() async {
    final entered = await _promptForPassword();
    if (!mounted || entered == null || entered.isEmpty) return;
    await _runFolderVaultCheck(password: entered);
  }

  Future<void> _runFolderVaultRepair({String? password}) async {
    final target = _target;
    if (target is! FolderVaultTarget) return;

    if (!target.isAlreadyMounted && (password == null || password.isEmpty)) {
      final entered = await _promptForPassword();
      if (!mounted || entered == null || entered.isEmpty) return;
      password = entered;
    }

    setState(() {
      _folderVaultRepairing = true;
      _error = null;
      _folderVaultRepairReport = null;
      _logLines.clear();
    });

    try {
      final report = await ContainerToolService.instance.repairFolderVault(
        target,
        password: password,
        onLogLine: _appendLogLine,
      );
      if (mounted) {
        setState(() {
          _folderVaultRepairing = false;
          _folderVaultRepairReport = report;
          _folderVaultReport = FolderVaultCheckReport(
            format: report.format,
            filesScanned: _folderVaultReport?.filesScanned ?? 0,
            issues: report.remainingIssues,
            deepScanPerformed: true,
          );
        });
      }
    } on RepairIncorrectPasswordException {
      if (!mounted) return;
      setState(() => _folderVaultRepairing = false);
      final entered = await _promptForPassword();
      if (!mounted || entered == null || entered.isEmpty) return;
      await _runFolderVaultRepair(password: entered);
    } on FolderVaultInvalidException catch (e) {
      if (mounted) {
        setState(() {
          _folderVaultRepairing = false;
          _error = '$e';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _folderVaultRepairing = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final isLandscape = context.screen.useWideLayout;
    final hasTarget = _target != null;

    return PopScope(
      canPop: !_isWorking && !hasTarget,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (hasTarget && !_isWorking) {
          _changeTarget();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHigh,
          elevation: 0,
          leading: hasTarget
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: context.l10n.goBack,
                  onPressed: _isWorking ? null : _changeTarget,
                )
              : null,
          title: Text(
            context.l10n.toolContainerRepairTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: isLandscape
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                : AppSpacing.pagePadding,
            child: hasTarget
                ? _buildActiveRepairLayout(context, isLandscape)
                : _buildTargetSelectorLayout(context, isLandscape),
          ),
        ),
      ),
    );
  }

  // ── TARGET SELECTOR LAYOUT (ALIGNED & ZERO-WASTE) ──────────────────────────

  Widget _buildTargetSelectorLayout(BuildContext context, bool isLandscape) {
    final cs = context.colors;
    final textTheme = context.typography;

    final unmountedSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.repairTargetStepTitle,
          style: textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            children: [
              SheetOptionTile(
                icon: Icons.insert_drive_file_outlined,
                title: context.l10n.repairTargetUnmountedFileOption,
                subtitle: context.l10n.repairTargetUnmountedFileSubtitle,
                onTap: _pickUnmountedFile,
              ),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
              SheetOptionTile(
                icon: Icons.folder_outlined,
                title: 'Folder vault',
                subtitle: 'gocryptfs, CryFS, or Cryptomator',
                onTap: _pickFolderVault,
              ),
            ],
          ),
        ),
      ],
    );

    final mountedSection = ValueListenableBuilder<List<MountedContainer>>(
      valueListenable: widget.mountedContainers,
      builder: (context, mountedList, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.repairTargetMountedVolumeSubtitle,
              style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (mountedList.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Text(
                    context.l10n.repairNoMountedVolumes,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: mountedList.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
                  itemBuilder: (context, i) {
                    final c = mountedList[i];
                    return SheetOptionTile(
                      icon: Icons.lock_open_rounded,
                      iconColor: cs.tertiary,
                      title: c.displayName,
                      subtitle: c.containerFormat.toUpperCase(),
                      onTap: () => ContainerFormat.isFolderVaultWire(c.containerFormat)
                          ? _pickMountedFolderVault(c)
                          : _pickMountedVolume(c),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );

    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: unmountedSection),
          const SizedBox(width: 16),
          const VerticalDivider(width: 1),
          const SizedBox(width: 16),
          Expanded(child: mountedSection),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        unmountedSection,
        const SizedBox(height: AppSpacing.lg),
        mountedSection,
      ],
    );
  }

  // ── ACTIVE REPAIR LAYOUT (ALIGNED & ZERO-WASTE) ────────────────────────────

  Widget _buildActiveRepairLayout(BuildContext context, bool isLandscape) {
    final cs = context.colors;
    final textTheme = context.typography;
    final target = _target!;

    final leftControls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTargetSummaryCard(context, target, cs, textTheme),
        const SizedBox(height: 10),
        if (target is FolderVaultTarget) ...[
          ..._buildFolderVaultReportSection(context, target, cs, textTheme),
        ] else ...[
          ..._buildFileDiagnosisSection(context, target, cs, textTheme),
        ],
      ],
    );

    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(child: leftControls),
          ),
          const SizedBox(width: 16),
          const VerticalDivider(width: 1),
          const SizedBox(width: 16),
          Expanded(
            flex: 6,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: _buildLogPanel(context, cs),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        leftControls,
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: _buildLogPanel(context, cs),
        ),
      ],
    );
  }

  // ── MODULE COMPONENTS ──────────────────────────────────────────────────────

  Widget _buildTargetSummaryCard(BuildContext context, RepairTarget target, ColorScheme cs, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            target is UnmountedFileTarget ? Icons.insert_drive_file_outlined : Icons.lock_open_rounded,
            size: AppIconSize.small,
            color: cs.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.repairTargetStepTitle,
                  style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  target is UnmountedFileTarget
                      ? target.displayName
                      : target is FolderVaultTarget
                          ? target.displayName
                          : (target as MountedVolumeTarget).displayName,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── FILE/VOLUME REPAIR MODULES ─────────────────────────────────────────────

  List<Widget> _buildFileDiagnosisSection(
    BuildContext context,
    RepairTarget target,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return [
      if (_diagnosis != null && _actionSucceeded != true) ...[
        InlineBanner(
          _diagnosisLabel(context, _diagnosis!),
          tone: _diagnosisTone(_diagnosis!),
          icon: _diagnosisIcon(_diagnosis!),
        ),
        const SizedBox(height: 8),
      ],
      if (_actionSucceeded != null) ...[
        InlineBanner(
          _actionSucceeded!
              ? context.l10n.repairActionSucceededMessage
              : context.l10n.repairActionFailedMessage,
          tone: _actionSucceeded! ? AppBannerTone.success : AppBannerTone.error,
        ),
        const SizedBox(height: 8),
      ],
      if (_error != null) ...[
        InlineErrorBanner(_error!),
        const SizedBox(height: 8),
      ],
      _buildActionButton(context, target),
    ];
  }

  Widget _buildActionButton(BuildContext context, RepairTarget target) {
    final cs = context.colors;
    if (_diagnosis == RepairDiagnosis.headerCorrupted && _actionSucceeded != true) {
      return FilledButton(
        onPressed: _actionRunning ? null : _restoreBackupHeader,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
        ),
        child: _actionButtonChild(context.l10n.repairRestoreBackupHeaderButton),
      );
    }
    if (_diagnosis == RepairDiagnosis.filesystemDirty &&
        target is MountedVolumeTarget &&
        _actionSucceeded != true) {
      return FilledButton(
        onPressed: _actionRunning ? null : _runFilesystemCheck,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
        ),
        child: _actionButtonChild(context.l10n.repairRunFilesystemCheckButton),
      );
    }
    return FilledButton(
      onPressed: (_diagnosing || _actionRunning) ? null : _runDiagnosis,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: const StadiumBorder(),
      ),
      child: _diagnosing
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(cs.onPrimary),
              ),
            )
          : Text(
              context.l10n.repairScanButton,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
    );
  }

  // ── FOLDER VAULT MODULES ───────────────────────────────────────────────────

  List<Widget> _buildFolderVaultReportSection(
    BuildContext context,
    FolderVaultTarget target,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final report = _folderVaultReport;
    final problemCount = report?.issues.where((i) => i.severity != FolderVaultIssueSeverity.info).length ?? 0;
    final repairReport = _folderVaultRepairReport;

    return [
      if (report != null) ...[
        InlineBanner(
          report.healthy
              ? (report.deepScanPerformed
                  ? 'No problems found -- every file\'s contents verified.'
                  : 'No structural problems found. Run a deep scan with the password to also verify file contents.')
              : '$problemCount issue${problemCount == 1 ? '' : 's'} found${report.deepScanPerformed ? '' : ' (structure only -- run a deep scan for a full content check)'}.',
          tone: report.healthy ? AppBannerTone.success : AppBannerTone.warning,
          icon: report.healthy ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
        ),
        if (report.issues.isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Scrollbar(
                child: ListView.separated(
                  itemCount: report.issues.length,
                  separatorBuilder: (_, __) => const Divider(height: 8),
                  itemBuilder: (context, i) => _buildFolderVaultIssueTile(context, report.issues[i]),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
      if (_error != null) ...[
        InlineErrorBanner(_error!),
        const SizedBox(height: 8),
      ],
      if (repairReport != null) ...[
        InlineBanner(
          'Repair summary: ${repairReport.fixedCount} fixed, '
          '${repairReport.recoveredCount} recovered to /LOST+FOUND, '
          '${repairReport.removedCount} cleaned up.',
          tone: repairReport.healthy ? AppBannerTone.success : AppBannerTone.warning,
          icon: repairReport.healthy ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
        ),
        const SizedBox(height: 8),
      ],
      _buildFolderVaultActionArea(context, report, cs),
    ];
  }

  Widget _buildFolderVaultActionArea(BuildContext context, FolderVaultCheckReport? report, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (report != null && !report.healthy) ...[
          FilledButton.icon(
            onPressed: (_folderVaultChecking || _folderVaultRepairing) ? null : () => _runFolderVaultRepair(),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.build_circle_rounded, size: 18),
            label: _folderVaultRepairing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: cs.onPrimary),
                  )
                : const Text('Repair & Recover Vault', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
        ],
        if (report != null && !report.deepScanPerformed && report.healthy) ...[
          OutlinedButton.icon(
            onPressed: (_folderVaultChecking || _folderVaultRepairing) ? null : _promptForPasswordAndDeepScan,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.password_rounded, size: 18),
            label: const Text('Deep scan with password', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
        ],
        if (report == null || report.healthy) ...[
          FilledButton(
            onPressed: (_folderVaultChecking || _folderVaultRepairing) ? null : () => _runFolderVaultCheck(),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            child: _folderVaultChecking
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onPrimary),
                  )
                : Text(
                    report == null ? context.l10n.repairScanButton : 'Scan again',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ],
    );
  }

  // ── GENERAL LOGGER PANEL ───────────────────────────────────────────────────

  Widget _buildLogPanel(BuildContext context, ColorScheme cs) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414), // Zero-glare deep console black background
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: _logLines.isEmpty
          ? Center(
              child: Text(
                'Console log output remains idle...',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            )
          : Scrollbar(
              controller: _logScrollController,
              child: ListView.builder(
                controller: _logScrollController,
                itemCount: _logLines.length,
                itemBuilder: (context, index) {
                  final line = _logLines[index];
                  // Color highlights matching the console status outputs
                  final color = line.contains('[ERROR]')
                      ? Colors.redAccent
                      : line.contains('[SUCCESS]')
                          ? Colors.greenAccent
                          : line.contains('[WARNING]')
                              ? Colors.amberAccent
                              : Colors.white70;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: color,
                        height: 1.4,
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  // ── AUXILIARY HELPERS ──────────────────────────────────────────────────────

  String _diagnosisLabel(BuildContext context, RepairDiagnosis diagnosis) => switch (diagnosis) {
        RepairDiagnosis.healthy => context.l10n.repairDiagnosisHealthy,
        RepairDiagnosis.headerCorrupted => context.l10n.repairDiagnosisHeaderCorrupted,
        RepairDiagnosis.filesystemDirty => context.l10n.repairDiagnosisFilesystemDirty,
      };

  AppBannerTone _diagnosisTone(RepairDiagnosis diagnosis) => switch (diagnosis) {
        RepairDiagnosis.healthy => AppBannerTone.success,
        RepairDiagnosis.headerCorrupted => AppBannerTone.warning,
        RepairDiagnosis.filesystemDirty => AppBannerTone.warning,
      };

  IconData _diagnosisIcon(RepairDiagnosis diagnosis) => switch (diagnosis) {
        RepairDiagnosis.healthy => Icons.check_circle_outline_rounded,
        RepairDiagnosis.headerCorrupted => Icons.warning_amber_rounded,
        RepairDiagnosis.filesystemDirty => Icons.warning_amber_rounded,
      };

  Widget _actionButtonChild(String label) {
    if (_actionRunning) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
    }
    return Text(label, style: const TextStyle(fontWeight: FontWeight.bold));
  }

  Widget _buildFolderVaultIssueTile(BuildContext context, FolderVaultIssue issue) {
    final cs = context.colors;
    final (icon, color) = switch (issue.severity) {
      FolderVaultIssueSeverity.critical => (Icons.error_outline_rounded, cs.error),
      FolderVaultIssueSeverity.warning => (Icons.warning_amber_rounded, cs.tertiary),
      FolderVaultIssueSeverity.info => (Icons.info_outline_rounded, cs.onSurfaceVariant),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (issue.path.isNotEmpty)
                Text(
                  issue.path,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              Text(
                issue.message,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _folderVaultFormatLabel(String format) => switch (format) {
        'gocryptfs' => 'gocryptfs',
        'cryfs' => 'CryFS',
        'cryptomator' => 'Cryptomator',
        _ => format,
      };
}

class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog();

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(context.l10n.passwordFieldLabel),
      content: TextField(
        controller: _controller,
        obscureText: _obscure,
        autofocus: true,
        decoration: InputDecoration(
          labelText: context.l10n.passwordFieldLabel,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(materialL10n.cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(materialL10n.okButtonLabel),
        ),
      ],
    );
  }
}