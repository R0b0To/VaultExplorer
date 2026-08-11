import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
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

  const SingleFileCryptoSheet({
    super.key,
    this.mountedContainers,
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
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _addSources() {
    final mountedVaults = widget.mountedContainers?.value ?? [];
    if (mountedVaults.isEmpty) {
      _addExternalSources();
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => AppBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                context.l10n.singleFileCryptoSelectInputTitle,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            SheetOptionTile(
              icon: Icons.sd_storage_outlined,
              title: context.l10n.singleFileCryptoFromDeviceTitle,
              subtitle: context.l10n.singleFileCryptoFromDeviceSubtitle,
              onTap: () {
                Navigator.pop(ctx);
                _addExternalSources();
              },
            ),
            SheetOptionTile(
              icon: Icons.lock_open_rounded,
              iconColor: Theme.of(ctx).colorScheme.tertiary,
              title: context.l10n.singleFileCryptoFromVaultTitle,
              subtitle: context.l10n.singleFileCryptoFromVaultSubtitle,
              onTap: () {
                Navigator.pop(ctx);
                _addVaultSources(mountedVaults);
              },
            ),
          ],
        ),
      ),
    );
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

  void _pickDestination() {
    final mountedVaults = widget.mountedContainers?.value ?? [];
    if (mountedVaults.isEmpty) {
      _pickExternalDestination();
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => AppBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                context.l10n.singleFileCryptoSelectDestinationTitle,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            SheetOptionTile(
              icon: Icons.folder_open_rounded,
              title: context.l10n.singleFileCryptoDeviceFolderTitle,
              subtitle: context.l10n.singleFileCryptoDeviceFolderSubtitle,
              onTap: () {
                Navigator.pop(ctx);
                _pickExternalDestination();
              },
            ),
            SheetOptionTile(
              icon: Icons.lock_open_rounded,
              iconColor: Theme.of(ctx).colorScheme.tertiary,
              title: context.l10n.singleFileCryptoVaultFolderTitle,
              subtitle: context.l10n.singleFileCryptoVaultFolderSubtitle,
              onTap: () {
                Navigator.pop(ctx);
                _pickVaultDestination(mountedVaults);
              },
            ),
          ],
        ),
      ),
    );
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
    final textTheme = context.typography;
    final isEncrypt = _direction == CryptoDirection.encrypt;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.toolSingleFileCryptoTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<CryptoDirection>(
              segments: [
                ButtonSegment(
                  value: CryptoDirection.encrypt,
                  label: Text(context.l10n.cryptoDirectionEncrypt),
                  icon: const Icon(Icons.lock_outline_rounded, size: 18),
                ),
                ButtonSegment(
                  value: CryptoDirection.decrypt,
                  label: Text(context.l10n.cryptoDirectionDecrypt),
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
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.description_outlined,
                          size: AppIconSize.small, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.singleFileCryptoInputFileLabel,
                              style: textTheme.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            Text(
                              context.l10n.singleFileCryptoFilesQueuedCount(
                                  _sources.length),
                              style: textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _busy ? null : _addSources,
                        child: Text(context.l10n.singleFileCryptoAddFilesButton),
                      ),
                    ],
                  ),
                  if (_sources.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Divider(
                        height: 1,
                        color: cs.outlineVariant.withValues(alpha: 0.25)),
                    for (final file in _sources)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Icon(
                              file.isFromVault
                                  ? Icons.lock_rounded
                                  : iconForFile(file.displayName),
                              size: 16,
                              color: file.isFromVault
                                  ? cs.primary
                                  : colorForFile(file.displayName),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    file.displayName,
                                    style: textTheme.bodySmall,
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
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              visualDensity: VisualDensity.compact,
                              onPressed:
                                  _busy ? null : () => _removeSource(file),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _clearSources,
                        child:
                            Text(context.l10n.singleFileCryptoClearFilesButton),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(
                    _destination?.isVault == true
                        ? Icons.lock_rounded
                        : Icons.folder_outlined,
                    size: AppIconSize.small,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.splitDestinationFolderLabel,
                          style: textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        Text(
                          _destination?.displayName ??
                              context.l10n.noFolderSelectedLabel,
                          style: textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busy ? null : _pickDestination,
                    child: Text(context.l10n.chooseFolderButton),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              enabled: !_busy,
              autofillHints: isEncrypt ? const [AutofillHints.newPassword] : null,
              decoration: InputDecoration(
                labelText: context.l10n.passwordFieldLabel,
                prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
                suffixIcon: PasswordVisibilityToggle(
                  obscured: _obscure,
                  onToggle: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            KeyfilesPicker(
              keyfiles: keyfiles,
              picking: pickingKeyfiles,
              onPick: pickKeyfiles,
              onRemove: removeKeyfile,
              enabled: !_busy,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: isEncrypt
                    ? Column(
                        key: const ValueKey('encrypt-extra-fields'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.sm),
                          OptionPickerTile<StandaloneCipher>(
                            label: context.l10n.singleFileCryptoCipherLabel,
                            value: _cipher,
                            prefixIcon: Icons.security_rounded,
                            options: StandaloneCipher.values
                                .map((c) => SelectOption(value: c, label: c.label))
                                .toList(),
                            onChanged: _busy ? (_) {} : (val) => setState(() => _cipher = val),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _deleteOriginal,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _deleteOriginal = v),
                            title: Text(
                              context.l10n.singleFileCryptoDeleteOriginalLabel,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey('decrypt-extra-fields')),
              ),
            ),
            if (_busy && _sources.length > 1) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.singleFileCryptoBatchProgressLabel(_currentIndex, _sources.length),
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (_progressTotal != null) ...[
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(
                value: _progressTotal! > 0
                    ? (_progressDone ?? 0) / _progressTotal!
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.splitJoinOperationProgress(
                  formatBytes(_progressDone ?? 0),
                  formatBytes(_progressTotal!),
                ),
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              InlineErrorBanner(_error!),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _busy ? null : _run,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
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
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
