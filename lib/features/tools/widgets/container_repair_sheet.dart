import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
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

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

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

  void _resetDiagnosis() {
    _diagnosis = null;
    _actionSucceeded = null;
    _error = null;
    _logLines.clear();
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
    final controller = TextEditingController();
    bool obscure = true;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final materialL10n = MaterialLocalizations.of(dialogContext);
            return AlertDialog(
              title: Text(context.l10n.passwordFieldLabel),
              content: TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.l10n.passwordFieldLabel,
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
                onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(materialL10n.cancelButtonLabel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(controller.text),
                  child: Text(materialL10n.okButtonLabel),
                ),
              ],
            );
          },
        );
      },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.colors.surfaceContainerHigh,
        title: Text(
          context.l10n.toolContainerRepairTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: _target == null
            ? SingleChildScrollView(
                padding: AppSpacing.pagePadding,
                child: _buildTargetStep(context),
              )
            : Padding(
                padding: AppSpacing.pagePadding,
                child: _buildDiagnosisStep(context),
              ),
      ),
    );
  }

  Widget _buildTargetStep(BuildContext context) {
    final textTheme = context.typography;
    final cs = context.colors;
    return ValueListenableBuilder<List<MountedContainer>>(
      valueListenable: widget.mountedContainers,
      builder: (context, mounted, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.repairTargetStepTitle,
              style: textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            SheetOptionTile(
              icon: Icons.insert_drive_file_outlined,
              title: context.l10n.repairTargetUnmountedFileOption,
              subtitle: context.l10n.repairTargetUnmountedFileSubtitle,
              onTap: _pickUnmountedFile,
            ),
            const Divider(height: 24),
            Text(
              context.l10n.repairTargetMountedVolumeSubtitle,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            if (mounted.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  context.l10n.repairNoMountedVolumes,
                  style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              )
            else
              ...mounted.map(
                (c) => SheetOptionTile(
                  icon: Icons.lock_open_rounded,
                  iconColor: cs.tertiary,
                  title: c.displayName,
                  subtitle: c.containerFormat.toUpperCase(),
                  onTap: () => _pickMountedVolume(c),
                ),
              ),
          ],
        );
      },
    );
  }

  String _diagnosisLabel(BuildContext context, RepairDiagnosis diagnosis) =>
      switch (diagnosis) {
        RepairDiagnosis.healthy => context.l10n.repairDiagnosisHealthy,
        RepairDiagnosis.headerCorrupted =>
          context.l10n.repairDiagnosisHeaderCorrupted,
        RepairDiagnosis.filesystemDirty =>
          context.l10n.repairDiagnosisFilesystemDirty,
      };

  AppBannerTone _diagnosisTone(RepairDiagnosis diagnosis) =>
      switch (diagnosis) {
        RepairDiagnosis.healthy => AppBannerTone.success,
        RepairDiagnosis.headerCorrupted => AppBannerTone.warning,
        RepairDiagnosis.filesystemDirty => AppBannerTone.warning,
      };

  IconData _diagnosisIcon(RepairDiagnosis diagnosis) =>
      switch (diagnosis) {
        RepairDiagnosis.healthy => Icons.check_circle_outline_rounded,
        RepairDiagnosis.headerCorrupted => Icons.warning_amber_rounded,
        RepairDiagnosis.filesystemDirty => Icons.warning_amber_rounded,
      };

  Widget _buildDiagnosisStep(BuildContext context) {
    final textTheme = context.typography;
    final cs = context.colors;
    final target = _target!;
    final targetName = target is UnmountedFileTarget
        ? target.displayName
        : (target as MountedVolumeTarget).displayName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Target summary card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(
                target is UnmountedFileTarget
                    ? Icons.insert_drive_file_outlined
                    : Icons.lock_open_rounded,
                size: AppIconSize.small,
                color: cs.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  targetName,
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed:
                    (_diagnosing || _actionRunning) ? null : _changeTarget,
                child: Text(context.l10n.repairChangeTargetButton),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Log panel expanding to fill available screen height
        Expanded(
          child: _buildLogPanel(context),
        ),
        const SizedBox(height: AppSpacing.md),

        // Diagnosis banner (only shown before repair action succeeds)
        if (_diagnosis != null && _actionSucceeded != true) ...[
          InlineBanner(
            _diagnosisLabel(context, _diagnosis!),
            tone: _diagnosisTone(_diagnosis!),
            icon: _diagnosisIcon(_diagnosis!),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // Action Succeeded / Failed result banner
        if (_actionSucceeded != null) ...[
          InlineBanner(
            _actionSucceeded!
                ? context.l10n.repairActionSucceededMessage
                : context.l10n.repairActionFailedMessage,
            tone: _actionSucceeded!
                ? AppBannerTone.success
                : AppBannerTone.error,
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // Error banner
        if (_error != null) ...[
          InlineErrorBanner(_error!),
          const SizedBox(height: AppSpacing.md),
        ],

        // Action Button
        _buildActionButton(context, target),
      ],
    );
  }

  Widget _buildActionButton(BuildContext context, RepairTarget target) {
    final cs = context.colors;

    // Show fix button if diagnosis found corruption AND action has NOT succeeded yet
    if (_diagnosis == RepairDiagnosis.headerCorrupted && _actionSucceeded != true) {
      return FilledButton(
        onPressed: _actionRunning ? null : _restoreBackupHeader,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
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
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
        ),
        child: _actionButtonChild(context.l10n.repairRunFilesystemCheckButton),
      );
    }

    // Otherwise (no diagnosis yet, healthy, or after successful repair): show Diagnostic Scan button
    return FilledButton(
      onPressed: (_diagnosing || _actionRunning) ? null : _runDiagnosis,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
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

  Widget _buildLogPanel(BuildContext context) {
    final cs = context.colors;
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: _logLines.isEmpty
          ? Center(
              child: Text(
                'Log output will appear here...',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            )
          : Scrollbar(
              controller: _logScrollController,
              child: ListView.builder(
                controller: _logScrollController,
                itemCount: _logLines.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    _logLines[index],
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _actionButtonChild(String label) {
    if (_actionRunning) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    return Text(label, style: const TextStyle(fontWeight: FontWeight.bold));
  }
}