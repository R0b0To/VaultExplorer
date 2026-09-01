import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/hash_operation.dart';
import 'package:vaultexplorer/features/tools/models/hash_verifier_models.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/hash_verifier_controller.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_file_picker_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_folder_picker_sheet.dart';

part 'hash_verifier_sheet_rows.dart';

class HashVerifierSheet extends ConsumerStatefulWidget {
  final ValueListenable<List<MountedContainer>>? mountedContainers;

  const HashVerifierSheet({super.key, this.mountedContainers});

  @override
  ConsumerState<HashVerifierSheet> createState() => _HashVerifierSheetState();
}

class _HashVerifierSheetState extends ConsumerState<HashVerifierSheet> {
  Future<List<CryptoSourceItem>> _pickExternalSources() async {
    final picked = await ref.read(vaultLifecycleApiProvider).pickCryptoFiles();
    return picked
        .map((f) => CryptoSourceItem.external(displayName: f.displayName, externalUri: f.uri))
        .toList();
  }

  Future<List<CryptoSourceItem>> _pickVaultSources(List<MountedContainer> vaults) async {
    final result = await Navigator.push<List<CryptoSourceItem>>(
      context,
      MaterialPageRoute(builder: (_) => VaultFilePickerSheet(mountedContainers: vaults)),
    );
    return result ?? [];
  }

  Future<List<CryptoSourceItem>> _pickSources() async {
    final mountedVaults = widget.mountedContainers?.value ?? [];
    if (mountedVaults.isEmpty) return _pickExternalSources();
    final useDevice = await showDeviceOrVaultChooserSheet(
      context: context,
      sheetTitle: context.l10n.hashVerifierSelectSourceTitle,
      deviceTitle: context.l10n.singleFileCryptoFromDeviceTitle,
      deviceSubtitle: context.l10n.singleFileCryptoFromDeviceSubtitle,
      vaultTitle: context.l10n.singleFileCryptoFromVaultTitle,
      vaultSubtitle: context.l10n.singleFileCryptoFromVaultSubtitle,
    );
    if (useDevice == true) return _pickExternalSources();
    if (useDevice == false) return _pickVaultSources(mountedVaults);
    return [];
  }

  Future<void> _copyDigest(String hex) async {
    await Clipboard.setData(ClipboardData(text: hex));
    if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.hashVerifierCopiedMessage,
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _addComputeSources() async {
    final picked = await _pickSources();
    if (picked.isEmpty || !mounted) return;
    ref.read(hashVerifierProvider.notifier).addComputeSources(picked);
  }

  Future<void> _exportManifestResults(List<HashComputeResult> results, HashAlgorithm algorithm) async {
    if (results.isEmpty) return;
    final manifestText = ref
        .read(hashVerifierServiceProvider)
        .buildManifestText(results, algorithm);
    final suggestedName = results.length == 1
        ? '${results.first.source.displayName}.${algorithm.manifestExtension}'
        : 'checksums.${algorithm.manifestExtension}';

    final mountedVaults = widget.mountedContainers?.value ?? [];
    final useDevice = await showDeviceOrVaultChooserSheet(
      context: context,
      sheetTitle: context.l10n.singleFileCryptoSelectDestinationTitle,
      deviceTitle: context.l10n.singleFileCryptoFromDeviceTitle,
      deviceSubtitle: context.l10n.singleFileCryptoFromDeviceSubtitle,
      vaultTitle: context.l10n.singleFileCryptoFromVaultTitle,
      vaultSubtitle: context.l10n.singleFileCryptoFromVaultSubtitle,
      showVaultOption: mountedVaults.isNotEmpty,
    );
    if (useDevice == null || !mounted) return;

    if (useDevice) {
      final folder = await ref.read(vaultLifecycleApiProvider).pickExtractFolder();
      if (folder == null || !mounted) return;
      try {
        await ref.read(vaultHashApiProvider).writeExternalFileBytes(
          destinationPath: folder.path,
          destinationTreeUri: folder.treeUri,
          fileName: suggestedName,
          bytes: Uint8List.fromList(utf8.encode(manifestText)),
        );
        if (mounted) {
          showAppSnackBar(
            context,
            message: context.l10n
                .hashVerifierExportSuccessMessage('${folder.displayName}/$suggestedName'),
            tone: AppBannerTone.success,
          );
        }
      } catch (e) {
        if (mounted) {
          showAppSnackBar(
            context,
            message: context.l10n.hashVerifierExportFailedMessage(e),
            tone: AppBannerTone.error,
          );
        }
      }
    } else {
      final dest = await Navigator.push<CryptoDestination>(
        context,
        MaterialPageRoute(builder: (_) => VaultFolderPickerSheet(mountedContainers: mountedVaults)),
      );
      if (dest == null || !mounted) return;
      try {
        final path = '/${dest.relativePath ?? ''}/$suggestedName'.replaceAll('//', '/');
        final ok = await ref.read(vaultFileIoApiProvider).writeFileChunk(
          dest.container!,
          path,
          0,
          Uint8List.fromList(utf8.encode(manifestText)),
        );
        if (!mounted) return;
        if (ok) {
          showAppSnackBar(
            context,
            message: context.l10n
                .hashVerifierExportSuccessMessage('${dest.container!.displayName}$path'),
            tone: AppBannerTone.success,
          );
        } else {
          showAppSnackBar(
            context,
            message: context.l10n.hashVerifierExportFailedMessage(''),
            tone: AppBannerTone.error,
          );
        }
      } catch (e) {
        if (mounted) {
          showAppSnackBar(
            context,
            message: context.l10n.hashVerifierExportFailedMessage(e),
            tone: AppBannerTone.error,
          );
        }
      }
    }
  }

  Future<void> _pickManifest() async {
    final picked = await _pickSources();
    if (picked.isEmpty || !mounted) return;
    ref.read(hashVerifierProvider.notifier).loadManifest(picked.first, context.l10n);
  }

  Future<void> _autoAddFromManifestFolder() async {
    final added = await ref.read(hashVerifierProvider.notifier).autoAddFromManifestFolder();
    if (added != null && mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.hashVerifierAutoAddedCount(added),
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _addVerifyCandidates() async {
    final picked = await _pickSources();
    if (picked.isEmpty || !mounted) return;
    ref.read(hashVerifierProvider.notifier).addVerifyCandidates(picked);
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Widget _buildModeSegmentedButton(
    BuildContext context,
    HashVerifierState state, {
    required bool isCompact,
  }) {
    return Container(
      width: isCompact ? null : double.infinity,
      padding: isCompact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: SegmentedButton<HashVerifierMode>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        segments: [
          ButtonSegment(
            value: HashVerifierMode.compute,
            label: Text(
              context.l10n.hashVerifierModeCompute,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
          ButtonSegment(
            value: HashVerifierMode.verify,
            label: Text(
              context.l10n.hashVerifierModeVerify,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
          ButtonSegment(
            value: HashVerifierMode.vault,
            label: Text(
              context.l10n.hashVerifierModeVault,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
        ],
        selected: {state.mode},
        onSelectionChanged: state.isBusy
            ? null
            : (sel) => ref.read(hashVerifierProvider.notifier).setMode(sel.first),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hashVerifierProvider);
    final cs = context.colors;
    final textTheme = context.typography;
    final isLandscape = context.screen.useWideLayout;
    final inVaultSubAction = state.mode == HashVerifierMode.vault && state.vaultAction != null;

    return PopScope(
      canPop: !state.isBusy && !inVaultSubAction,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (inVaultSubAction && !state.vaultBusy) {
          ref.read(hashVerifierProvider.notifier).setVaultAction(null);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHigh,
          elevation: 0,
          leading: inVaultSubAction
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: context.l10n.goBack,
                  onPressed: state.vaultBusy
                      ? null
                      : () => ref.read(hashVerifierProvider.notifier).setVaultAction(null),
                )
              : null,
          title: Text(
            inVaultSubAction
                ? (state.vaultAction == HashVerifierVaultAction.compute
                    ? context.l10n.hashVerifierVaultActionComputeTitle
                    : context.l10n.hashVerifierVaultActionVerifyTitle)
                : context.l10n.toolHashVerifierTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (isLandscape && !inVaultSubAction) ...[
              _buildModeSegmentedButton(context, state, isCompact: true),
              const SizedBox(width: 12),
            ],
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: isLandscape
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isLandscape && !inVaultSubAction) ...[
                  _buildModeSegmentedButton(context, state, isCompact: false),
                  const SizedBox(height: 10),
                ],
                if (state.mode == HashVerifierMode.compute)
                  ..._buildComputeTab(context, state, cs, textTheme, isLandscape)
                else if (state.mode == HashVerifierMode.verify)
                  ..._buildVerifyTab(context, state, cs, textTheme, isLandscape)
                else
                  ..._buildVaultTab(context, state, cs, textTheme, isLandscape),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── COMPUTE TAB ────────────────────────────────────────────────────────────

  Widget _buildComputeFilesCard(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme, {
    required bool isCompact,
  }) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined, size: AppIconSize.small, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.hashVerifierFilesLabel,
                      style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      context.l10n.hashVerifierFilesQueuedCount(state.computeSources.length),
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(
                    context.l10n.singleFileCryptoAddFilesButton,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                  onPressed: state.computeBusy ? null : _addComputeSources,
                ),
              ),
            ],
          ),
          if (state.computeSources.isNotEmpty) ...[
            const SizedBox(height: 6),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: isCompact ? 100 : 140),
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final source in state.computeSources)
                        _SourceRow(
                          source: source,
                          result: state.computeResults[source.id],
                          algorithms: state.algorithms,
                          enabled: !state.computeBusy,
                          onRemove: () => ref
                              .read(hashVerifierProvider.notifier)
                              .removeComputeSource(source),
                          onCopy: _copyDigest,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onPressed: state.computeBusy
                    ? null
                    : () => ref.read(hashVerifierProvider.notifier).clearComputeSources(),
                child: Text(
                  context.l10n.singleFileCryptoClearFilesButton,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComputeResultsCard(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme, {
    required bool isCompact,
  }) {
    if (state.computeResults.isEmpty && !state.computeBusy) {
      return Container(
        padding: EdgeInsets.all(isCompact ? 14 : 20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            'Select files and tap "Compute Hashes" to view checksums and export a verification manifest.',
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.computeResults.isNotEmpty) ...[
          Text(
            'Computed Hashes (${state.computeResults.length})',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: isCompact ? 160 : 300),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final source in state.computeSources)
                      if (state.computeResults[source.id] != null)
                        _SourceRow(
                          source: source,
                          result: state.computeResults[source.id],
                          algorithms: state.algorithms,
                          enabled: !state.computeBusy,
                          onRemove: () => ref
                              .read(hashVerifierProvider.notifier)
                              .removeComputeSource(source),
                          onCopy: _copyDigest,
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.hashVerifierExportAlgorithmLabel,
                  style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: DropdownButton<HashAlgorithm>(
                  value: state.algorithms.contains(state.exportAlgorithm)
                      ? state.exportAlgorithm
                      : (state.algorithms.isEmpty ? null : state.algorithms.first),
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: [
                    for (final algo in state.algorithms)
                      DropdownMenuItem(value: algo, child: Text(algo.label)),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      ref.read(hashVerifierProvider.notifier).setExportAlgorithm(val);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: state.computeResults.values
                    .any((r) => r.digests.containsKey(state.exportAlgorithm))
                ? () => _exportManifestResults(
                      state.computeResults.values
                          .where((r) => r.digests.containsKey(state.exportAlgorithm))
                          .toList(),
                      state.exportAlgorithm,
                    )
                : null,
            icon: const Icon(Icons.save_alt_rounded, size: 16),
            label: Text(
              context.l10n.hashVerifierExportManifestButton,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAlgorithmsInlineSelector(
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.l10n.hashVerifierAlgorithmsLabel,
        style: textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final algo in HashAlgorithm.values) ...[
              FilterChip(
                label: Text(algo.label, style: const TextStyle(fontSize: 12)),
                selected: state.algorithms.contains(algo),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onSelected: state.computeBusy
                    ? null
                    : (selected) {
                        final newAlgos = Set<HashAlgorithm>.from(state.algorithms);
                        if (selected) {
                          newAlgos.add(algo);
                        } else {
                          newAlgos.remove(algo);
                        }
                        ref
                            .read(hashVerifierProvider.notifier)
                            .setAlgorithms(newAlgos);
                      },
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    ],
  );
}

  List<Widget> _buildComputeTab(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme,
    bool isLandscape,
  ) {
    final leftControls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAlgorithmsInlineSelector(state, cs, textTheme),
        const SizedBox(height: 8),
        _buildComputeFilesCard(context, state, cs, textTheme, isCompact: isLandscape),
        if (state.computeBusy && state.computeSources.length > 1) ...[
          const SizedBox(height: 6),
          Text(
            context.l10n.hashVerifierBatchProgressLabel(
              state.computeIndex,
              state.computeSources.length,
            ),
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (state.computeBusy) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (state.computeTotal != null && state.computeTotal! > 0)
                ? (state.computeDone ?? 0) / state.computeTotal!
                : null,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          const SizedBox(height: 4),
          Text(
            state.computeTotal != null
                ? context.l10n.splitJoinOperationProgress(
                    formatBytes(state.computeDone ?? 0),
                    formatBytes(state.computeTotal!),
                  )
                : formatBytes(state.computeDone ?? 0),
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (state.computeError != null) ...[
          const SizedBox(height: 8),
          InlineErrorBanner(state.computeError!),
        ],
        const SizedBox(height: 10),
        if (state.computeBusy)
          OutlinedButton(
            onPressed: () => ref.read(hashVerifierProvider.notifier).cancelCompute(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: const StadiumBorder(),
            ),
            child: Text(
              context.l10n.hashVerifierCancelButton,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          )
        else
          FilledButton(
            onPressed: state.computeSources.isEmpty
                ? null
                : () => ref
                    .read(hashVerifierProvider.notifier)
                    .runCompute(context.l10n),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: const StadiumBorder(),
            ),
            child: Text(
              context.l10n.hashVerifierComputeButton(state.computeSources.length),
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
      ],
    );

    if (isLandscape) {
      return [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: SingleChildScrollView(child: leftControls),
            ),
            const SizedBox(width: 14),
            const VerticalDivider(width: 1),
            const SizedBox(width: 14),
            Expanded(
              flex: 6,
              child: SingleChildScrollView(
                child: _buildComputeResultsCard(context, state, cs, textTheme, isCompact: true),
              ),
            ),
          ],
        ),
      ];
    }

    return [
      leftControls,
      if (state.computeResults.isNotEmpty && !state.computeBusy) ...[
        const SizedBox(height: AppSpacing.md),
        _buildComputeResultsCard(context, state, cs, textTheme, isCompact: false),
      ],
    ];
  }

  // ── VERIFY TAB ─────────────────────────────────────────────────────────────

  Widget _buildManifestPickerCard(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme, {
    required bool isCompact,
  }) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.checklist_rtl_rounded, size: AppIconSize.small, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.hashVerifierManifestLabel,
                  style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  state.manifestSource?.displayName ?? context.l10n.noFileSelectedLabel,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (state.manifestSource != null)
                  Text(
                    context.l10n.hashVerifierManifestEntryCount(state.manifestEntries.length),
                    style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: state.isBusy ? null : _pickManifest,
              child: Text(
                state.manifestSource == null
                    ? context.l10n.hashVerifierLoadManifestButton
                    : context.l10n.hashVerifierChangeManifestButton,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildVerifyTab(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme,
    bool isLandscape,
  ) {
    final matchCount = state.rows.where((r) => r.status == VerifyStatus.match).length;
    final mismatchCount = state.rows
        .where((r) => r.status == VerifyStatus.mismatch || r.status == VerifyStatus.error)
        .length;
    final missingCount = state.rows.where((r) => r.status == VerifyStatus.missing).length;
    final extras = state.extraCandidates;

    final leftControls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildManifestPickerCard(context, state, cs, textTheme, isCompact: isLandscape),
        if (state.manifestSource == null) ...[
          const SizedBox(height: 8),
          InlineBanner(context.l10n.hashVerifierNoManifestLoadedMessage),
        ],
        if (state.manifestSource != null) ...[
          const SizedBox(height: 8),
          if (state.manifestSource!.isFromVault) ...[
            OutlinedButton.icon(
              onPressed: state.isBusy ? null : _autoAddFromManifestFolder,
              icon: const Icon(Icons.folder_copy_outlined, size: 16),
              label: Text(
                context.l10n.hashVerifierAutoAddFolderButton,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(height: 6),
          ],
          OutlinedButton.icon(
            onPressed: state.isBusy ? null : _addVerifyCandidates,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(
              context.l10n.hashVerifierAddFilesToVerifyButton,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
        if (state.verifyError != null) ...[
          const SizedBox(height: 8),
          InlineErrorBanner(state.verifyError!),
        ],
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            context.l10n.hashVerifierExtraFilesLabel(extras.length),
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (state.verifyBusy && state.rows.where((r) => r.matchedSource != null).length > 1) ...[
          const SizedBox(height: 6),
          Text(
            context.l10n.hashVerifierVerifyProgressLabel(
              state.verifyIndex,
              state.rows.where((r) => r.matchedSource != null).length,
            ),
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (state.verifyBusy) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (state.verifyTotal != null && state.verifyTotal! > 0)
                ? (state.verifyDone ?? 0) / state.verifyTotal!
                : null,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          const SizedBox(height: 4),
          Text(
            state.verifyTotal != null
                ? context.l10n.splitJoinOperationProgress(
                    formatBytes(state.verifyDone ?? 0),
                    formatBytes(state.verifyTotal!),
                  )
                : formatBytes(state.verifyDone ?? 0),
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 10),
        if (state.verifyBusy)
          OutlinedButton(
            onPressed: () => ref.read(hashVerifierProvider.notifier).cancelVerify(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: const StadiumBorder(),
            ),
            child: Text(
              context.l10n.hashVerifierCancelButton,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          )
        else
          FilledButton(
            onPressed: state.rows.any((r) => r.matchedSource != null) && !state.isBusy
                ? () => ref.read(hashVerifierProvider.notifier).runVerifyAll()
                : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: const StadiumBorder(),
            ),
            child: Text(
              context.l10n.hashVerifierVerifyAllButton,
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
      ],
    );

    final rightResults = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.rows.isNotEmpty) ...[
          InlineBanner(
            context.l10n.hashVerifierSummaryMessage(matchCount, mismatchCount, missingCount),
            tone: mismatchCount > 0
                ? AppBannerTone.error
                : (missingCount > 0 ? AppBannerTone.warning : AppBannerTone.success),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: isLandscape ? 220 : 320),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final row in state.rows) _VerifyRowTile(row: row),
                  ],
                ),
              ),
            ),
          ),
        ] else if (isLandscape)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(
                context.l10n.hashVerifierNoManifestLoadedMessage,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );

    if (isLandscape) {
      return [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: SingleChildScrollView(child: leftControls)),
            const SizedBox(width: 14),
            const VerticalDivider(width: 1),
            const SizedBox(width: 14),
            Expanded(flex: 6, child: SingleChildScrollView(child: rightResults)),
          ],
        ),
      ];
    }

    return [
      leftControls,
      if (state.rows.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        rightResults,
      ],
    ];
  }

  // ── VAULT TAB ──────────────────────────────────────────────────────────────

  Widget _buildVaultActionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: AppIconSize.action, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildVaultTab(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme,
    bool isLandscape,
  ) {
    final action = state.vaultAction;
    if (action == null) return _buildVaultActionChooser(context, cs, textTheme, isLandscape);

    return [
      if (action == HashVerifierVaultAction.compute)
        ..._buildVaultComputeSection(context, state, cs, textTheme, isLandscape)
      else
        ..._buildVaultVerifySection(context, state, cs, textTheme, isLandscape),
    ];
  }

  List<Widget> _buildVaultActionChooser(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    bool isLandscape,
  ) {
    final computeCard = _buildVaultActionCard(
      icon: Icons.tag_rounded,
      iconColor: cs.primary,
      title: context.l10n.hashVerifierVaultActionComputeTitle,
      subtitle: context.l10n.hashVerifierVaultActionComputeSubtitle,
      onTap: () => ref
          .read(hashVerifierProvider.notifier)
          .setVaultAction(HashVerifierVaultAction.compute),
    );

    final verifyCard = _buildVaultActionCard(
      icon: Icons.fact_check_outlined,
      iconColor: cs.tertiary,
      title: context.l10n.hashVerifierVaultActionVerifyTitle,
      subtitle: context.l10n.hashVerifierVaultActionVerifySubtitle,
      onTap: () => ref
          .read(hashVerifierProvider.notifier)
          .setVaultAction(HashVerifierVaultAction.verify),
    );

    if (isLandscape) {
      return [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: computeCard),
              const SizedBox(width: 12),
              Expanded(child: verifyCard),
            ],
          ),
        ),
      ];
    }

    return [
      computeCard,
      const SizedBox(height: 10),
      verifyCard,
    ];
  }

  List<Widget> _buildVaultComputeSection(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme,
    bool isLandscape,
  ) {
    final phase = state.vaultProgress.phase;
    switch (phase) {
      case HashOperationPhase.scanning:
        return _buildVaultScanningTab(context, state, cs, textTheme);
      case HashOperationPhase.confirming:
        return _buildVaultConfirmingTab(context, state, cs, textTheme);
      case HashOperationPhase.hashing:
        return _buildVaultHashingTab(context, state, cs, textTheme);
      case HashOperationPhase.completed:
      case HashOperationPhase.cancelled:
        return _buildVaultCompletedTab(context, state, cs, textTheme, isLandscape);
      case HashOperationPhase.failed:
        return _buildVaultFailedTab(context, state, cs, textTheme);
      case HashOperationPhase.selecting:
        return _buildVaultSelectingTab(context, state, cs, textTheme, isLandscape);
    }
  }

  List<Widget> _buildVaultSelectingTab(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme,
    bool isLandscape,
  ) {
    final vaults = widget.mountedContainers?.value ?? [];
    if (vaults.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              context.l10n.hashVerifierVaultNoVaultsMessage,
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ];
    }

    final currentTarget = state.vaultTarget ?? vaults.first;

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OptionPickerTile<int>(
          label: context.l10n.hashVerifierVaultPickerLabel,
          value: currentTarget.volId,
          prefixIcon: Icons.lock_open_rounded,
          options: [
            for (final v in vaults) SelectOption(value: v.volId, label: v.displayName),
          ],
          onChanged: (volId) {
            final target = vaults.firstWhere((v) => v.volId == volId, orElse: () => vaults.first);
            ref.read(hashVerifierProvider.notifier).setVaultTarget(target);
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              context.l10n.hashVerifierAlgorithmsLabel,
              style: textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final algo in HashAlgorithm.values) ...[
                      FilterChip(
                        label: Text(algo.label, style: const TextStyle(fontSize: 12)),
                        selected: state.vaultAlgorithms.contains(algo),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onSelected: (selected) {
                          final newAlgos = Set<HashAlgorithm>.from(state.vaultAlgorithms);
                          if (selected) {
                            newAlgos.add(algo);
                          } else {
                            newAlgos.remove(algo);
                          }
                          ref
                              .read(hashVerifierProvider.notifier)
                              .setVaultAlgorithms(newAlgos);
                        },
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final actionButton = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.vaultError != null) ...[
          InlineErrorBanner(state.vaultError!),
          const SizedBox(height: 8),
        ],
        FilledButton.icon(
          onPressed: state.vaultAlgorithms.isEmpty
              ? null
              : () {
                  if (state.vaultTarget == null) {
                    ref.read(hashVerifierProvider.notifier).setVaultTarget(currentTarget);
                  }
                  ref.read(hashVerifierProvider.notifier).startVaultScan();
                },
          icon: const Icon(Icons.travel_explore_rounded, size: 18),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: const StadiumBorder(),
          ),
          label: Text(
            context.l10n.hashVerifierCheckEntireVaultButton,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
          ),
        ),
      ],
    );

    if (isLandscape) {
      return [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: controls),
            const SizedBox(width: 14),
            const VerticalDivider(width: 1),
            const SizedBox(width: 14),
            Expanded(flex: 6, child: actionButton),
          ],
        ),
      ];
    }

    return [
      controls,
      const SizedBox(height: 12),
      actionButton,
    ];
  }

  List<Widget> _buildVaultScanningTab(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return [
      Text(
        context.l10n.hashVerifierVaultScanningLabel,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 8),
      const LinearProgressIndicator(),
      const SizedBox(height: 8),
      Text(
        context.l10n.hashVerifierVaultFilesDiscoveredLabel(state.vaultProgress.discoveredFiles),
        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 4),
      Text(
        state.vaultProgress.currentPath ?? '',
        style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => ref.read(hashVerifierProvider.notifier).cancelVaultOperation(),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: const StadiumBorder(),
        ),
        child: Text(
          context.l10n.hashVerifierCancelButton,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
      ),
    ];
  }

  List<Widget> _buildVaultConfirmingTab(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final isEmpty = state.vaultProgress.discoveredFiles == 0;
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.hashVerifierVaultConfirmTitle,
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.hashVerifierVaultConfirmFilesLabel(state.vaultProgress.discoveredFiles),
              style: textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              formatBytes(state.vaultProgress.discoveredBytes),
              style: textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              state.vaultAlgorithms.map((a) => a.label).join(', '),
              style: textTheme.bodySmall?.copyWith(color: cs.primary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      if (state.vaultError != null) ...[
        const SizedBox(height: 8),
        InlineErrorBanner(state.vaultError!),
      ],
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => ref.read(hashVerifierProvider.notifier).resetVaultOperation(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                shape: const StadiumBorder(),
              ),
              child: Text(
                context.l10n.hashVerifierCancelButton,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: isEmpty
                  ? null
                  : () => ref
                      .read(hashVerifierProvider.notifier)
                      .startVaultHashing(context.l10n),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                shape: const StadiumBorder(),
              ),
              child: Text(
                context.l10n.hashVerifierVaultStartButton,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildVaultHashingTab(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final progress = state.vaultProgress;
    return [
      Text(
        context.l10n.hashVerifierVaultHashingProgressLabel(
          progress.completedFiles,
          progress.discoveredFiles,
        ),
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 4),
      Text(
        progress.currentPath ?? '',
        style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 8),
      LinearProgressIndicator(
        value: progress.hashingFraction,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      const SizedBox(height: 4),
      Text(
        context.l10n.splitJoinOperationProgress(
          formatBytes(progress.processedBytes),
          formatBytes(progress.discoveredBytes),
        ),
        style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => ref.read(hashVerifierProvider.notifier).cancelVaultOperation(),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: const StadiumBorder(),
        ),
        child: Text(
          context.l10n.hashVerifierCancelButton,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
      ),
    ];
  }

  List<Widget> _buildVaultCompletedTab(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme,
    bool isLandscape,
  ) {
    final aggregate = state.vaultProgress.aggregate;
    final cancelled = state.vaultProgress.phase == HashOperationPhase.cancelled;

    final statsCard = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.hashVerifierVaultCompleteTitle,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          if (aggregate != null) ...[
            Text(
              context.l10n.hashVerifierVaultCompleteFilesLabel(aggregate.filesChecked),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              context.l10n.hashVerifierVaultCompleteBytesLabel(formatBytes(aggregate.bytesProcessed)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.hashVerifierVaultCompleteSucceededLabel(aggregate.filesSucceeded),
              style: TextStyle(color: context.semanticColors.success, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (aggregate.filesFailed > 0)
              Text(
                context.l10n.hashVerifierVaultCompleteFailedLabel(aggregate.filesFailed),
                style: TextStyle(color: cs.error, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 6),
            Text(
              context.l10n.hashVerifierVaultElapsedLabel(_formatElapsed(aggregate.elapsed)),
              style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );

    final actionButtons = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (aggregate != null && aggregate.fileResults.any((r) => !r.hasError)) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.hashVerifierExportAlgorithmLabel,
                  style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: DropdownButton<HashAlgorithm>(
                  value: state.vaultAlgorithms.contains(state.vaultExportAlgorithm)
                      ? state.vaultExportAlgorithm
                      : (state.vaultAlgorithms.isEmpty ? null : state.vaultAlgorithms.first),
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: [
                    for (final algo in state.vaultAlgorithms)
                      DropdownMenuItem(value: algo, child: Text(algo.label)),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      ref.read(hashVerifierProvider.notifier).setVaultExportAlgorithm(val);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _exportManifestResults(
              aggregate.fileResults
                  .where((r) => r.digests.containsKey(state.vaultExportAlgorithm))
                  .toList(),
              state.vaultExportAlgorithm,
            ),
            icon: const Icon(Icons.save_alt_rounded, size: 16),
            label: Text(
              context.l10n.hashVerifierExportManifestButton,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton(
          onPressed: () => ref.read(hashVerifierProvider.notifier).resetVaultOperation(),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            shape: const StadiumBorder(),
          ),
          child: Text(
            context.l10n.hashVerifierVaultNewCheckButton,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
          ),
        ),
      ],
    );

    if (isLandscape) {
      return [
        if (cancelled) InlineErrorBanner(context.l10n.hashVerifierVaultCancelledMessage),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: statsCard),
            const SizedBox(width: 14),
            const VerticalDivider(width: 1),
            const SizedBox(width: 14),
            Expanded(flex: 6, child: actionButtons),
          ],
        ),
      ];
    }

    return [
      if (cancelled) InlineErrorBanner(context.l10n.hashVerifierVaultCancelledMessage),
      statsCard,
      const SizedBox(height: 12),
      actionButtons,
    ];
  }

  List<Widget> _buildVaultFailedTab(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return [
      InlineErrorBanner(
        context.l10n.hashVerifierVaultFailedMessage(state.vaultProgress.failureMessage ?? ''),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () => ref.read(hashVerifierProvider.notifier).resetVaultOperation(),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: const StadiumBorder(),
        ),
        child: Text(
          context.l10n.hashVerifierVaultNewCheckButton,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
      ),
    ];
  }

  List<Widget> _buildVaultVerifySection(
    BuildContext context,
    HashVerifierState state,
    ColorScheme cs,
    TextTheme textTheme,
    bool isLandscape,
  ) {
    final matchCount = state.rows.where((r) => r.status == VerifyStatus.match).length;
    final mismatchCount = state.rows
        .where((r) => r.status == VerifyStatus.mismatch || r.status == VerifyStatus.error)
        .length;
    final missingCount = state.rows.where((r) => r.status == VerifyStatus.missing).length;
    final manifestFromVault = state.manifestSource?.isFromVault ?? false;
    final matchedRowCount = state.rows.where((r) => r.matchedSource != null).length;
    final extras = state.extraCandidates;

    final leftControls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildManifestPickerCard(context, state, cs, textTheme, isCompact: isLandscape),
        if (state.manifestSource == null) ...[
          const SizedBox(height: 8),
          InlineBanner(context.l10n.hashVerifierNoManifestLoadedMessage),
        ] else if (!manifestFromVault) ...[
          const SizedBox(height: 8),
          InlineBanner(
            context.l10n.hashVerifierVaultVerifyRequiresVaultManifestMessage,
            tone: AppBannerTone.warning,
          ),
        ],
        if (state.verifyError != null) ...[
          const SizedBox(height: 8),
          InlineErrorBanner(state.verifyError!),
        ],
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            context.l10n.hashVerifierExtraFilesLabel(extras.length),
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (state.verifyBusy && matchedRowCount > 1) ...[
          const SizedBox(height: 6),
          Text(
            context.l10n.hashVerifierVerifyProgressLabel(state.verifyIndex, matchedRowCount),
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (state.verifyBusy) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (state.verifyTotal != null && state.verifyTotal! > 0)
                ? (state.verifyDone ?? 0) / state.verifyTotal!
                : null,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          const SizedBox(height: 4),
          Text(
            state.verifyTotal != null
                ? context.l10n.splitJoinOperationProgress(
                    formatBytes(state.verifyDone ?? 0),
                    formatBytes(state.verifyTotal!),
                  )
                : formatBytes(state.verifyDone ?? 0),
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 10),
        if (state.verifyBusy)
          OutlinedButton(
            onPressed: () => ref.read(hashVerifierProvider.notifier).cancelVerify(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: const StadiumBorder(),
            ),
            child: Text(
              context.l10n.hashVerifierCancelButton,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          )
        else
          FilledButton.icon(
            onPressed: (manifestFromVault && !state.loadingManifest)
                ? () => ref.read(hashVerifierProvider.notifier).verifyEntireVault()
                : null,
            icon: state.loadingManifest
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.travel_explore_rounded, size: 18),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: const StadiumBorder(),
            ),
            label: Text(
              context.l10n.hashVerifierVaultVerifyButton,
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
      ],
    );

    final rightResults = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.rows.isNotEmpty) ...[
          InlineBanner(
            context.l10n.hashVerifierSummaryMessage(matchCount, mismatchCount, missingCount),
            tone: mismatchCount > 0
                ? AppBannerTone.error
                : (missingCount > 0 ? AppBannerTone.warning : AppBannerTone.success),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: isLandscape ? 220 : 320),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final row in state.rows) _VerifyRowTile(row: row),
                  ],
                ),
              ),
            ),
          ),
        ] else if (isLandscape)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(
                context.l10n.hashVerifierNoManifestLoadedMessage,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );

    if (isLandscape) {
      return [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: SingleChildScrollView(child: leftControls)),
            const SizedBox(width: 14),
            const VerticalDivider(width: 1),
            const SizedBox(width: 14),
            Expanded(flex: 6, child: SingleChildScrollView(child: rightResults)),
          ],
        ),
      ];
    }

    return [
      leftControls,
      if (state.rows.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        rightResults,
      ],
    ];
  }
}
