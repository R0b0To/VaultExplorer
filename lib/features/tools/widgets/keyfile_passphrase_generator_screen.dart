import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
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

  // Generated output
  String _generatedPassphrase = '';
  double _passphraseEntropyBits = 0.0;

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

  void _regeneratePassphrase() {
    if (_passphraseMode == PassphraseMode.diceware) {
      final res = KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
        wordCount: _dicewareWordCount,
        separator: _dicewareSeparator,
        casing: _dicewareCasing,
        includeNumber: _dicewareIncludeNumber,
        includeSymbol: _dicewareIncludeSymbol,
      );
      setState(() {
        _generatedPassphrase = res.passphrase;
        _passphraseEntropyBits = res.entropyBits;
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
      setState(() {
        _generatedPassphrase = res.password;
        _passphraseEntropyBits = res.entropyBits;
      });
    }
  }

  void _regenerateKeyfile() {
    final nowStr = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    if (_keyfileType == KeyfileType.binary) {
      final bytes = KeyfilePassphraseGeneratorService.generateBinaryKeyfile(
        _binaryPreset.bytes,
      );
      final fp = KeyfilePassphraseGeneratorService.calculateKeyfileFingerprint(
        bytes,
      );
      setState(() {
        _generatedKeyfileBytes = bytes;
        _keyfileFingerprint = fp;
        _keyfileSuggestedName = 'vault_keyfile_$nowStr.key';
      });
    } else {
      final bytes = KeyfilePassphraseGeneratorService.generateImageKeyfile(
        _imagePreset.dimension,
      );
      final fp = KeyfilePassphraseGeneratorService.calculateKeyfileFingerprint(
        bytes,
      );
      setState(() {
        _generatedKeyfileBytes = bytes;
        _keyfileFingerprint = fp;
        _keyfileSuggestedName =
            'vault_keyfile_${_imagePreset.dimension}x${_imagePreset.dimension}_$nowStr.png';
      });
    }
  }

  Future<void> _copyPassphrase() async {
    await vaultExplorerApi.setSensitiveClipboardText(_generatedPassphrase);
    if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.copyPassphraseSuccess,
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _copyFingerprint() async {
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
      final destFile = File('${folder.path}/$_keyfileSuggestedName');
      await destFile.writeAsBytes(_generatedKeyfileBytes!, flush: true);
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
    final textTheme = context.typography;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.keyfilePassphraseGeneratorTitle),
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildTopTabSegment(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _selectedTab == GeneratorTab.passphrase
                  ? _buildPassphraseView(context)
                  : _buildKeyfileView(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabSegment(BuildContext context) {
    final cs = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: cs.surface,
      child: SegmentedButton<GeneratorTab>(
        segments: [
          ButtonSegment(
            value: GeneratorTab.passphrase,
            icon: const Icon(Icons.password_rounded),
            label: Text(context.l10n.tabPassphrase),
          ),
          ButtonSegment(
            value: GeneratorTab.keyfile,
            icon: const Icon(Icons.vpn_key_rounded),
            label: Text(context.l10n.tabKeyfile),
          ),
        ],
        selected: {_selectedTab},
        onSelectionChanged: (set) {
          setState(() => _selectedTab = set.first);
        },
      ),
    );
  }

  // ── PASSPHRASE TAB VIEW ───────────────────────────────────────────────────

  Widget _buildPassphraseView(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final strength = KeyfilePassphraseGeneratorService.evaluatePasswordStrength(
      _passphraseEntropyBits,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mode Selector (Diceware vs Custom)
        SegmentedButton<PassphraseMode>(
          segments: [
            ButtonSegment(
              value: PassphraseMode.diceware,
              icon: const Icon(Icons.casino_outlined),
              label: Text(context.l10n.modeDiceware),
            ),
            ButtonSegment(
              value: PassphraseMode.custom,
              icon: const Icon(Icons.tune_rounded),
              label: Text(context.l10n.modeCustomPassword),
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

        const SizedBox(height: AppSpacing.lg),

        // Generated Output Display Card
        Card(
          elevation: 0,
          color: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      context.l10n.passphraseGeneratedSecretLabel,
                      style: textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: context.l10n.copyToClipboardTooltip,
                      onPressed: _copyPassphrase,
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: context.l10n.generateNewTooltip,
                      onPressed: _regeneratePassphrase,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: 96,
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SelectableText(
                          _generatedPassphrase,
                          style: textTheme.titleLarge?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Entropy & Strength Indicator Card
        Card(
          elevation: 0,
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 20,
                          color: _colorForStrength(strength.scoreFraction),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          context.l10n.passphraseStrengthLabel(strength.label),
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _colorForStrength(strength.scoreFraction),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      context.l10n.passphraseEntropyBitsLabel(
                        _passphraseEntropyBits.toStringAsFixed(1),
                      ),
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: LinearProgressIndicator(
                    value: strength.scoreFraction,
                    minHeight: 6,
                    color: _colorForStrength(strength.scoreFraction),
                    backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.l10n.passphraseCrackTimeLabel(strength.crackTimeStr),
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // Config Controls
        if (_passphraseMode == PassphraseMode.diceware)
          _buildDicewareControls(context)
        else
          _buildCustomPasswordControls(context),
      ],
    );
  }

  Widget _buildDicewareControls(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.dicewareOptionsTitle,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.dicewareWordCountLabel(_dicewareWordCount),
                  ),
                ),
                Text(
                  context.l10n.dicewareWordCountBitsLabel(
                    (_dicewareWordCount * 12.9).toStringAsFixed(0),
                  ),
                  style: textTheme.labelSmall?.copyWith(color: cs.secondary),
                ),
              ],
            ),
            Slider(
              value: _dicewareWordCount.toDouble(),
              min: 3,
              max: 12,
              divisions: 9,
              label: context.l10n.dicewareWordCountSliderLabel(_dicewareWordCount),
              onChanged: (val) {
                setState(() {
                  _dicewareWordCount = val.toInt();
                  _regeneratePassphrase();
                });
              },
            ),

            const Divider(),

            // Separator Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.l10n.dicewareWordSeparatorLabel),
                DropdownButton<String>(
                  value: _dicewareSeparator,
                  underline: const SizedBox(),
                  items: [
                    DropdownMenuItem(value: '-', child: Text(context.l10n.dicewareSeparatorHyphen)),
                    DropdownMenuItem(value: ' ', child: Text(context.l10n.dicewareSeparatorSpace)),
                    DropdownMenuItem(value: '_', child: Text(context.l10n.dicewareSeparatorUnderscore)),
                    DropdownMenuItem(value: '.', child: Text(context.l10n.dicewareSeparatorDot)),
                    DropdownMenuItem(value: '/', child: Text(context.l10n.dicewareSeparatorSlash)),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _dicewareSeparator = val;
                      _regeneratePassphrase();
                    });
                  },
                ),
              ],
            ),

            // Casing Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.l10n.dicewareWordCasingLabel),
                DropdownButton<PasswordCasing>(
                  value: _dicewareCasing,
                  underline: const SizedBox(),
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
              ],
            ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.dicewareAppendDigitLabel),
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
              title: Text(context.l10n.dicewareAppendSymbolLabel),
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
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.customPasswordOptionsTitle,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(context.l10n.customPasswordLengthLabel(_customLength)),
            Slider(
              value: _customLength.toDouble(),
              min: 8,
              max: 128,
              divisions: 120,
              label: context.l10n.customPasswordLengthSliderLabel(_customLength),
              onChanged: (val) {
                setState(() {
                  _customLength = val.toInt();
                  _regeneratePassphrase();
                });
              },
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.customPasswordUppercaseLabel),
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
              title: Text(context.l10n.customPasswordLowercaseLabel),
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
              title: Text(context.l10n.customPasswordNumbersLabel),
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
              title: Text(context.l10n.customPasswordSymbolsLabel),
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
              title: Text(context.l10n.customPasswordExcludeAmbiguousLabel),
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

  // ── KEYFILE TAB VIEW ─────────────────────────────────────────────────────

  Widget _buildKeyfileView(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Keyfile Type Selector
        SegmentedButton<KeyfileType>(
          segments: [
            ButtonSegment(
              value: KeyfileType.binary,
              icon: const Icon(Icons.memory_outlined),
              label: Text(context.l10n.keyfileTypeBinary),
            ),
            ButtonSegment(
              value: KeyfileType.image,
              icon: const Icon(Icons.image_outlined),
              label: Text(context.l10n.keyfileTypeImage),
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

        const SizedBox(height: AppSpacing.lg),

        // Size Presets Selector Card
        Card(
          elevation: 0,
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _keyfileType == KeyfileType.binary
                      ? context.l10n.keyfileBinarySizeTitle
                      : context.l10n.keyfileImageResolutionTitle,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_keyfileType == KeyfileType.binary)
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: KeyfileSizePreset.values.map((preset) {
                      final isSelected = _binaryPreset == preset;
                      return ChoiceChip(
                        label: Text(preset.label),
                        selected: isSelected,
                        showCheckmark: false,
                        labelStyle: textTheme.labelLarge?.copyWith(
                          color: isSelected ? cs.onSecondaryContainer : null,
                          fontWeight: isSelected ? FontWeight.bold : null,
                        ),
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
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: ImageKeyfileResolution.values.map((preset) {
                      final isSelected = _imagePreset == preset;
                      return ChoiceChip(
                        label: Text(preset.label),
                        selected: isSelected,
                        showCheckmark: false,
                        labelStyle: textTheme.labelLarge?.copyWith(
                          color: isSelected ? cs.onSecondaryContainer : null,
                          fontWeight: isSelected ? FontWeight.bold : null,
                        ),
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

        const SizedBox(height: AppSpacing.md),

        // Keyfile Preview & Metrics Card
        Card(
          elevation: 0,
          color: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
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
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        _keyfileSuggestedName,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: context.l10n.keyfileGenerateNewTooltip,
                      onPressed: _regenerateKeyfile,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.l10n.keyfileSizeLabel(
                    formatBytes(_generatedKeyfileBytes?.length ?? 0),
                  ),
                  style: textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Text(
                      context.l10n.keyfileFingerprintLabel,
                      style: textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: context.l10n.keyfileCopyFingerprintTooltip,
                      onPressed: _copyFingerprint,
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: SelectableText(
                    _keyfileFingerprint,
                    style: textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _isExporting ? null : _exportKeyfileToStorage,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(context.l10n.exportKeyfileToStorage),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isExporting ? null : _saveKeyfileToMountedVault,
                icon: const Icon(Icons.lock_open_rounded),
                label: Text(context.l10n.saveKeyfileToVault),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _colorForStrength(double fraction) {
    if (fraction < 0.35) return Colors.redAccent;
    if (fraction < 0.65) return Colors.orangeAccent;
    if (fraction < 0.9) return Colors.green;
    return Colors.purpleAccent;
  }
}