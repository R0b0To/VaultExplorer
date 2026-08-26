// File: lib/features/tools/widgets/single_file_crypto_sheet.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/container_tool_service.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_file_picker_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_folder_picker_sheet.dart';

class SingleFileCryptoSheet extends StatefulWidget {
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
  State<SingleFileCryptoSheet> createState() => _SingleFileCryptoSheetState();
}

class _SingleFileCryptoSheetState extends State<SingleFileCryptoSheet>
    with KeyfilePickerMixin {
  CryptoDirection _direction = CryptoDirection.encrypt;
  StandaloneCipher _cipher = StandaloneCipher.xChaCha20Poly1305;
  final List<CryptoSourceItem> _sources = [];
  CryptoDestination? _destination;
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _deleteOriginal = false;
  bool _busy = false;
  String? _error;
  int _currentIndex = 0;
  int? _progressDone;
  int? _progressTotal;

  @override
  void onKeyfilePickError(String message) => setState(() => _error = message);

  @override
  void initState() {
    super.initState();
    final initialSources = widget.initialSources;
    if (initialSources != null) _sources.addAll(initialSources);
    _destination = widget.initialDestination;
    _direction = widget.initialDirection ?? CryptoDirection.encrypt;
  }

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

  Future<void> _addExternalSources() async {
    final picked = await vaultExplorerApi.pickCryptoFiles();
    if (picked.isEmpty || !mounted) return;
    setState(() {
      final existingIds = _sources.map((f) => f.id).toSet();
      for (final file in picked) {
        final item = CryptoSourceItem.external(
          displayName: file.displayName,
          externalUri: file.uri,
        );
        if (existingIds.add(item.id)) _sources.add(item);
      }
      _error = null;
    });
  }

  Future<void> _addVaultSources(List<MountedContainer> mountedVaults) async {
    final result = await Navigator.push<List<CryptoSourceItem>>(
      context,
      MaterialPageRoute(
        builder: (_) => VaultFilePickerSheet(mountedContainers: mountedVaults),
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        final existingIds = _sources.map((f) => f.id).toSet();
        for (final item in result) {
          if (existingIds.add(item.id)) _sources.add(item);
        }
        _error = null;
      });
    }
  }

  void _removeSource(CryptoSourceItem file) {
    setState(() => _sources.remove(file));
  }

  void _clearSources() {
    setState(() => _sources.clear());
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

  Future<void> _pickExternalDestination() async {
    final picked = await vaultExplorerApi.pickExtractFolder();
    if (picked == null || !mounted) return;
    setState(() {
      _destination = CryptoDestination.external(
        displayName: picked.displayName,
        externalPath: picked.path,
        externalTreeUri: picked.treeUri,
      );
      _error = null;
    });
  }

  Future<void> _pickVaultDestination(List<MountedContainer> mountedVaults) async {
    final result = await Navigator.push<CryptoDestination>(
      context,
      MaterialPageRoute(
        builder: (_) => VaultFolderPickerSheet(mountedContainers: mountedVaults),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _destination = result;
        _error = null;
      });
    }
  }

  Future<void> _run() async {
    if (_sources.isEmpty) {
      setState(() => _error = context.l10n.noFileSelectedLabel);
      return;
    }
    final dest = _destination;
    if (dest == null) {
      setState(() => _error = context.l10n.noFolderSelectedLabel);
      return;
    }
    if (_passwordCtrl.text.isEmpty && keyfiles.isEmpty) {
      setState(() => _error = context.l10n.passwordOrKeyfilesRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _currentIndex = 0;
      _progressDone = 0;
      _progressTotal = null;
    });
    final keyfilePaths = keyfiles.map((k) => k.uri).toList();
    final result = await ContainerToolService.instance.runBatchFileCrypto(
      direction: _direction,
      sources: _sources,
      destination: dest,
      cipher: _cipher,
      passphrase: _passwordCtrl.text,
      keyfilePaths: keyfilePaths,
      deleteOriginal: _deleteOriginal,
      onFileStart: (currentIndex, totalFiles) {
        if (!mounted) return;
        setState(() {
          _currentIndex = currentIndex;
          _progressDone = 0;
          _progressTotal = null;
        });
      },
      onFileProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _progressDone = done;
          _progressTotal = total;
        });
      },
    );
    if (!mounted) return;
    if (result.abortReason == BatchCryptoAbortReason.notImplemented) {
      setState(() {
        _busy = false;
        _error = context.l10n.toolNotImplementedYetMessage;
      });
      return;
    }
    if (result.abortReason == BatchCryptoAbortReason.authFailure) {
      setState(() {
        _busy = false;
        _error = context.l10n.incorrectPasswordError;
      });
      return;
    }
    if (result.failedNames.isEmpty) {
      Navigator.of(context).pop();
      showAppSnackBar(
        context,
        message: context.l10n.singleFileCryptoSuccessMessage(result.succeeded),
        tone: AppBannerTone.success,
      );
    } else if (result.succeeded > 0) {
      Navigator.of(context).pop();
      showAppSnackBar(
        context,
        message: context.l10n.singleFileCryptoPartialFailureMessage(
          result.succeeded,
          result.totalFiles,
          result.failedNames.length,
        ),
        tone: AppBannerTone.warning,
      );
    } else {
      setState(() {
        _busy = false;
        _error = context.l10n.singleFileCryptoPartialFailureMessage(
          result.succeeded,
          result.totalFiles,
          result.failedNames.length,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final isEncrypt = _direction == CryptoDirection.encrypt;
    final directionLocked = widget.initialDirection != null;
    final isLandscape = context.screen.useWideLayout;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        elevation: 0,
        title: Text(
          directionLocked
              ? (isEncrypt
                  ? context.l10n.singleFileCryptoEncryptButton(_sources.length)
                  : context.l10n.singleFileCryptoDecryptButton(_sources.length))
              : context.l10n.toolSingleFileCryptoTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (!directionLocked && isLandscape) ...[
            _buildDirectionSelector(isCompact: true),
            const SizedBox(width: 16),
          ],
        ],
      ),
      body: SafeArea(
        child: isLandscape
            ? _buildLandscapeLayout(context, isEncrypt)
            : _buildPortraitLayout(context, isEncrypt, directionLocked),
      ),
    );
  }

  Widget _buildDirectionSelector({required bool isCompact}) {
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
        selected: {_direction},
        onSelectionChanged: _busy
            ? null
            : (sel) => setState(() {
                  _direction = sel.first;
                  _error = null;
                }),
      ),
    );
  }

  // ── LANDSCAPE 2-COLUMN LAYOUT ──────────────────────────────────────────────

  Widget _buildLandscapeLayout(BuildContext context, bool isEncrypt) {
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
                  _buildInputFilesCard(cs, textTheme, isCompact: true),
                  const SizedBox(height: 10),
                  _buildDestinationFolderCard(cs, textTheme, isCompact: true),
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
                  _buildCryptoParams(cs, textTheme, isEncrypt, isCompact: true),
                  const SizedBox(height: 8),
                  _buildProgressAndSubmit(cs, textTheme, isEncrypt),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PORTRAIT SINGLE-COLUMN LAYOUT ──────────────────────────────────────────

  Widget _buildPortraitLayout(BuildContext context, bool isEncrypt, bool directionLocked) {
    final cs = context.colors;
    final textTheme = context.typography;

    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!directionLocked) ...[
            _buildDirectionSelector(isCompact: false),
            const SizedBox(height: AppSpacing.md),
          ],
          _buildInputFilesCard(cs, textTheme, isCompact: false),
          const SizedBox(height: AppSpacing.sm),
          _buildDestinationFolderCard(cs, textTheme, isCompact: false),
          const SizedBox(height: AppSpacing.md),
          _buildCryptoParams(cs, textTheme, isEncrypt, isCompact: false),
          _buildProgressAndSubmit(cs, textTheme, isEncrypt),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  // ── INPUT FILES CARD ───────────────────────────────────────────────────────

  Widget _buildInputFilesCard(ColorScheme cs, TextTheme textTheme, {required bool isCompact}) {
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
                      context.l10n.singleFileCryptoFilesQueuedCount(_sources.length),
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
                    onPressed: _busy ? null : _addSources,
                  ),
                ),
              ],
            ],
          ),
          if (_sources.isNotEmpty) ...[
            const SizedBox(height: 6),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: isCompact ? 140 : 200),
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final file in _sources)
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
                                  onPressed: _busy ? null : () => _removeSource(file),
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
                  onPressed: _busy ? null : _clearSources,
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

  Widget _buildDestinationFolderCard(ColorScheme cs, TextTheme textTheme, {required bool isCompact}) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            _destination?.isVault == true ? Icons.lock_rounded : Icons.folder_outlined,
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
                  _destination?.displayName ?? context.l10n.noFolderSelectedLabel,
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
                onPressed: _busy ? null : _pickDestination,
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

  Widget _buildCryptoParams(ColorScheme cs, TextTheme textTheme, bool isEncrypt, {required bool isCompact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _passwordCtrl,
          obscureText: _obscure,
          enabled: !_busy,
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
          keyfiles: keyfiles,
          picking: pickingKeyfiles,
          onPick: pickKeyfiles,
          onRemove: removeKeyfile,
          enabled: !_busy,
        ),
        if (isEncrypt) ...[
          const SizedBox(height: 8),
          OptionPickerTile<StandaloneCipher>(
            label: context.l10n.singleFileCryptoCipherLabel,
            value: _cipher,
            prefixIcon: Icons.security_rounded,
            options: StandaloneCipher.values
                .map((c) => SelectOption(value: c, label: c.label))
                .toList(),
            onChanged: _busy ? (_) {} : (val) => setState(() => _cipher = val),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: isCompact,
            value: _deleteOriginal,
            onChanged: _busy ? null : (v) => setState(() => _deleteOriginal = v),
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

  Widget _buildProgressAndSubmit(ColorScheme cs, TextTheme textTheme, bool isEncrypt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy && _sources.length > 1) ...[
          const SizedBox(height: 4),
          Text(
            context.l10n.singleFileCryptoBatchProgressLabel(_currentIndex, _sources.length),
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (_progressTotal != null) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: _progressTotal! > 0 ? (_progressDone ?? 0) / _progressTotal! : null,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.splitJoinOperationProgress(
              formatBytes(_progressDone ?? 0),
              formatBytes(_progressTotal!),
            ),
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          InlineErrorBanner(_error!),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _run,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: const StadiumBorder(),
          ),
          child: _busy
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
                      ? context.l10n.singleFileCryptoEncryptButton(_sources.length)
                      : context.l10n.singleFileCryptoDecryptButton(_sources.length),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}