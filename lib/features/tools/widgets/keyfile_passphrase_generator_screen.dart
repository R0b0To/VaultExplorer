// File: lib/features/tools/widgets/keyfile_passphrase_generator_screen.dart

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/utils/sensitive_clipboard.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/services/keyfile_passphrase_generator_service.dart';

enum GeneratorTab { passphrase, keyfile }

enum PassphraseMode { diceware, custom }

enum KeyfileType { binary, image }

class KeyfilePassphraseGeneratorScreen extends StatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;

  const KeyfilePassphraseGeneratorScreen({
    super.key,
    required this.mountedContainers,
  });

  @override
  State<KeyfilePassphraseGeneratorScreen> createState() =>
      _KeyfilePassphraseGeneratorScreenState();
}

class _KeyfilePassphraseGeneratorScreenState
    extends State<KeyfilePassphraseGeneratorScreen> {
  GeneratorTab _selectedTab = GeneratorTab.passphrase;

  // ── Passphrase State ────────────────────────────────────────────────────────
  PassphraseMode _passphraseMode = PassphraseMode.diceware;

  // Diceware controls
  int _dicewareWordCount = 5;
  String _dicewareSeparator = '-';
  PasswordCasing _dicewareCasing = PasswordCasing.lowercase;
  bool _dicewareIncludeNumber = false;
  bool _dicewareIncludeSymbol = false;

  // Custom password controls
  int _customLength = 24;
  bool _customUseUppercase = true;
  bool _customUseLowercase = true;
  bool _customUseNumbers = true;
  bool _customUseSymbols = true;
  bool _customExcludeAmbiguous = false;

  // Generated output & Async State
  String _generatedPassphrase = '';
  double _passphraseEntropyBits = 0.0;
  bool _isLoadingPassphrase = false;
  int _activePassphraseRequestId = 0;

  // ── Keyfile State ───────────────────────────────────────────────────────────
  KeyfileType _keyfileType = KeyfileType.binary;
  KeyfileSizePreset _binaryPreset = KeyfileSizePreset.bytes64;
  ImageKeyfileResolution _imagePreset = ImageKeyfileResolution.res256;

  Uint8List? _generatedKeyfileBytes;
  String _keyfileFingerprint = '';
  String _keyfileSuggestedName = '';

  List<MountedContainer> _openVaults = [];
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _regeneratePassphrase();
    _regenerateKeyfile();
    _loadOpenVaults();
  }

  void _loadOpenVaults() {
    setState(() {
      _openVaults = widget.mountedContainers.value;
    });
  }

  Future<void> _regeneratePassphrase() async {
    final requestId = ++_activePassphraseRequestId;

    setState(() {
      _isLoadingPassphrase = true;
    });

    try {
      if (_passphraseMode == PassphraseMode.diceware) {
        final res =
            await KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
          wordCount: _dicewareWordCount,
          separator: _dicewareSeparator,
          casing: _dicewareCasing,
          includeNumber: _dicewareIncludeNumber,
          includeSymbol: _dicewareIncludeSymbol,
        );

        if (!mounted || requestId != _activePassphraseRequestId) return;

        setState(() {
          _generatedPassphrase = res.passphrase;
          _passphraseEntropyBits = res.entropyBits;
          _isLoadingPassphrase = false;
        });
      } else {
        final res = KeyfilePassphraseGeneratorService.generateCustomPassword(
          length: _customLength,
          useUppercase: _customUseUppercase,
          useLowercase: _customUseLowercase,
          useNumbers: _customUseNumbers,
          useSymbols: _customUseSymbols,
          excludeAmbiguous: _customExcludeAmbiguous,
        );

        if (!mounted || requestId != _activePassphraseRequestId) return;

        setState(() {
          _generatedPassphrase = res.password;
          _passphraseEntropyBits = res.entropyBits;
          _isLoadingPassphrase = false;
        });
      }
    } catch (e, stack) {
      debugPrint('Error generating passphrase: $e\n$stack');
      if (!mounted || requestId != _activePassphraseRequestId) return;

      setState(() {
        _isLoadingPassphrase = false;
        _generatedPassphrase = '';
        _passphraseEntropyBits = 0.0;
      });

      showAppSnackBar(
        context,
        message: e.toString(),
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _regenerateKeyfile() async {
    try {
      final nowStr =
          DateTime.now().millisecondsSinceEpoch.toString().substring(7);
      if (_keyfileType == KeyfileType.binary) {
        final bytes = KeyfilePassphraseGeneratorService.generateBinaryKeyfile(
          _binaryPreset.bytes,
        );
        final fp =
            await KeyfilePassphraseGeneratorService.calculateKeyfileFingerprint(
          bytes,
        );
        if (!mounted) return;
        setState(() {
          _generatedKeyfileBytes = bytes;
          _keyfileFingerprint = fp;
          _keyfileSuggestedName = 'vault_keyfile_$nowStr.key';
        });
      } else {
        final bytes =
            await KeyfilePassphraseGeneratorService.generateImageKeyfile(
          _imagePreset.dimension,
        );
        final fp =
            await KeyfilePassphraseGeneratorService.calculateKeyfileFingerprint(
          bytes,
        );
        if (!mounted) return;
        setState(() {
          _generatedKeyfileBytes = bytes;
          _keyfileFingerprint = fp;
          _keyfileSuggestedName =
              'vault_keyfile_${_imagePreset.dimension}x${_imagePreset.dimension}_$nowStr.png';
        });
      }
    } catch (e, stack) {
      debugPrint('Error generating keyfile: $e\n$stack');
    }
  }

  Future<void> _copyPassphrase() async {
    if (_generatedPassphrase.isEmpty) return;
    await SensitiveClipboard.copy(_generatedPassphrase);
    if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.copyPassphraseSuccess,
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _copyFingerprint() async {
    if (_keyfileFingerprint.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _keyfileFingerprint));
    if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.copyFingerprintSuccess,
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _exportKeyfileToStorage() async {
    if (_generatedKeyfileBytes == null) return;
    final folder = await vaultExplorerApi.pickExtractFolder();
    if (folder == null || !mounted) return;

    setState(() => _isExporting = true);
    try {
      await vaultExplorerApi.writeExternalFileBytes(
        destinationPath: folder.path,
        destinationTreeUri: folder.treeUri,
        fileName: _keyfileSuggestedName,
        bytes: _generatedKeyfileBytes!,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.keyfileExportSuccessMessage(
            '${folder.displayName}/$_keyfileSuggestedName',
          ),
          tone: AppBannerTone.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.keyfileExportFailedMessage(e),
          tone: AppBannerTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _saveKeyfileToMountedVault() async {
    if (_generatedKeyfileBytes == null) return;
    _loadOpenVaults();

    if (_openVaults.isEmpty) {
      showAppSnackBar(
        context,
        message: context.l10n.keyfileNoOpenVaultsMessage,
        tone: AppBannerTone.warning,
      );
      return;
    }

    final selectedVault = await showModalBottomSheet<MountedContainer>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  ctx.l10n.keyfileSelectDestinationVaultTitle,
                  style: ctx.typography.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              ..._openVaults.map(
                (vault) => ListTile(
                  leading: const Icon(Icons.lock_open_rounded),
                  title: Text(vault.displayName),
                  subtitle: Text(ctx.l10n.keyfileVolumeIdLabel(vault.volId)),
                  onTap: () => Navigator.pop(ctx, vault),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selectedVault == null || !mounted) return;

    setState(() => _isExporting = true);
    try {
      final vaultPath = '/$_keyfileSuggestedName';
      final ok = await vaultExplorerApi.writeFileChunk(
        selectedVault,
        vaultPath,
        0,
        _generatedKeyfileBytes!,
      );

      if (ok && mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.keyfileSavedToVaultMessage(
            selectedVault.displayName,
            vaultPath,
          ),
          tone: AppBannerTone.success,
        );
      } else if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.keyfileWriteFailedMessage,
          tone: AppBannerTone.error,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.keyfileSaveErrorMessage(e),
          tone: AppBannerTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final isLandscape = context.screen.useWideLayout;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.keyfilePassphraseGeneratorTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        elevation: 0,
        backgroundColor: cs.surfaceContainerHigh,
        actions: [
          if (isLandscape) ...[
            _buildTabSegment(context, isCompact: true),
            const SizedBox(width: 12),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!isLandscape) _buildTabSegment(context, isCompact: false),
            Expanded(
              child: isLandscape
                  ? _buildLandscapeLayout(context)
                  : _buildPortraitLayout(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabSegment(BuildContext context, {required bool isCompact}) {
    final cs = context.colors;
    return Container(
      width: isCompact ? null : double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 0 : 12,
        vertical: isCompact ? 4 : 6,
      ),
      color: isCompact ? Colors.transparent : cs.surface,
      child: SegmentedButton<GeneratorTab>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        segments: [
          ButtonSegment(
            value: GeneratorTab.passphrase,
            icon: const Icon(Icons.password_rounded, size: 18),
            label: Text(
              context.l10n.tabPassphrase,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
          ButtonSegment(
            value: GeneratorTab.keyfile,
            icon: const Icon(Icons.vpn_key_rounded, size: 18),
            label: Text(
              context.l10n.tabKeyfile,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
        ],
        selected: {_selectedTab},
        onSelectionChanged: (set) {
          setState(() => _selectedTab = set.first);
        },
      ),
    );
  }

  // ── LANDSCAPE 2-COLUMN LAYOUT ───────────────────────────────────────────────

  Widget _buildLandscapeLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: _selectedTab == GeneratorTab.passphrase
                  ? _buildUnifiedPassphraseOutputCard(context)
                  : _buildUnifiedKeyfileOutputCard(context),
            ),
          ),
          const SizedBox(width: 12),
          const VerticalDivider(width: 1),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              child: _selectedTab == GeneratorTab.passphrase
                  ? _buildPassphraseControls(context)
                  : _buildKeyfileControls(context),
            ),
          ),
        ],
      ),
    );
  }

  // ── PORTRAIT SINGLE-COLUMN LAYOUT ──────────────────────────────────────────

  Widget _buildPortraitLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selectedTab == GeneratorTab.passphrase) ...[
            _buildUnifiedPassphraseOutputCard(context),
            const SizedBox(height: 10),
            _buildPassphraseControls(context),
          ] else ...[
            _buildUnifiedKeyfileOutputCard(context),
            const SizedBox(height: 10),
            _buildKeyfileControls(context),
          ],
        ],
      ),
    );
  }

  // ── PASSPHRASE VIEWS ───────────────────────────────────────────────────────

  Widget _buildUnifiedPassphraseOutputCard(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final strength = KeyfilePassphraseGeneratorService.evaluatePasswordStrength(
      _passphraseEntropyBits,
    );

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.passphraseGeneratedSecretLabel,
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  tooltip: context.l10n.copyToClipboardTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: _isLoadingPassphrase || _generatedPassphrase.isEmpty
                      ? null
                      : _copyPassphrase,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: context.l10n.generateNewTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      _isLoadingPassphrase ? null : _regeneratePassphrase,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 68, maxHeight: 90),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border:
                    Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: _isLoadingPassphrase
                  ? Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      ),
                    )
                  : Scrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _generatedPassphrase,
                          style: textTheme.titleMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Live Entropy & Strength Details
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 16,
                  color: _colorForStrength(strength.scoreFraction),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.l10n.passphraseStrengthLabel(
                      _strengthLevelLabel(context, strength.level),
                    ),
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _colorForStrength(strength.scoreFraction),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.passphraseEntropyBitsLabel(
                    _passphraseEntropyBits.toStringAsFixed(1),
                  ),
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: _isLoadingPassphrase ? null : strength.scoreFraction,
                minHeight: 5,
                color: _colorForStrength(strength.scoreFraction),
                backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.passphraseCrackTimeLabel(
                _crackTimeLabel(context, strength.crackTime),
              ),
              style: textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassphraseControls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<PassphraseMode>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          segments: [
            ButtonSegment(
              value: PassphraseMode.diceware,
              icon: const Icon(Icons.casino_outlined, size: 18),
              label: Text(
                context.l10n.modeDiceware,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
            ButtonSegment(
              value: PassphraseMode.custom,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(
                context.l10n.modeCustomPassword,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
          ],
          selected: {_passphraseMode},
          onSelectionChanged: (set) {
            setState(() {
              _passphraseMode = set.first;
              _regeneratePassphrase();
            });
          },
        ),
        const SizedBox(height: 10),
        _passphraseMode == PassphraseMode.diceware
            ? _buildDicewareControls(context)
            : _buildCustomPasswordControls(context),
      ],
    );
  }

  Widget _buildDicewareControls(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.dicewareOptionsTitle,
              style:
                  textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.dicewareWordCountLabel(_dicewareWordCount),
                    style: textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.dicewareWordCountBitsLabel(
                    (_dicewareWordCount * 12.9).toStringAsFixed(0),
                  ),
                  style: textTheme.labelSmall?.copyWith(color: cs.primary),
                ),
              ],
            ),
            Slider(
              value: _dicewareWordCount.toDouble(),
              min: 3,
              max: 12,
              divisions: 9,
              label:
                  context.l10n.dicewareWordCountSliderLabel(_dicewareWordCount),
              onChanged: (val) {
                setState(() {
                  _dicewareWordCount = val.toInt();
                });
              },
              onChangeEnd: (val) {
                _regeneratePassphrase();
              },
            ),
            const Divider(height: 10),
Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.dicewareWordSeparatorLabel,
                    style: textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 130,
                  child: DropdownButton<String>(
                    value: _dicewareSeparator,
                    underline: const SizedBox(),
                    isDense: true,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(
                        value: '-',
                        child: Text(context.l10n.dicewareSeparatorHyphen),
                      ),
                      DropdownMenuItem(
                        value: ' ',
                        child: Text(context.l10n.dicewareSeparatorSpace),
                      ),
                      DropdownMenuItem(
                        value: '_',
                        child: Text(context.l10n.dicewareSeparatorUnderscore),
                      ),
                      DropdownMenuItem(
                        value: '.',
                        child: Text(context.l10n.dicewareSeparatorDot),
                      ),
                      DropdownMenuItem(
                        value: '/',
                        child: Text(context.l10n.dicewareSeparatorSlash),
                      ),
                    ],
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        _dicewareSeparator = val;
                        _regeneratePassphrase();
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.dicewareWordCasingLabel,
                    style: textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 130,
                  child: DropdownButton<PasswordCasing>(
                    value: _dicewareCasing,
                    underline: const SizedBox(),
                    isDense: true,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(
                        value: PasswordCasing.lowercase,
                        child: Text(context.l10n.dicewareCasingLowercase),
                      ),
                      DropdownMenuItem(
                        value: PasswordCasing.titleCase,
                        child: Text(context.l10n.dicewareCasingTitleCase),
                      ),
                      DropdownMenuItem(
                        value: PasswordCasing.uppercase,
                        child: Text(context.l10n.dicewareCasingUppercase),
                      ),
                    ],
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        _dicewareCasing = val;
                        _regeneratePassphrase();
                      });
                    },
                  ),
                ),
              ],
            ),
            const Divider(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                context.l10n.dicewareAppendDigitLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: _dicewareIncludeNumber,
              onChanged: (val) {
                setState(() {
                  _dicewareIncludeNumber = val;
                  _regeneratePassphrase();
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                context.l10n.dicewareAppendSymbolLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: _dicewareIncludeSymbol,
              onChanged: (val) {
                setState(() {
                  _dicewareIncludeSymbol = val;
                  _regeneratePassphrase();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomPasswordControls(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.customPasswordOptionsTitle,
              style:
                  textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.customPasswordLengthLabel(_customLength),
              style:
                  textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Slider(
              value: _customLength.toDouble(),
              min: 8,
              max: 128,
              divisions: 120,
              label:
                  context.l10n.customPasswordLengthSliderLabel(_customLength),
              onChanged: (val) {
                setState(() {
                  _customLength = val.toInt();
                });
              },
              onChangeEnd: (val) {
                _regeneratePassphrase();
              },
            ),
            const Divider(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                context.l10n.customPasswordUppercaseLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: _customUseUppercase,
              onChanged: (val) {
                setState(() {
                  _customUseUppercase = val;
                  _regeneratePassphrase();
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                context.l10n.customPasswordLowercaseLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: _customUseLowercase,
              onChanged: (val) {
                setState(() {
                  _customUseLowercase = val;
                  _regeneratePassphrase();
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                context.l10n.customPasswordNumbersLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: _customUseNumbers,
              onChanged: (val) {
                setState(() {
                  _customUseNumbers = val;
                  _regeneratePassphrase();
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                context.l10n.customPasswordSymbolsLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: _customUseSymbols,
              onChanged: (val) {
                setState(() {
                  _customUseSymbols = val;
                  _regeneratePassphrase();
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                context.l10n.customPasswordExcludeAmbiguousLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: _customExcludeAmbiguous,
              onChanged: (val) {
                setState(() {
                  _customExcludeAmbiguous = val;
                  _regeneratePassphrase();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── KEYFILE VIEWS ──────────────────────────────────────────────────────────

  Widget _buildUnifiedKeyfileOutputCard(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _keyfileType == KeyfileType.binary
                      ? Icons.insert_drive_file_rounded
                      : Icons.image_rounded,
                  color: cs.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _keyfileSuggestedName,
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: context.l10n.keyfileGenerateNewTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: _regenerateKeyfile,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.keyfileSizeLabel(
                formatBytes(_generatedKeyfileBytes?.length ?? 0),
              ),
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),

            // Fingerprint Chip
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.keyfileFingerprintLabel,
                    style: textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  tooltip: context.l10n.keyfileCopyFingerprintTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: _copyFingerprint,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border:
                    Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: SelectableText(
                _keyfileFingerprint,
                style: textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: cs.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Responsive Action Buttons
            LayoutBuilder(
              builder: (context, constraints) {
                final isVeryNarrow = constraints.maxWidth < 280;

                final exportBtn = FilledButton.icon(
                  onPressed: _isExporting ? null : _exportKeyfileToStorage,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: Text(
                    context.l10n.exportKeyfileToStorage,
                    maxLines: 3,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                );

                final saveBtn = OutlinedButton.icon(
                  onPressed: _isExporting ? null : _saveKeyfileToMountedVault,
                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                  label: Text(
                    context.l10n.saveKeyfileToVault,
                    maxLines: 3,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                );

                if (isVeryNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      exportBtn,
                      const SizedBox(height: 8),
                      saveBtn,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: exportBtn),
                    const SizedBox(width: 1),
                    Expanded(child: saveBtn),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyfileControls(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<KeyfileType>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: KeyfileType.binary,
              icon: const Icon(Icons.memory_outlined, size: 18),
              label: Text(
                context.l10n.keyfileTypeBinary,
                maxLines: 3,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
            ButtonSegment(
              value: KeyfileType.image,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(
                context.l10n.keyfileTypeImage,
                maxLines: 3,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
          ],
          selected: {_keyfileType},
          onSelectionChanged: (set) {
            setState(() {
              _keyfileType = set.first;
              _regenerateKeyfile();
            });
          },
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _keyfileType == KeyfileType.binary
                      ? context.l10n.keyfileBinarySizeTitle
                      : context.l10n.keyfileImageResolutionTitle,
                  style:
                      textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                if (_keyfileType == KeyfileType.binary)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: KeyfileSizePreset.values.map((preset) {
                      final isSelected = _binaryPreset == preset;
                      return ChoiceChip(
                        label: Text(
                          _binaryPresetLabel(context, preset),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: isSelected,
                        showCheckmark: false,
                        onSelected: (sel) {
                          if (sel) {
                            setState(() {
                              _binaryPreset = preset;
                              _regenerateKeyfile();
                            });
                          }
                        },
                      );
                    }).toList(),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ImageKeyfileResolution.values.map((preset) {
                      final isSelected = _imagePreset == preset;
                      return ChoiceChip(
                        label: Text(
                          _imagePresetLabel(context, preset),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: isSelected,
                        showCheckmark: false,
                        onSelected: (sel) {
                          if (sel) {
                            setState(() {
                              _imagePreset = preset;
                              _regenerateKeyfile();
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── STRENGTH HELPERS ───────────────────────────────────────────────────────

  Color _colorForStrength(double fraction) {
    if (fraction < 0.35) return Colors.redAccent;
    if (fraction < 0.65) return Colors.orangeAccent;
    if (fraction < 0.9) return Colors.green;
    return Colors.purpleAccent;
  }

  String _strengthLevelLabel(
      BuildContext context, PasswordStrengthLevel level) {
    return switch (level) {
      PasswordStrengthLevel.weak => context.l10n.passphraseStrengthWeak,
      PasswordStrengthLevel.good => context.l10n.passphraseStrengthGood,
      PasswordStrengthLevel.strong => context.l10n.passphraseStrengthStrong,
      PasswordStrengthLevel.unbreakable =>
        context.l10n.passphraseStrengthUnbreakable,
    };
  }

  String _crackTimeLabel(
      BuildContext context, PasswordCrackTimeEstimate estimate) {
    return switch (estimate) {
      PasswordCrackTimeEstimate.instant =>
        context.l10n.passphraseCrackTimeInstant,
      PasswordCrackTimeEstimate.shortTerm =>
        context.l10n.passphraseCrackTimeShort,
      PasswordCrackTimeEstimate.centuries =>
        context.l10n.passphraseCrackTimeCenturies,
      PasswordCrackTimeEstimate.millionsOfYears =>
        context.l10n.passphraseCrackTimeMillionsOfYears,
    };
  }

  String _binaryPresetLabel(BuildContext context, KeyfileSizePreset preset) {
    return switch (preset) {
      KeyfileSizePreset.bytes64 => context.l10n.keyfilePresetBytes64,
      KeyfileSizePreset.bytes256 => context.l10n.keyfilePresetBytes256,
      KeyfileSizePreset.bytes2048 => context.l10n.keyfilePresetBytes2048,
      KeyfileSizePreset.bytes64kb => context.l10n.keyfilePresetBytes64kb,
      KeyfileSizePreset.bytes1mb => context.l10n.keyfilePresetBytes1mb,
    };
  }

  String _imagePresetLabel(
      BuildContext context, ImageKeyfileResolution preset) {
    return switch (preset) {
      ImageKeyfileResolution.res64 => context.l10n.keyfilePresetRes64,
      ImageKeyfileResolution.res256 => context.l10n.keyfilePresetRes256,
      ImageKeyfileResolution.res512 => context.l10n.keyfilePresetRes512,
    };
  }
}