import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/container_tool_service.dart';
import 'package:vaultexplorer/features/tools/widgets/container_repair_controller.dart';

class ContainerRepairSheet extends ConsumerStatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;

  const ContainerRepairSheet({super.key, required this.mountedContainers});

  @override
  ConsumerState<ContainerRepairSheet> createState() => _ContainerRepairSheetState();
}

class _ContainerRepairSheetState extends ConsumerState<ContainerRepairSheet> {
  final ScrollController _logScrollController = ScrollController();

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  void _scrollToLogBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScrollController.hasClients) return;
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickFolderVault() async {
    try {
      final picked = await ContainerToolService.instance.pickFolderVaultForRepair();
      if (picked == null || !mounted) return;
      ref.read(containerRepairProvider.notifier).setFolderVaultTarget(picked);
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

  Future<String?> _promptForPassword() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => const _PasswordPromptDialog(),
    );
  }

  Future<void> _runDiagnosis() =>
      ref.read(containerRepairProvider.notifier).runDiagnosis(context.l10n);

  Future<void> _restoreBackupHeader() =>
      ref.read(containerRepairProvider.notifier).restoreBackupHeader(
            onPromptPassword: _promptForPassword,
            l10n: context.l10n,
          );

  Future<void> _runFilesystemCheck() =>
      ref.read(containerRepairProvider.notifier).runFilesystemCheck(context.l10n);

  Future<void> _runFolderVaultCheck({String? password}) =>
      ref.read(containerRepairProvider.notifier).runFolderVaultCheck(
            password: password,
            onPromptPassword: _promptForPassword,
            l10n: context.l10n,
          );

  Future<void> _promptForPasswordAndDeepScan() async {
    final entered = await _promptForPassword();
    if (!mounted || entered == null || entered.isEmpty) return;
    await _runFolderVaultCheck(password: entered);
  }

  Future<void> _runFolderVaultRepair({String? password}) =>
      ref.read(containerRepairProvider.notifier).runFolderVaultRepair(
            password: password,
            onPromptPassword: _promptForPassword,
          );

  @override
  Widget build(BuildContext context) {
    ref.listen(
      containerRepairProvider.select((s) => s.logLines.length),
      (prev, next) {
        if (prev != next) _scrollToLogBottom();
      },
    );

    final state = ref.watch(containerRepairProvider);
    final cs = context.colors;
    final isLandscape = context.screen.useWideLayout;
    final hasTarget = state.target != null;

    return PopScope(
      canPop: !state.isWorking && !hasTarget,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (hasTarget && !state.isWorking) {
          ref.read(containerRepairProvider.notifier).changeTarget();
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
                  onPressed: state.isWorking
                      ? null
                      : () => ref.read(containerRepairProvider.notifier).changeTarget(),
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
                ? _buildActiveRepairLayout(context, state, isLandscape)
                : _buildTargetSelectorLayout(context, isLandscape),
          ),
        ),
      ),
    );
  }

  // ── TARGET SELECTOR LAYOUT ─────────────────────────────────────────────────

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
                onTap: () => ref.read(containerRepairProvider.notifier).pickUnmountedFile(),
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
                          ? ref.read(containerRepairProvider.notifier).pickMountedFolderVault(c)
                          : ref.read(containerRepairProvider.notifier).pickMountedVolume(c),
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

  // ── ACTIVE REPAIR LAYOUT (STABLE & NO SHIFT) ───────────────────────────────

  Widget _buildActiveRepairLayout(BuildContext context, ContainerRepairState state, bool isLandscape) {
    final cs = context.colors;
    final textTheme = context.typography;
    final target = state.target!;

    if (isLandscape) {
      final leftControls = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTargetSummaryCard(context, target, cs, textTheme),
          const SizedBox(height: 10),
          _buildPrimaryActionArea(context, state, target, cs),
          const SizedBox(height: 10),
          ..._buildResultsSection(context, state, target, cs, textTheme),
        ],
      );

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
              constraints: const BoxConstraints(maxHeight: 300),
              child: _buildLogPanel(context, state, cs),
            ),
          ),
        ],
      );
    }

    // Portrait Layout: Target -> Action -> Log Panel -> Results below (Zero Shift!)
    final results = _buildResultsSection(context, state, target, cs, textTheme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTargetSummaryCard(context, target, cs, textTheme),
        const SizedBox(height: 10),
        _buildPrimaryActionArea(context, state, target, cs),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: _buildLogPanel(context, state, cs),
        ),
        if (results.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...results,
        ],
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

  Widget _buildPrimaryActionArea(
    BuildContext context,
    ContainerRepairState state,
    RepairTarget target,
    ColorScheme cs,
  ) {
    if (target is FolderVaultTarget) {
      final report = state.folderVaultReport;
      return _buildFolderVaultActionArea(context, state, report, cs);
    }
    return _buildFileActionButton(context, state, target);
  }

  List<Widget> _buildResultsSection(
    BuildContext context,
    ContainerRepairState state,
    RepairTarget target,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    if (target is FolderVaultTarget) {
      return _buildFolderVaultReportSection(context, state, target, cs, textTheme);
    }
    return _buildFileDiagnosisSection(context, state, target, cs, textTheme);
  }

  // ── FILE/VOLUME REPAIR MODULES ─────────────────────────────────────────────

  List<Widget> _buildFileDiagnosisSection(
    BuildContext context,
    ContainerRepairState state,
    RepairTarget target,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return [
      if (state.diagnosis != null && state.actionSucceeded != true) ...[
        InlineBanner(
          _diagnosisLabel(context, state.diagnosis!),
          tone: _diagnosisTone(state.diagnosis!),
          icon: _diagnosisIcon(state.diagnosis!),
        ),
        const SizedBox(height: 8),
      ],
      if (state.actionSucceeded != null) ...[
        InlineBanner(
          state.actionSucceeded!
              ? context.l10n.repairActionSucceededMessage
              : context.l10n.repairActionFailedMessage,
          tone: state.actionSucceeded! ? AppBannerTone.success : AppBannerTone.error,
        ),
        const SizedBox(height: 8),
      ],
      if (state.error != null) ...[
        InlineErrorBanner(state.error!),
      ],
    ];
  }

  Widget _buildFileActionButton(BuildContext context, ContainerRepairState state, RepairTarget target) {
    if (state.diagnosis == RepairDiagnosis.headerCorrupted && state.actionSucceeded != true) {
      return FilledButton(
        onPressed: state.actionRunning ? null : _restoreBackupHeader,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
        ),
        child: _actionButtonChild(context.l10n.repairRestoreBackupHeaderButton, state.actionRunning),
      );
    }
    if (state.diagnosis == RepairDiagnosis.filesystemDirty &&
        target is MountedVolumeTarget &&
        state.actionSucceeded != true) {
      return FilledButton(
        onPressed: state.actionRunning ? null : _runFilesystemCheck,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
        ),
        child: _actionButtonChild(context.l10n.repairRunFilesystemCheckButton, state.actionRunning),
      );
    }
    final cs = context.colors;
    return FilledButton(
      onPressed: (state.diagnosing || state.actionRunning) ? null : _runDiagnosis,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: const StadiumBorder(),
      ),
      child: state.diagnosing
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
    ContainerRepairState state,
    FolderVaultTarget target,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final report = state.folderVaultReport;
    final problemCount = report?.issues.where((i) => i.severity != FolderVaultIssueSeverity.info).length ?? 0;
    final repairReport = state.folderVaultRepairReport;

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
        if (!report.deepScanPerformed && report.healthy) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (state.folderVaultChecking || state.folderVaultRepairing)
                ? null
                : _promptForPasswordAndDeepScan,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.password_rounded, size: 18),
            label: const Text('Deep scan with password', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
        const SizedBox(height: 8),
      ],
      if (state.error != null) ...[
        InlineErrorBanner(state.error!),
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
      ],
    ];
  }

  Widget _buildFolderVaultActionArea(
    BuildContext context,
    ContainerRepairState state,
    FolderVaultCheckReport? report,
    ColorScheme cs,
  ) {
    if (report != null && !report.healthy) {
      return FilledButton.icon(
        onPressed: (state.folderVaultChecking || state.folderVaultRepairing)
            ? null
            : () => _runFolderVaultRepair(),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
        ),
        icon: const Icon(Icons.build_circle_rounded, size: 18),
        label: state.folderVaultRepairing
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: cs.onPrimary),
              )
            : const Text('Repair & Recover Vault', style: TextStyle(fontWeight: FontWeight.bold)),
      );
    }

    return FilledButton(
      onPressed: (state.folderVaultChecking || state.folderVaultRepairing)
          ? null
          : () => _runFolderVaultCheck(),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: const StadiumBorder(),
      ),
      child: state.folderVaultChecking
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onPrimary),
            )
          : Text(
              report == null ? context.l10n.repairScanButton : 'Scan again',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
    );
  }

  // ── GENERAL LOGGER PANEL ───────────────────────────────────────────────────

  Widget _buildLogPanel(BuildContext context, ContainerRepairState state, ColorScheme cs) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: state.logLines.isEmpty
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
                itemCount: state.logLines.length,
                itemBuilder: (context, index) {
                  final line = state.logLines[index];
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

  Widget _actionButtonChild(String label, bool actionRunning) {
    if (actionRunning) {
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