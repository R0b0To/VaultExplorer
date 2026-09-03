import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart' show KeyfileRef;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/header_backup_controller.dart';

/// Credentials supplied when unlocking/verifying a header restore.
class HeaderBackupPasswordResult {
  final String password;
  final int? pim;
  final List<KeyfileRef> keyfiles;

  const HeaderBackupPasswordResult({
    required this.password,
    this.pim,
    this.keyfiles = const [],
  });

  bool get hasAdvanced => keyfiles.isNotEmpty || (pim != null && pim! > 0);

  @override
  String toString() => password;
}

/// Container Utilities -> Header Backup: export a container's (or folder
/// vault's) header/key material to an external file, or restore it later.
/// See container_repair.cpp's "Header Backup / Restore" section and
/// HeaderBackupHandlers.kt for what actually gets backed up per format and
/// how a restore is verified before anything is written.
class HeaderBackupSheet extends ConsumerStatefulWidget {
  const HeaderBackupSheet({super.key});

  @override
  ConsumerState<HeaderBackupSheet> createState() => _HeaderBackupSheetState();
}

class _HeaderBackupSheetState extends ConsumerState<HeaderBackupSheet> {
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

  Future<String?> _promptForPassword() async {
    final state = ref.read(headerBackupProvider);
    final format = state.loadedBackup?.format ??
        (state.target is FolderVaultTarget ? 'gocryptfs' : 'veracrypt');

    final result = await showDialog<HeaderBackupPasswordResult>(
      context: context,
      builder: (dialogContext) => _HeaderBackupPasswordPromptDialog(
        containerFormat: format,
      ),
    );
    if (result == null) return null;
    return result.password;
  }

  Future<void> _saveExportedBackup(HeaderBackupFile backup) async {
    final folder = await ref.read(vaultLifecycleApiProvider).pickExtractFolder();
    if (folder == null || !mounted) return;
    final suggestedName = _suggestedFileName(backup);
    await ref
        .read(headerBackupProvider.notifier)
        .saveExportedBackup(
          destinationPath: folder.path,
          destinationTreeUri: folder.treeUri,
          fileName: suggestedName,
        );
  }

  String _suggestedFileName(HeaderBackupFile backup) {
    final base = backup.sourceName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '$base.${backup.format}.vxhdrbkp';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(headerBackupProvider.select((s) => s.logLines.length), (prev, next) {
      if (prev != next) _scrollToLogBottom();
    });

    final state = ref.watch(headerBackupProvider);
    final cs = context.colors;
    final l10n = context.l10n;
    final isLandscape = context.screen.useWideLayout;
    final hasTarget = state.target != null;

    return PopScope(
      canPop: !state.busy && !hasTarget,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (hasTarget && !state.busy) {
          ref.read(headerBackupProvider.notifier).changeTarget();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHigh,
          elevation: 0,
          leading: hasTarget
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: l10n.goBack,
                  onPressed: state.busy ? null : () => ref.read(headerBackupProvider.notifier).changeTarget(),
                )
              : null,
          title: Text(
            l10n.toolHeaderBackupTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: isLandscape
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                : AppSpacing.pagePadding,
            child: hasTarget
                ? _buildActiveLayout(context, state, isLandscape)
                : _buildStartLayout(context, state, isLandscape),
          ),
        ),
      ),
    );
  }

  // ── START LAYOUT: mode toggle + target picker ───────────────────────────

  Widget _buildStartLayout(BuildContext context, HeaderBackupState state, bool isLandscape) {
    final cs = context.colors;
    final l10n = context.l10n;
    final textTheme = context.typography;
    final notifier = ref.read(headerBackupProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<HeaderBackupMode>(
          segments: [
            ButtonSegment(
              value: HeaderBackupMode.export,
              label: Text(l10n.headerBackupModeExport, maxLines: 2, overflow: TextOverflow.ellipsis),
              icon: const Icon(Icons.save_alt_rounded),
            ),
            ButtonSegment(
              value: HeaderBackupMode.restore,
              label: Text(l10n.headerBackupModeRestore, maxLines: 2, overflow: TextOverflow.ellipsis),
              icon: const Icon(Icons.settings_backup_restore_rounded),
            ),
          ],
          selected: {state.mode},
          onSelectionChanged: (s) => notifier.setMode(s.first),
        ),
        const SizedBox(height: 14),
        Text(
          state.mode == HeaderBackupMode.export
              ? l10n.headerBackupPickExportTarget
              : l10n.headerBackupPickRestoreTarget,
          style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.bold),
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
                title: l10n.vaultKindContainerFile,
                subtitle: l10n.headerBackupTargetContainerSubtitle,
                onTap: () => notifier.pickUnmountedFile(),
              ),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
              SheetOptionTile(
                icon: Icons.folder_outlined,
                title: l10n.vaultKindFolderVault,
                subtitle: l10n.headerBackupTargetFolderSubtitle,
                onTap: () => notifier.pickFolderVault(),
              ),
            ],
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: 10),
          InlineErrorBanner(state.error!),
        ],
        const SizedBox(height: 14),
        InlineBanner(
          state.mode == HeaderBackupMode.export
              ? l10n.headerBackupExportInfoBanner
              : l10n.headerBackupRestoreInfoBanner,
          tone: AppBannerTone.info,
          icon: Icons.info_outline_rounded,
        ),
      ],
    );
  }

  // ── ACTIVE LAYOUT: target picked ────────────────────────────────────────

  Widget _buildActiveLayout(BuildContext context, HeaderBackupState state, bool isLandscape) {
    final cs = context.colors;
    final textTheme = context.typography;
    final target = state.target!;

    final content = state.mode == HeaderBackupMode.export
        ? _buildExportContent(context, state, target, cs, textTheme)
        : _buildRestoreContent(context, state, target, cs, textTheme);

    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: SingleChildScrollView(child: content)),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        content,
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: _buildLogPanel(context, state, cs),
        ),
      ],
    );
  }

  Widget _buildTargetSummaryCard(BuildContext context, RepairTarget target, ColorScheme cs, TextTheme textTheme) {
    final displayName = switch (target) {
      UnmountedFileTarget(:final displayName) => displayName,
      FolderVaultTarget(:final displayName) => displayName,
      MountedVolumeTarget(:final displayName) => displayName,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            target is UnmountedFileTarget ? Icons.insert_drive_file_outlined : Icons.folder_outlined,
            size: AppIconSize.small,
            color: cs.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              displayName,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── EXPORT ───────────────────────────────────────────────────────────

  Widget _buildExportContent(
    BuildContext context,
    HeaderBackupState state,
    RepairTarget target,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final notifier = ref.read(headerBackupProvider.notifier);
    final l10n = context.l10n;
    final backup = state.exportedBackup;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTargetSummaryCard(context, target, cs, textTheme),
        const SizedBox(height: 10),
        if (state.unhealthyDiagnosis != null) ...[
          InlineBanner(
            l10n.headerBackupUnhealthyExportWarning(_diagnosisLabel(state.unhealthyDiagnosis!)),
            tone: AppBannerTone.warning,
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => notifier.changeTarget(),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  child: Text(l10n.cancel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: state.busy ? null : () => notifier.confirmExportDespiteUnhealthy(),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  child: Text(l10n.headerBackupBackUpAnyway),
                ),
              ),
            ],
          ),
        ] else if (backup == null) ...[
          FilledButton(
            onPressed: state.busy ? null : () => notifier.runExport(l10n),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
            child: _actionButtonChild(l10n.headerBackupExportHeader, state.busy, cs),
          ),
        ] else ...[
          _buildBackupSummaryCard(context, backup, cs, textTheme),
          const SizedBox(height: 8),
          if (state.exportSaved)
            InlineBanner(
              l10n.headerBackupSavedBanner,
              tone: AppBannerTone.success,
              icon: Icons.check_circle_outline_rounded,
            )
          else
            FilledButton.icon(
              onPressed: state.busy ? null : () => _saveExportedBackup(backup),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
              icon: const Icon(Icons.save_alt_rounded, size: 18),
              label: _actionButtonChild(l10n.headerBackupSaveBackupFile, state.busy, cs),
            ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 8),
          InlineErrorBanner(state.error!),
        ],
      ],
    );
  }

  // ── RESTORE ──────────────────────────────────────────────────────────

  Widget _buildRestoreContent(
    BuildContext context,
    HeaderBackupState state,
    RepairTarget target,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final notifier = ref.read(headerBackupProvider.notifier);
    final l10n = context.l10n;
    final backup = state.loadedBackup;
    final expectedKind = target is FolderVaultTarget ? HeaderBackupKind.folderVaultConfig : HeaderBackupKind.containerHeader;
    final kindMismatch = backup != null && backup.kind != expectedKind;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTargetSummaryCard(context, target, cs, textTheme),
        const SizedBox(height: 10),
        if (backup == null)
          FilledButton.icon(
            onPressed: state.busy ? null : () => notifier.pickBackupFile(),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
            icon: const Icon(Icons.file_open_outlined, size: 18),
            label: _actionButtonChild(l10n.headerBackupPickBackupFile, state.busy, cs),
          )
        else ...[
          _buildBackupSummaryCard(context, backup, cs, textTheme),
          const SizedBox(height: 8),
          if (kindMismatch)
            InlineBanner(
              backup.kind == HeaderBackupKind.folderVaultConfig
                  ? l10n.headerBackupMismatchFolderVaultError
                  : l10n.headerBackupMismatchContainerFileError,
              tone: AppBannerTone.error,
              icon: Icons.error_outline_rounded,
            )
          else if (state.restoreSucceeded)
            InlineBanner(
              l10n.headerBackupRestoredSuccess,
              tone: AppBannerTone.success,
              icon: Icons.check_circle_outline_rounded,
            )
          else
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => notifier.runRestore(onPromptPassword: _promptForPassword, l10n: l10n),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
              child: _actionButtonChild(l10n.headerBackupRestore, state.busy, cs),
            ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 8),
          InlineErrorBanner(state.error!),
        ],
      ],
    );
  }

  Widget _buildBackupSummaryCard(BuildContext context, HeaderBackupFile backup, ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final exportedAt = backup.exportedAtMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(backup.exportedAtMs).toLocal()
        : null;

    final datePart = exportedAt != null
        ? ' · ${l10n.headerBackupBackedUpAt(exportedAt.toString().split('.').first)}'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            backup.sourceName,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${backup.format.toUpperCase()} · ${formatBytes(backup.payload.length)}$datePart',
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ── SHARED ───────────────────────────────────────────────────────────

  Widget _buildLogPanel(BuildContext context, HeaderBackupState state, ColorScheme cs) {
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
                context.l10n.headerBackupLogIdle,
                style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              ),
            )
          : Scrollbar(
              controller: _logScrollController,
              child: ListView.builder(
                controller: _logScrollController,
                itemCount: state.logLines.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      state.logLines[index],
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white70, height: 1.4),
                    ),
                  );
                },
              ),
            ),
    );
  }

  String _diagnosisLabel(RepairDiagnosis diagnosis) => switch (diagnosis) {
    RepairDiagnosis.healthy => context.l10n.repairDiagnosisHealthy,
    RepairDiagnosis.headerCorrupted => context.l10n.repairDiagnosisHeaderCorrupted,
    RepairDiagnosis.filesystemDirty => context.l10n.repairDiagnosisFilesystemDirty,
  };

  Widget _actionButtonChild(String label, bool busy, ColorScheme cs) {
    if (busy) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation(cs.onPrimary)),
      );
    }
    return Text(label, style: const TextStyle(fontWeight: FontWeight.bold));
  }
}

class _HeaderBackupPasswordPromptDialog extends ConsumerStatefulWidget {
  final String containerFormat;

  const _HeaderBackupPasswordPromptDialog({
    this.containerFormat = 'veracrypt',
  });

  @override
  ConsumerState<_HeaderBackupPasswordPromptDialog> createState() =>
      _HeaderBackupPasswordPromptDialogState();
}

class _HeaderBackupPasswordPromptDialogState
    extends ConsumerState<_HeaderBackupPasswordPromptDialog> {
  final _controller = TextEditingController();
  final _pimCtrl = TextEditingController();
  final List<KeyfileRef> _keyfiles = [];

  bool _showAdvanced = false;
  bool _obscure = true;
  bool _pickingKeyfiles = false;

  bool get _isCryptomator => widget.containerFormat.toLowerCase().contains('cryptomator');
  bool get _isGocryptfs => widget.containerFormat.toLowerCase().contains('gocryptfs');
  bool get _isCryfs => widget.containerFormat.toLowerCase().contains('cryfs');
  bool get _isBitlocker => widget.containerFormat.toLowerCase().contains('bitlocker');
  bool get _supportsAdvanced =>
      !_isCryptomator && !_isGocryptfs && !_isCryfs && !_isBitlocker;

  @override
  void dispose() {
    _controller.dispose();
    _pimCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickKeyfiles() async {
    setState(() => _pickingKeyfiles = true);
    try {
      final picked = await ref.read(vaultLifecycleApiProvider).pickKeyfiles();
      if (picked.isNotEmpty && mounted) {
        setState(() {
          _keyfiles.addAll(picked);
        });
      }
    } catch (_) {
      // Ignored: cancelled or file picker error
    } finally {
      if (mounted) setState(() => _pickingKeyfiles = false);
    }
  }

  void _submit() {
    final pimVal = int.tryParse(_pimCtrl.text.trim());
    Navigator.of(context).pop(
      HeaderBackupPasswordResult(
        password: _controller.text,
        pim: pimVal,
        keyfiles: List.unmodifiable(_keyfiles),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final materialL10n = MaterialLocalizations.of(context);
    final l10n = context.l10n;

    final hasConfiguredAdvanced =
        _keyfiles.isNotEmpty || _pimCtrl.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(l10n.verifyCredentialsTitle),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                obscureText: _obscure,
                autofocus: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  labelText: _supportsAdvanced
                      ? l10n.containerPasswordOptionalLabel
                      : l10n.passwordFieldLabel,
                  suffixIcon: PasswordVisibilityToggle(
                    obscured: _obscure,
                    onToggle: () => setState(() => _obscure = !_obscure),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),

              // ── Advanced Options Section (Keyfiles & PIM) ───────────────────
              if (_supportsAdvanced) ...[
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                    child: Row(
                      children: [
                        Icon(
                          _showAdvanced ? Icons.expand_less : Icons.expand_more,
                          color: cs.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.advancedOptionsTitle,
                          style: textTheme.bodyMedium?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!_showAdvanced && hasConfiguredAdvanced) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _keyfiles.isNotEmpty
                                  ? '${_keyfiles.length} keyfile${_keyfiles.length > 1 ? 's' : ''}'
                                  : 'PIM',
                              style: textTheme.labelSmall?.copyWith(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 240),
                  sizeCurve: Curves.easeInOutCubic,
                  crossFadeState: _showAdvanced
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity, height: 0),
                  secondChild: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      KeyfilesPicker(
                        keyfiles: _keyfiles,
                        picking: _pickingKeyfiles,
                        onPick: _pickKeyfiles,
                        onRemove: (k) => setState(() => _keyfiles.remove(k)),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pimCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          labelText: l10n.pimOptionalLabel,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(materialL10n.okButtonLabel),
        ),
      ],
    );
  }
}