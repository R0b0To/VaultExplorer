import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
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

  // Folder-vault (gocryptfs/CryFS/Cryptomator) check state -- kept separate
  // from _diagnosis/_actionSucceeded above since a folder-vault check
  // produces a list of issues rather than a single RepairDiagnosis code;
  // see _buildFolderVaultStep.
  bool _folderVaultChecking = false;
  FolderVaultCheckReport? _folderVaultReport;

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

  /// Counterpart to [_pickMountedVolume] for containers whose format
  /// [ContainerFormat.isFolderVault] -- these aren't a block device with an
  /// inner filesystem to fsck, they're a directory tree, so they need the
  /// [FolderVaultTarget] flow rather than [MountedVolumeTarget]. Routing
  /// through here rather than the SAF folder picker also means
  /// [FolderVaultTarget.mountedVolId] gets set, letting the deep scan reuse
  /// this already-open vault's key instead of asking for a password.
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
                child: _target is FolderVaultTarget
                    ? _buildFolderVaultStep(context)
                    : _buildDiagnosisStep(context),
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
            SheetOptionTile(
              icon: Icons.folder_outlined,
              title: 'Folder vault',
              subtitle: 'gocryptfs, CryFS, or Cryptomator',
              onTap: _pickFolderVault,
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
                  onTap: () => ContainerFormat.isFolderVaultWire(c.containerFormat)
                      ? _pickMountedFolderVault(c)
                      : _pickMountedVolume(c),
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
              Flexible(
                child: TextButton(
                  onPressed:
                      (_diagnosing || _actionRunning) ? null : _changeTarget,
                  child: Text(
                    context.l10n.repairChangeTargetButton,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
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

  String _folderVaultFormatLabel(String format) => switch (format) {
        'gocryptfs' => 'gocryptfs',
        'cryfs' => 'CryFS',
        'cryptomator' => 'Cryptomator',
        _ => format,
      };

  Widget _buildFolderVaultStep(BuildContext context) {
    final textTheme = context.typography;
    final cs = context.colors;
    final target = _target as FolderVaultTarget;
    final report = _folderVaultReport;
    final problemCount = report?.issues
            .where((i) => i.severity != FolderVaultIssueSeverity.info)
            .length ??
        0;

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
                target.isAlreadyMounted ? Icons.lock_open_rounded : Icons.folder_outlined,
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
                      target.displayName,
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      target.isAlreadyMounted
                          ? '${_folderVaultFormatLabel(target.format)} · already unlocked'
                          : _folderVaultFormatLabel(target.format),
                      style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: TextButton(
                  onPressed: _folderVaultChecking ? null : _changeTarget,
                  child: Text(
                    context.l10n.repairChangeTargetButton,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        Expanded(child: _buildLogPanel(context)),
        const SizedBox(height: AppSpacing.md),

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
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Scrollbar(
                  child: ListView.separated(
                    itemCount: report.issues.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (context, i) => _buildFolderVaultIssueTile(context, report.issues[i]),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
        ],

        if (_error != null) ...[
          InlineErrorBanner(_error!),
          const SizedBox(height: AppSpacing.md),
        ],

        _buildFolderVaultActionArea(context, report),
      ],
    );
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
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
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

  Widget _buildFolderVaultActionArea(BuildContext context, FolderVaultCheckReport? report) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (report != null && !report.deepScanPerformed) ...[
          OutlinedButton.icon(
            onPressed: _folderVaultChecking ? null : _promptForPasswordAndDeepScan,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.password_rounded),
            label: const Text('Deep scan with password', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        FilledButton(
          onPressed: _folderVaultChecking ? null : () => _runFolderVaultCheck(),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: _folderVaultChecking
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                  ),
                )
              : Text(
                  report == null ? context.l10n.repairScanButton : 'Scan again',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
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

/// The password dialog used by [_ContainerRepairSheetState._promptForPassword].
///
/// Pulled out into its own widget rather than a local closure holding a
/// bare TextEditingController + `.whenComplete(controller.dispose)`: that
/// pattern disposes the controller as soon as `showDialog`'s Future
/// resolves, which can be *before* the dialog's route has actually finished
/// its exit transition and been unmounted -- if anything triggers one more
/// build of the still-transitioning route in that window, it rebuilds a
/// TextField pointed at an already-disposed controller and crashes. Making
/// the controller a State field means Flutter disposes it exactly when the
/// Element is unmounted, which is always the right time by construction.
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