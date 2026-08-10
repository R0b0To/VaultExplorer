import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/container_tool_service.dart';

class CryptoSourceItem {
  final String displayName;
  final String? externalUri;
  final MountedContainer? container;
  final String? relativePath;
  final bool isFromVault;

  const CryptoSourceItem.external({
    required this.displayName,
    required this.externalUri,
  })  : container = null,
        relativePath = null,
        isFromVault = false;

  const CryptoSourceItem.vault({
    required this.displayName,
    required this.container,
    required this.relativePath,
  })  : externalUri = null,
        isFromVault = true;

  String get id => isFromVault
      ? 'vault:${container!.volId}:$relativePath'
      : 'ext:$externalUri';
}

class CryptoDestination {
  final String displayName;
  final String? externalPath;
  final String? externalTreeUri;
  final MountedContainer? container;
  final String? relativePath;
  final bool isVault;

  const CryptoDestination.external({
    required this.displayName,
    required this.externalPath,
    this.externalTreeUri,
  })  : container = null,
        relativePath = null,
        isVault = false;

  const CryptoDestination.vault({
    required this.displayName,
    required this.container,
    required this.relativePath,
  })  : externalPath = null,
        externalTreeUri = null,
        isVault = true;
}

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
                'Select Input Files',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            SheetOptionTile(
              icon: Icons.sd_storage_outlined,
              title: 'From Device Storage',
              subtitle: 'Pick files from device using system file picker',
              onTap: () {
                Navigator.pop(ctx);
                _addExternalSources();
              },
            ),
            SheetOptionTile(
              icon: Icons.lock_open_rounded,
              iconColor: Theme.of(ctx).colorScheme.tertiary,
              title: 'From Mounted Vault',
              subtitle: 'Pick files from an open encrypted container',
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
        builder: (_) => _VaultFilePickerSheet(mountedContainers: mountedVaults),
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
                'Select Destination Folder',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            SheetOptionTile(
              icon: Icons.folder_open_rounded,
              title: 'Device Storage Folder',
              subtitle: 'Save output to a folder on device storage',
              onTap: () {
                Navigator.pop(ctx);
                _pickExternalDestination();
              },
            ),
            SheetOptionTile(
              icon: Icons.lock_open_rounded,
              iconColor: Theme.of(ctx).colorScheme.tertiary,
              title: 'Mounted Vault Folder',
              subtitle: 'Save output inside an open encrypted container',
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
        builder: (_) => _VaultFolderPickerSheet(mountedContainers: mountedVaults),
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
    void onProgress(int done, int total) {
      if (!mounted) return;
      setState(() {
        _progressDone = done;
        _progressTotal = total;
      });
    }

    final failedNames = <String>[];
    var succeeded = 0;

    for (var i = 0; i < _sources.length; i++) {
      final source = _sources[i];
      if (!mounted) return;
      setState(() {
        _currentIndex = i + 1;
        _progressDone = 0;
        _progressTotal = null;
      });

      Directory? tempInDir;
      Directory? tempOutDir;

      try {
        // 1. Prepare input file path/URI
        String effectiveSourceUri;

        if (source.isFromVault) {
          tempInDir = await Directory.systemTemp.createTemp('vx_crypto_in_');
          final tempInFile = File(p.join(tempInDir.path, source.displayName));
          final extracted = await vaultExplorerApi.decryptFile(
            source.container!,
            source.relativePath!,
            tempInFile.path,
          );
          if (!extracted || !tempInFile.existsSync()) {
            throw Exception('Failed to extract file from source vault');
          }
          effectiveSourceUri = Uri.file(tempInFile.path).toString();
        } else {
          effectiveSourceUri = source.externalUri!;
        }

        // 2. Prepare destination path
        String? effectiveDestPath;
        String? effectiveTreeUri;

        if (dest.isVault) {
          tempOutDir = await Directory.systemTemp.createTemp('vx_crypto_out_');
          effectiveDestPath = tempOutDir.path;
          effectiveTreeUri = null;
        } else {
          effectiveDestPath = dest.externalPath;
          effectiveTreeUri = dest.externalTreeUri;
        }

        // 3. Execute Crypto Operation
        if (_direction == CryptoDirection.encrypt) {
          await ContainerToolService.instance.encryptFile(
            sourceUri: effectiveSourceUri,
            cipher: _cipher,
            passphrase: _passwordCtrl.text,
            keyfilePaths: keyfilePaths,
            deleteOriginalAfter: source.isFromVault ? false : _deleteOriginal,
            destinationPath: effectiveDestPath,
            destinationTreeUri: effectiveTreeUri,
            onProgress: onProgress,
          );
        } else {
          await ContainerToolService.instance.decryptFile(
            sourceUri: effectiveSourceUri,
            passphrase: _passwordCtrl.text,
            keyfilePaths: keyfilePaths,
            destinationPath: effectiveDestPath,
            destinationTreeUri: effectiveTreeUri,
            onProgress: onProgress,
          );
        }

        // 4. If destination is a vault, copy generated output file(s) into target vault
        if (dest.isVault && tempOutDir != null) {
          final generatedFiles = tempOutDir.listSync().whereType<File>().toList();
          if (generatedFiles.isEmpty) {
            throw Exception('No output file generated by crypto engine');
          }
          for (final outFile in generatedFiles) {
            final outFileName = p.basename(outFile.path);
            final vaultPath = dest.relativePath!.isEmpty
                ? outFileName
                : '${dest.relativePath!}/$outFileName';
            final wroteBack = await vaultExplorerApi.writeBackFile(
              dest.container!,
              vaultPath,
              outFile.path,
            );
            if (!wroteBack) {
              throw Exception('Failed to write output file to target vault');
            }
            await vaultExplorerApi.finishWriteIfCryptomator(
              dest.container!,
              vaultPath,
            );
          }
        }

        // 5. Delete source from vault if requested
        if (_deleteOriginal && _direction == CryptoDirection.encrypt && source.isFromVault) {
          await vaultExplorerApi.deleteFile(source.container!, source.relativePath!);
        }

        succeeded++;
      } on UnimplementedError {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = context.l10n.toolNotImplementedYetMessage;
          });
        }
        return;
      } on PlatformException catch (e) {
        if (e.code == 'AUTH_FAIL') {
          if (mounted) {
            setState(() {
              _busy = false;
              _error = context.l10n.incorrectPasswordError;
            });
          }
          return;
        }
        failedNames.add(source.displayName);
      } catch (_) {
        failedNames.add(source.displayName);
      } finally {
        if (tempInDir != null && tempInDir.existsSync()) {
          try {
            tempInDir.deleteSync(recursive: true);
          } catch (_) {}
        }
        if (tempOutDir != null && tempOutDir.existsSync()) {
          try {
            tempOutDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    }

    if (!mounted) return;

    if (failedNames.isEmpty) {
      Navigator.of(context).pop();
      showAppSnackBar(
        context,
        message: context.l10n.singleFileCryptoSuccessMessage(succeeded),
        tone: AppBannerTone.success,
      );
    } else if (succeeded > 0) {
      Navigator.of(context).pop();
      showAppSnackBar(
        context,
        message: context.l10n.singleFileCryptoPartialFailureMessage(
          succeeded,
          _sources.length,
          failedNames.length,
        ),
        tone: AppBannerTone.warning,
      );
    } else {
      setState(() {
        _busy = false;
        _error = context.l10n.singleFileCryptoPartialFailureMessage(
          succeeded,
          _sources.length,
          failedNames.length,
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

class _VaultFilePickerSheet extends StatefulWidget {
  final List<MountedContainer> mountedContainers;

  const _VaultFilePickerSheet({required this.mountedContainers});

  @override
  State<_VaultFilePickerSheet> createState() => _VaultFilePickerSheetState();
}

class _VaultFilePickerSheetState extends State<_VaultFilePickerSheet> {
  late MountedContainer _selectedContainer;
  final List<String> _pathStack = [''];
  List<RawEntry> _currentItems = [];
  bool _loading = false;
  final Map<String, CryptoSourceItem> _selectedItems = {};

  String get _currentPath => _pathStack.last;

  @override
  void initState() {
    super.initState();
    _selectedContainer = widget.mountedContainers.first;
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() => _loading = true);
    try {
      final rawList =
          await vaultExplorerApi.listDirectory(_selectedContainer, path);
      final entries = RawEntry.parseAll(rawList ?? []);
      entries.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (mounted) {
        setState(() {
          _currentItems = entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateToFolder(String folderName) {
    final newPath =
        _currentPath.isEmpty ? folderName : '$_currentPath/$folderName';
    _pathStack.add(newPath);
    _loadDirectory(newPath);
  }

  void _navigateUp() {
    if (_pathStack.length > 1) {
      _pathStack.removeLast();
      _loadDirectory(_currentPath);
    }
  }

  void _toggleFileSelection(RawEntry entry) {
    final relPath =
        _currentPath.isEmpty ? entry.name : '$_currentPath/${entry.name}';
    final key = '${_selectedContainer.volId}:$relPath';
    setState(() {
      if (_selectedItems.containsKey(key)) {
        _selectedItems.remove(key);
      } else {
        _selectedItems[key] = CryptoSourceItem.vault(
          displayName: entry.name,
          container: _selectedContainer,
          relativePath: relPath,
        );
      }
    });
  }

  void _confirmSelection() {
    Navigator.pop(context, _selectedItems.values.toList());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Select Files (${_selectedContainer.displayName})'),
        leading: _pathStack.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _navigateUp,
              )
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
        actions: [
          if (widget.mountedContainers.length > 1)
            PopupMenuButton<MountedContainer>(
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: 'Switch Vault',
              onSelected: (container) {
                if (container != _selectedContainer) {
                  setState(() {
                    _selectedContainer = container;
                    _pathStack.clear();
                    _pathStack.add('');
                  });
                  _loadDirectory('');
                }
              },
              itemBuilder: (ctx) => widget.mountedContainers
                  .map(
                    (c) => PopupMenuItem(
                      value: c,
                      child: Text(c.displayName),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: cs.surfaceContainerLow,
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentPath.isEmpty ? 'Root Folder' : _currentPath,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _currentItems.isEmpty
                    ? Center(
                        child: Text(
                          'Folder is empty',
                          style: textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _currentItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final entry = _currentItems[i];
                          if (entry.isDir) {
                            return ListTile(
                              leading: Icon(
                                Icons.folder_rounded,
                                color: cs.secondary,
                              ),
                              title: Text(entry.name),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _navigateToFolder(entry.name),
                            );
                          }
                          final relPath = _currentPath.isEmpty
                              ? entry.name
                              : '$_currentPath/${entry.name}';
                          final key = '${_selectedContainer.volId}:$relPath';
                          final isSelected = _selectedItems.containsKey(key);

                          return ListTile(
                            leading: Icon(
                              iconForFile(entry.name),
                              color: colorForFile(entry.name),
                            ),
                            title: Text(entry.name),
                            subtitle: Text(formatBytes(entry.sizeBytes)),
                            trailing: Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleFileSelection(entry),
                            ),
                            onTap: () => _toggleFileSelection(entry),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: SafeArea(
          child: FilledButton(
            onPressed: _selectedItems.isNotEmpty ? _confirmSelection : null,
            child: Text('Select ${_selectedItems.length} File(s)'),
          ),
        ),
      ),
    );
  }
}

class _VaultFolderPickerSheet extends StatefulWidget {
  final List<MountedContainer> mountedContainers;

  const _VaultFolderPickerSheet({required this.mountedContainers});

  @override
  State<_VaultFolderPickerSheet> createState() =>
      _VaultFolderPickerSheetState();
}

class _VaultFolderPickerSheetState extends State<_VaultFolderPickerSheet> {
  late MountedContainer _selectedContainer;
  final List<String> _pathStack = [''];
  List<RawEntry> _currentFolders = [];
  bool _loading = false;

  String get _currentPath => _pathStack.last;

  @override
  void initState() {
    super.initState();
    _selectedContainer = widget.mountedContainers.first;
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() => _loading = true);
    try {
      final rawList =
          await vaultExplorerApi.listDirectory(_selectedContainer, path);
      final entries = RawEntry.parseAll(rawList ?? []);
      final folders = entries.where((e) => e.isDir).toList();
      folders.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _currentFolders = folders;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateToFolder(String folderName) {
    final newPath =
        _currentPath.isEmpty ? folderName : '$_currentPath/$folderName';
    _pathStack.add(newPath);
    _loadDirectory(newPath);
  }

  void _navigateUp() {
    if (_pathStack.length > 1) {
      _pathStack.removeLast();
      _loadDirectory(_currentPath);
    }
  }

  void _confirmSelection() {
    final folderName =
        _currentPath.isEmpty ? 'Root' : _currentPath.split('/').last;
    final displayName = '${_selectedContainer.displayName} / $folderName';
    Navigator.pop(
      context,
      CryptoDestination.vault(
        displayName: displayName,
        container: _selectedContainer,
        relativePath: _currentPath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Select Folder (${_selectedContainer.displayName})'),
        leading: _pathStack.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _navigateUp,
              )
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
        actions: [
          if (widget.mountedContainers.length > 1)
            PopupMenuButton<MountedContainer>(
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: 'Switch Vault',
              onSelected: (container) {
                if (container != _selectedContainer) {
                  setState(() {
                    _selectedContainer = container;
                    _pathStack.clear();
                    _pathStack.add('');
                  });
                  _loadDirectory('');
                }
              },
              itemBuilder: (ctx) => widget.mountedContainers
                  .map(
                    (c) => PopupMenuItem(
                      value: c,
                      child: Text(c.displayName),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: cs.surfaceContainerLow,
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentPath.isEmpty ? 'Root Folder' : _currentPath,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _currentFolders.isEmpty
                    ? Center(
                        child: Text(
                          'No subfolders here',
                          style: textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _currentFolders.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final entry = _currentFolders[i];
                          return ListTile(
                            leading: Icon(
                              Icons.folder_rounded,
                              color: cs.secondary,
                            ),
                            title: Text(entry.name),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _navigateToFolder(entry.name),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: SafeArea(
          child: FilledButton.icon(
            onPressed: _confirmSelection,
            icon: const Icon(Icons.check_rounded),
            label: Text(
              _currentPath.isEmpty
                  ? 'Select Root Folder'
                  : 'Select "${_currentPath.split('/').last}"',
            ),
          ),
        ),
      ),
    );
  }
}