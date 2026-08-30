import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/single_file_crypto_controller.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_file_picker_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_folder_picker_sheet.dart';

class SingleFileCryptoSheet extends ConsumerStatefulWidget {
  final ValueListenable<List<MountedContainer>>? mountedContainers;
  final List<CryptoSourceItem>? initialSources;
  final CryptoDestination? initialDestination;
  final CryptoDirection? initialDirection;
  final bool allowEditingSelection;

  const SingleFileCryptoSheet({
    super.key,
    this.mountedContainers,
    this.initialSources,
    this.initialDestination,
    this.initialDirection,
    this.allowEditingSelection = true,
  });

  @override
  ConsumerState<SingleFileCryptoSheet> createState() => _SingleFileCryptoSheetState();
}

class _SingleFileCryptoSheetState extends ConsumerState<SingleFileCryptoSheet> {
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _addSources() async {
    final mountedVaults = widget.mountedContainers?.value ?? [];
    if (mountedVaults.isEmpty) {
      _addExternalSources();
      return;
    }
    final useDevice = await showDeviceOrVaultChooserSheet(
      context: context,
      sheetTitle: context.l10n.singleFileCryptoSelectInputTitle,
      deviceTitle: context.l10n.singleFileCryptoFromDeviceTitle,
      deviceSubtitle: context.l10n.singleFileCryptoFromDeviceSubtitle,
      vaultTitle: context.l10n.singleFileCryptoFromVaultTitle,
      vaultSubtitle: context.l10n.singleFileCryptoFromVaultSubtitle,
    );
    if (useDevice == true) {
      _addExternalSources();
    } else if (useDevice == false) {
      _addVaultSources(mountedVaults);
    }
  }

  Future<void> _addExternalSources() => ref
      .read(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection).notifier)
      .addExternalSources();

  Future<void> _addVaultSources(List<MountedContainer> mountedVaults) async {
    final result = await Navigator.push<List<CryptoSourceItem>>(
      context,
      MaterialPageRoute(
        builder: (_) => VaultFilePickerSheet(mountedContainers: mountedVaults),
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      ref
          .read(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection).notifier)
          .addSources(result);
    }
  }

  void _removeSource(CryptoSourceItem file) {
    ref
        .read(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection).notifier)
        .removeSource(file);
  }

  void _clearSources() {
    ref
        .read(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection).notifier)
        .clearSources();
  }

  Future<void> _pickDestination() async {
    final mountedVaults = widget.mountedContainers?.value ?? [];
    if (mountedVaults.isEmpty) {
      _pickExternalDestination();
      return;
    }
    final useDevice = await showDeviceOrVaultChooserSheet(
      context: context,
      sheetTitle: context.l10n.singleFileCryptoSelectDestinationTitle,
      deviceIcon: Icons.folder_open_rounded,
      deviceTitle: context.l10n.singleFileCryptoDeviceFolderTitle,
      deviceSubtitle: context.l10n.singleFileCryptoDeviceFolderSubtitle,
      vaultTitle: context.l10n.singleFileCryptoVaultFolderTitle,
      vaultSubtitle: context.l10n.singleFileCryptoVaultFolderSubtitle,
    );
    if (useDevice == true) {
      _pickExternalDestination();
    } else if (useDevice == false) {
      _pickVaultDestination(mountedVaults);
    }
  }

  Future<void> _pickExternalDestination() => ref
      .read(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection).notifier)
      .pickExternalDestination();

  Future<void> _pickVaultDestination(List<MountedContainer> mountedVaults) async {
    final result = await Navigator.push<CryptoDestination>(
      context,
      MaterialPageRoute(
        builder: (_) => VaultFolderPickerSheet(mountedContainers: mountedVaults),
      ),
    );
    if (result != null && mounted) {
      ref
          .read(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection).notifier)
          .setDestination(result);
    }
  }

  Future<void> _run() async {
    final l10n = context.l10n;
    final result = await ref
        .read(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection).notifier)
        .runCrypto(
          passphrase: _passwordCtrl.text,
          l10n: l10n,
        );

    if (!mounted || result == null) return;

    if (result.isFullSuccess) {
      Navigator.of(context).pop();
      showAppSnackBar(
        context,
        message: l10n.singleFileCryptoSuccessMessage(result.succeeded),
        tone: AppBannerTone.success,
      );
    } else {
      Navigator.of(context).pop();
      showAppSnackBar(
        context,
        message: l10n.singleFileCryptoPartialFailureMessage(
          result.succeeded,
          result.totalFiles,
          result.failedCount,
        ),
        tone: AppBannerTone.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection));
    final cs = context.colors;
    final isEncrypt = state.direction == CryptoDirection.encrypt;
    final directionLocked = widget.initialDirection != null;
    final isLandscape = context.screen.useWideLayout;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        elevation: 0,
        title: Text(
          directionLocked
              ? (isEncrypt
                  ? context.l10n.singleFileCryptoEncryptButton(state.sources.length)
                  : context.l10n.singleFileCryptoDecryptButton(state.sources.length))
              : context.l10n.toolSingleFileCryptoTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (!directionLocked && isLandscape) ...[
            _buildDirectionSelector(state, isCompact: true),
            const SizedBox(width: 16),
          ],
        ],
      ),
      body: SafeArea(
        child: isLandscape
            ? _buildLandscapeLayout(context, state, isEncrypt)
            : _buildPortraitLayout(context, state, isEncrypt, directionLocked),
      ),
    );
  }

  Widget _buildDirectionSelector(SingleFileCryptoState state, {required bool isCompact}) {
    return Container(
      padding: isCompact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      child: SegmentedButton<CryptoDirection>(
        showSelectedIcon: false,
        style: isCompact
            ? SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              )
            : null,
        segments: [
          ButtonSegment(
            value: CryptoDirection.encrypt,
            label: Text(
              context.l10n.cryptoDirectionEncrypt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
            icon: const Icon(Icons.lock_outline_rounded, size: 18),
          ),
          ButtonSegment(
            value: CryptoDirection.decrypt,
            label: Text(
              context.l10n.cryptoDirectionDecrypt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
            icon: const Icon(Icons.lock_open_rounded, size: 18),
          ),
        ],
        selected: {state.direction},
        onSelectionChanged: state.busy
            ? null
            : (sel) => ref
                .read(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection).notifier)
                .setDirection(sel.first),
      ),
    );
  }

  // ── LANDSCAPE 2-COLUMN LAYOUT ──────────────────────────────────────────────

  Widget _buildLandscapeLayout(BuildContext context, SingleFileCryptoState state, bool isEncrypt) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left Column: Files & Destination ──────────────────────────────
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInputFilesCard(state, cs, textTheme, isCompact: true),
                  const SizedBox(height: 10),
                  _buildDestinationFolderCard(state, cs, textTheme, isCompact: true),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          const VerticalDivider(width: 1),
          const SizedBox(width: 16),

          // ── Right Column: Credentials, Options & Action ───────────────────
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCryptoParams(state, cs, textTheme, isEncrypt, isCompact: true),
                  const SizedBox(height: 8),
                  _buildProgressAndSubmit(state, cs, textTheme, isEncrypt),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PORTRAIT SINGLE-COLUMN LAYOUT ──────────────────────────────────────────

  Widget _buildPortraitLayout(
    BuildContext context,
    SingleFileCryptoState state,
    bool isEncrypt,
    bool directionLocked,
  ) {
    final cs = context.colors;
    final textTheme = context.typography;

    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!directionLocked) ...[
            _buildDirectionSelector(state, isCompact: false),
            const SizedBox(height: AppSpacing.md),
          ],
          _buildInputFilesCard(state, cs, textTheme, isCompact: false),
          const SizedBox(height: AppSpacing.sm),
          _buildDestinationFolderCard(state, cs, textTheme, isCompact: false),
          const SizedBox(height: AppSpacing.md),
          _buildCryptoParams(state, cs, textTheme, isEncrypt, isCompact: false),
          _buildProgressAndSubmit(state, cs, textTheme, isEncrypt),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  // ── INPUT FILES CARD ───────────────────────────────────────────────────────

  Widget _buildInputFilesCard(
    SingleFileCryptoState state,
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
                      context.l10n.singleFileCryptoInputFileLabel,
                      style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    Text(
                      context.l10n.singleFileCryptoFilesQueuedCount(state.sources.length),
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (widget.allowEditingSelection) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(
                      context.l10n.singleFileCryptoAddFilesButton,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                    onPressed: state.busy ? null : _addSources,
                  ),
                ),
              ],
            ],
          ),
          if (state.sources.isNotEmpty) ...[
            const SizedBox(height: 6),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: isCompact ? 140 : 200),
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final file in state.sources)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                file.isFromVault ? Icons.lock_rounded : iconForFile(file.displayName),
                                size: 16,
                                color: file.isFromVault ? cs.primary : colorForFile(file.displayName),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      file.displayName,
                                      style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (file.isFromVault)
                                      Text(
                                        '${file.container!.displayName} • ${file.relativePath}',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 10,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              if (widget.allowEditingSelection)
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 16),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: state.busy ? null : () => _removeSource(file),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.allowEditingSelection)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  onPressed: state.busy ? null : _clearSources,
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

  // ── DESTINATION FOLDER CARD ────────────────────────────────────────────────

  Widget _buildDestinationFolderCard(
    SingleFileCryptoState state,
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
          Icon(
            state.destination?.isVault == true ? Icons.lock_rounded : Icons.folder_outlined,
            size: AppIconSize.small,
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.splitDestinationFolderLabel,
                  style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  state.destination?.displayName ?? context.l10n.noFolderSelectedLabel,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (widget.allowEditingSelection) ...[
            const SizedBox(width: 6),
            Flexible(
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: state.busy ? null : _pickDestination,
                child: Text(
                  context.l10n.chooseFolderButton,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── CRYPTO PARAMETERS & OPTIONS ───────────────────────────────────────────

  Widget _buildCryptoParams(
    SingleFileCryptoState state,
    ColorScheme cs,
    TextTheme textTheme,
    bool isEncrypt, {
    required bool isCompact,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _passwordCtrl,
          obscureText: _obscure,
          enabled: !state.busy,
          autofillHints: null,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            isDense: isCompact,
            labelText: context.l10n.passwordFieldLabel,
            prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _obscure,
              onToggle: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 8),
        KeyfilesPicker(
          keyfiles: state.keyfiles,
          picking: state.pickingKeyfiles,
          onPick: () => ref
              .read(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection).notifier)
              .pickKeyfiles(),
          onRemove: (k) => ref
              .read(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection).notifier)
              .removeKeyfile(k),
          enabled: !state.busy,
        ),
        if (isEncrypt) ...[
          const SizedBox(height: 8),
          OptionPickerTile<StandaloneCipher>(
            label: context.l10n.singleFileCryptoCipherLabel,
            value: state.cipher,
            prefixIcon: Icons.security_rounded,
            options: StandaloneCipher.values
                .map((c) => SelectOption(value: c, label: c.label))
                .toList(),
            onChanged: state.busy
                ? (_) {}
                : (val) => ref
                    .read(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection).notifier)
                    .setCipher(val),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: isCompact,
            value: state.deleteOriginal,
            onChanged: state.busy
                ? null
                : (v) => ref
                    .read(singleFileCryptoProvider(widget.initialSources, widget.initialDestination, widget.initialDirection).notifier)
                    .setDeleteOriginal(v),
            title: Text(
              context.l10n.singleFileCryptoDeleteOriginalLabel,
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ],
    );
  }

  // ── PROGRESS & SUBMIT BUTTON ──────────────────────────────────────────────

  Widget _buildProgressAndSubmit(
    SingleFileCryptoState state,
    ColorScheme cs,
    TextTheme textTheme,
    bool isEncrypt,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.busy && state.sources.length > 1) ...[
          const SizedBox(height: 4),
          Text(
            context.l10n.singleFileCryptoBatchProgressLabel(state.currentIndex, state.sources.length),
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (state.progressTotal != null) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: state.progressTotal! > 0 ? (state.progressDone ?? 0) / state.progressTotal! : null,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.splitJoinOperationProgress(
              formatBytes(state.progressDone ?? 0),
              formatBytes(state.progressTotal!),
            ),
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 8),
          InlineErrorBanner(state.error!),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: state.busy ? null : _run,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: const StadiumBorder(),
          ),
          child: state.busy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                  ),
                )
              : Text(
                  isEncrypt
                      ? context.l10n.singleFileCryptoEncryptButton(state.sources.length)
                      : context.l10n.singleFileCryptoDecryptButton(state.sources.length),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}