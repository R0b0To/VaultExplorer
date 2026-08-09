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

/// File Cryptography → Single-File Encrypt/Decrypt.
///
/// Wraps one local file in a standalone AEAD container (or unwraps one
/// previously produced by this same tool) without needing a full
/// FAT/NTFS-backed volume -- see the design note's "File Cryptography
/// (Standalone)" section. Calls through [ContainerToolService], whose
/// [ContainerToolService.encryptFile]/[ContainerToolService.decryptFile]
/// are not implemented natively yet.
class SingleFileCryptoSheet extends StatefulWidget {
  const SingleFileCryptoSheet({super.key});

  @override
  State<SingleFileCryptoSheet> createState() => _SingleFileCryptoSheetState();
}

class _SingleFileCryptoSheetState extends State<SingleFileCryptoSheet>
    with KeyfilePickerMixin {
  CryptoDirection _direction = CryptoDirection.encrypt;
  StandaloneCipher _cipher = StandaloneCipher.xChaCha20Poly1305;

  String? _sourceUri;
  String? _sourceName;
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _deleteOriginal = false;

  bool _busy = false;
  String? _error;
  int? _progressDone;
  int? _progressTotal;

  @override
  void onKeyfilePickError(String message) => setState(() => _error = message);

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    // Generic ACTION_OPEN_DOCUMENT picker -- same one the Splitter's
    // "source file" field uses. Not restricted to container-shaped files,
    // which is fine here since it's already unfiltered ("*/*") on the
    // native side.
    final picked = await vaultExplorerApi.pickContainer();
    if (picked == null || !mounted) return;
    setState(() {
      _sourceUri = picked.uri;
      _sourceName = picked.displayName;
      _error = null;
    });
  }

  Future<void> _run() async {
    final source = _sourceUri;
    if (source == null) {
      setState(() => _error = context.l10n.noFileSelectedLabel);
      return;
    }
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _error = context.l10n.passwordFieldLabel);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
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

    try {
      if (_direction == CryptoDirection.encrypt) {
        await ContainerToolService.instance.encryptFile(
          sourceUri: source,
          cipher: _cipher,
          passphrase: _passwordCtrl.text,
          keyfilePaths: keyfilePaths,
          deleteOriginalAfter: _deleteOriginal,
          onProgress: onProgress,
        );
      } else {
        await ContainerToolService.instance.decryptFile(
          sourceUri: source,
          passphrase: _passwordCtrl.text,
          keyfilePaths: keyfilePaths,
          onProgress: onProgress,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnackBar(
        context,
        message: context.l10n.singleFileCryptoSuccessMessage,
        tone: AppBannerTone.success,
      );
    } on UnimplementedError {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.l10n.toolNotImplementedYetMessage;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message ?? '$e';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
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
              child: Row(
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
                          _sourceName ?? context.l10n.noFileSelectedLabel,
                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busy ? null : _pickSource,
                    child: Text(context.l10n.chooseFileButton),
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
                          Text(
                            context.l10n.singleFileCryptoCipherLabel,
                            style: textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: StandaloneCipher.values
                                .map(
                                  (c) => ChoiceChip(
                                    label: Text(c.label),
                                    selected: _cipher == c,
                                    onSelected: _busy
                                        ? null
                                        : (_) => setState(() => _cipher = c),
                                  ),
                                )
                                .toList(),
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
                          ? context.l10n.singleFileCryptoEncryptButton
                          : context.l10n.singleFileCryptoDecryptButton,
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