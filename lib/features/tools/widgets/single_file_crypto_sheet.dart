import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/container_tool_service.dart';

class SingleFileCryptoSheet extends StatefulWidget {
  const SingleFileCryptoSheet({super.key});

  @override
  State<SingleFileCryptoSheet> createState() => _SingleFileCryptoSheetState();
}

class _SingleFileCryptoSheetState extends State<SingleFileCryptoSheet>
    with KeyfilePickerMixin {
  CryptoDirection _direction = CryptoDirection.encrypt;
  StandaloneCipher _cipher = StandaloneCipher.xChaCha20Poly1305;
  final List<KeyfileRef> _sources = [];
  String? _destPath;
  String? _destName;
  String? _destTreeUri;
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _deleteOriginal = false;
  bool _busy = false;
  String? _error;
  // Which file (1-based, within _sources) the current run is on, plus
  // that file's own byte progress -- shown as "File {current} of {total}"
  // above the existing per-file LinearProgressIndicator.
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

  Future<void> _addSources() async {
    final picked = await vaultExplorerApi.pickCryptoFiles();
    if (picked.isEmpty || !mounted) return;
    setState(() {
      final existingUris = _sources.map((f) => f.uri).toSet();
      for (final file in picked) {
        if (existingUris.add(file.uri)) _sources.add(file);
      }
      _error = null;
    });
  }

  void _removeSource(KeyfileRef file) {
    setState(() => _sources.remove(file));
  }

  void _clearSources() {
    setState(() => _sources.clear());
  }

  Future<void> _pickDestinationFolder() async {
    final picked = await vaultExplorerApi.pickExtractFolder();
    if (picked == null || !mounted) return;
    setState(() {
      _destPath = picked.path;
      _destName = picked.displayName;
      _destTreeUri = picked.treeUri;
      _error = null;
    });
  }

  Future<void> _run() async {
    if (_sources.isEmpty) {
      setState(() => _error = context.l10n.noFileSelectedLabel);
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

    // No native batch API exists (encryptSingleFile/decryptSingleFile take
    // one URI per call) -- run the queue sequentially here instead,
    // reusing the same per-file progress callback for each one. A wrong
    // password/keyfile combo applies to every remaining file too, so that
    // one case aborts the whole run rather than grinding through it;
    // any other per-file failure is recorded and the batch continues.
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

      try {
        if (_direction == CryptoDirection.encrypt) {
          await ContainerToolService.instance.encryptFile(
            sourceUri: source.uri,
            cipher: _cipher,
            passphrase: _passwordCtrl.text,
            keyfilePaths: keyfilePaths,
            deleteOriginalAfter: _deleteOriginal,
            destinationPath: _destPath,
            destinationTreeUri: _destTreeUri,
            onProgress: onProgress,
          );
        } else {
          await ContainerToolService.instance.decryptFile(
            sourceUri: source.uri,
            passphrase: _passwordCtrl.text,
            keyfilePaths: keyfilePaths,
            destinationPath: _destPath,
            destinationTreeUri: _destTreeUri,
            onProgress: onProgress,
          );
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
                      Icon(Icons.description_outlined, size: AppIconSize.small, color: cs.primary),
                      const SizedBox(width: 10),
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
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
                    Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
                    for (final file in _sources)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                file.displayName,
                                style: textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              visualDensity: VisualDensity.compact,
                              onPressed: _busy ? null : () => _removeSource(file),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _clearSources,
                        child: Text(context.l10n.singleFileCryptoClearFilesButton),
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
                  Icon(Icons.folder_outlined, size: AppIconSize.small, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.splitDestinationFolderLabel,
                          style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        Text(
                          _destName ?? context.l10n.noFolderSelectedLabel,
                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busy ? null : _pickDestinationFolder,
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