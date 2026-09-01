import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/services/keyfile_passphrase_generator_service.dart';
import 'package:vaultexplorer/features/tools/widgets/keyfile_passphrase_generator_controller.dart';

class KeyfilePassphraseGeneratorScreen extends ConsumerWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;

  const KeyfilePassphraseGeneratorScreen({
    super.key,
    required this.mountedContainers,
  });

  Future<void> _copyPassphrase(
    BuildContext context,
    WidgetRef ref,
    String passphrase,
  ) async {
    if (passphrase.isEmpty) return;
    await ref.read(sensitiveClipboardProvider).copy(passphrase);
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.copyPassphraseSuccess,
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _copyFingerprint(BuildContext context, String fingerprint) async {
    if (fingerprint.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: fingerprint));
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.copyFingerprintSuccess,
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _exportKeyfileToStorage(BuildContext context, WidgetRef ref) async {
    try {
      final savedPath = await ref
          .read(keyfilePassphraseGeneratorProvider.notifier)
          .exportKeyfileToStorage();
      if (savedPath != null && context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.keyfileExportSuccessMessage(savedPath),
          tone: AppBannerTone.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.keyfileExportFailedMessage(e),
          tone: AppBannerTone.error,
        );
      }
    }
  }

  Future<void> _saveKeyfileToMountedVault(
    BuildContext context,
    WidgetRef ref,
    KeyfilePassphraseGeneratorState state,
  ) async {
    if (state.generatedKeyfileBytes == null) return;
    final openVaults = mountedContainers.value;

    if (openVaults.isEmpty) {
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
              ...openVaults.map(
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

    if (selectedVault == null || !context.mounted) return;

    try {
      final ok = await ref
          .read(keyfilePassphraseGeneratorProvider.notifier)
          .saveKeyfileToMountedVault(selectedVault);

      if (ok && context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.keyfileSavedToVaultMessage(
            selectedVault.displayName,
            '/${state.keyfileSuggestedName}',
          ),
          tone: AppBannerTone.success,
        );
      } else if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.keyfileWriteFailedMessage,
          tone: AppBannerTone.error,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.keyfileSaveErrorMessage(e),
          tone: AppBannerTone.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(keyfilePassphraseGeneratorProvider);
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
            _buildTabSegment(context, ref, state, isCompact: true),
            const SizedBox(width: 12),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!isLandscape) _buildTabSegment(context, ref, state, isCompact: false),
            Expanded(
              child: isLandscape
                  ? _buildLandscapeLayout(context, ref, state)
                  : _buildPortraitLayout(context, ref, state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabSegment(
    BuildContext context,
    WidgetRef ref,
    KeyfilePassphraseGeneratorState state, {
    required bool isCompact,
  }) {
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
        selected: {state.selectedTab},
        onSelectionChanged: (set) {
          ref
              .read(keyfilePassphraseGeneratorProvider.notifier)
              .setSelectedTab(set.first);
        },
      ),
    );
  }

  // ── LANDSCAPE 2-COLUMN LAYOUT ───────────────────────────────────────────────

  Widget _buildLandscapeLayout(
    BuildContext context,
    WidgetRef ref,
    KeyfilePassphraseGeneratorState state,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: state.selectedTab == GeneratorTab.passphrase
                  ? _buildUnifiedPassphraseOutputCard(context, ref, state)
                  : _buildUnifiedKeyfileOutputCard(context, ref, state),
            ),
          ),
          const SizedBox(width: 12),
          const VerticalDivider(width: 1),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              child: state.selectedTab == GeneratorTab.passphrase
                  ? _buildPassphraseControls(context, ref, state)
                  : _buildKeyfileControls(context, ref, state),
            ),
          ),
        ],
      ),
    );
  }

  // ── PORTRAIT SINGLE-COLUMN LAYOUT ──────────────────────────────────────────

  Widget _buildPortraitLayout(
    BuildContext context,
    WidgetRef ref,
    KeyfilePassphraseGeneratorState state,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.selectedTab == GeneratorTab.passphrase) ...[
            _buildUnifiedPassphraseOutputCard(context, ref, state),
            const SizedBox(height: 10),
            _buildPassphraseControls(context, ref, state),
          ] else ...[
            _buildUnifiedKeyfileOutputCard(context, ref, state),
            const SizedBox(height: 10),
            _buildKeyfileControls(context, ref, state),
          ],
        ],
      ),
    );
  }

  // ── PASSPHRASE VIEWS ───────────────────────────────────────────────────────

  Widget _buildUnifiedPassphraseOutputCard(
    BuildContext context,
    WidgetRef ref,
    KeyfilePassphraseGeneratorState state,
  ) {
    final cs = context.colors;
    final textTheme = context.typography;
    final strength = KeyfilePassphraseGeneratorService.evaluatePasswordStrength(
      state.passphraseEntropyBits,
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
                  onPressed: state.isLoadingPassphrase || state.generatedPassphrase.isEmpty
                      ? null
                      : () => _copyPassphrase(
                            context,
                            ref,
                            state.generatedPassphrase,
                          ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: context.l10n.generateNewTooltip,
                  onPressed: state.isLoadingPassphrase
                      ? null
                      : () => ref
                          .read(keyfilePassphraseGeneratorProvider.notifier)
                          .regeneratePassphrase(),
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
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: state.isLoadingPassphrase
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
                          state.generatedPassphrase,
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
                    state.passphraseEntropyBits.toStringAsFixed(1),
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
                value: state.isLoadingPassphrase ? null : strength.scoreFraction,
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

  Widget _buildPassphraseControls(
    BuildContext context,
    WidgetRef ref,
    KeyfilePassphraseGeneratorState state,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<PassphraseMode>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
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
          selected: {state.passphraseMode},
          onSelectionChanged: (set) {
            ref
                .read(keyfilePassphraseGeneratorProvider.notifier)
                .setPassphraseMode(set.first);
          },
        ),
        const SizedBox(height: 10),
        state.passphraseMode == PassphraseMode.diceware
            ? _buildDicewareControls(context, ref, state)
            : _buildCustomPasswordControls(context, ref, state),
      ],
    );
  }

  Widget _buildDicewareControls(
    BuildContext context,
    WidgetRef ref,
    KeyfilePassphraseGeneratorState state,
  ) {
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
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.dicewareWordCountLabel(state.dicewareWordCount),
                    style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.dicewareWordCountBitsLabel(
                    (state.dicewareWordCount * 12.9).toStringAsFixed(0),
                  ),
                  style: textTheme.labelSmall?.copyWith(color: cs.primary),
                ),
              ],
            ),
            Slider(
              value: state.dicewareWordCount.toDouble(),
              min: 3,
              max: 12,
              divisions: 9,
              label: context.l10n.dicewareWordCountSliderLabel(state.dicewareWordCount),
              onChanged: (val) {
                ref
                    .read(keyfilePassphraseGeneratorProvider.notifier)
                    .setDicewareWordCount(val.toInt());
              },
              onChangeEnd: (_) {
                ref
                    .read(keyfilePassphraseGeneratorProvider.notifier)
                    .regeneratePassphrase();
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
                    value: state.dicewareSeparator,
                    underline: const SizedBox(),
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
                      ref
                          .read(keyfilePassphraseGeneratorProvider.notifier)
                          .setDicewareSeparator(val);
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
                    value: state.dicewareCasing,
                    underline: const SizedBox(),
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
                      ref
                          .read(keyfilePassphraseGeneratorProvider.notifier)
                          .setDicewareCasing(val);
                    },
                  ),
                ),
              ],
            ),
            const Divider(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.l10n.dicewareAppendDigitLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: state.dicewareIncludeNumber,
              onChanged: (val) {
                ref
                    .read(keyfilePassphraseGeneratorProvider.notifier)
                    .setDicewareIncludeNumber(val);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.l10n.dicewareAppendSymbolLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: state.dicewareIncludeSymbol,
              onChanged: (val) {
                ref
                    .read(keyfilePassphraseGeneratorProvider.notifier)
                    .setDicewareIncludeSymbol(val);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomPasswordControls(
    BuildContext context,
    WidgetRef ref,
    KeyfilePassphraseGeneratorState state,
  ) {
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
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.customPasswordLengthLabel(state.customLength),
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Slider(
              value: state.customLength.toDouble(),
              min: 8,
              max: 128,
              divisions: 120,
              label: context.l10n.customPasswordLengthSliderLabel(state.customLength),
              onChanged: (val) {
                ref
                    .read(keyfilePassphraseGeneratorProvider.notifier)
                    .setCustomLength(val.toInt());
              },
              onChangeEnd: (_) {
                ref
                    .read(keyfilePassphraseGeneratorProvider.notifier)
                    .regeneratePassphrase();
              },
            ),
            const Divider(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.l10n.customPasswordUppercaseLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: state.customUseUppercase,
              onChanged: (val) {
                ref
                    .read(keyfilePassphraseGeneratorProvider.notifier)
                    .setCustomUseUppercase(val);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.l10n.customPasswordLowercaseLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: state.customUseLowercase,
              onChanged: (val) {
                ref
                    .read(keyfilePassphraseGeneratorProvider.notifier)
                    .setCustomUseLowercase(val);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.l10n.customPasswordNumbersLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: state.customUseNumbers,
              onChanged: (val) {
                ref
                    .read(keyfilePassphraseGeneratorProvider.notifier)
                    .setCustomUseNumbers(val);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.l10n.customPasswordSymbolsLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: state.customUseSymbols,
              onChanged: (val) {
                ref
                    .read(keyfilePassphraseGeneratorProvider.notifier)
                    .setCustomUseSymbols(val);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.l10n.customPasswordExcludeAmbiguousLabel,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: state.customExcludeAmbiguous,
              onChanged: (val) {
                ref
                    .read(keyfilePassphraseGeneratorProvider.notifier)
                    .setCustomExcludeAmbiguous(val);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── KEYFILE VIEWS ──────────────────────────────────────────────────────────

  Widget _buildUnifiedKeyfileOutputCard(
    BuildContext context,
    WidgetRef ref,
    KeyfilePassphraseGeneratorState state,
  ) {
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
                  state.keyfileType == KeyfileType.binary
                      ? Icons.insert_drive_file_rounded
                      : Icons.image_rounded,
                  color: cs.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.keyfileSuggestedName,
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: context.l10n.keyfileGenerateNewTooltip,
                  onPressed: () => ref
                      .read(keyfilePassphraseGeneratorProvider.notifier)
                      .regenerateKeyfile(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.keyfileSizeLabel(
                formatBytes(state.generatedKeyfileBytes?.length ?? 0),
              ),
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.keyfileFingerprintLabel,
                    style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  tooltip: context.l10n.keyfileCopyFingerprintTooltip,
                  onPressed: () => _copyFingerprint(context, state.keyfileFingerprint),
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
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: SelectableText(
                state.keyfileFingerprint,
                style: textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: cs.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            LayoutBuilder(
              builder: (context, constraints) {
                final isVeryNarrow = constraints.maxWidth < 280;

                final exportBtn = FilledButton.icon(
                  onPressed: state.isExporting
                      ? null
                      : () => _exportKeyfileToStorage(context, ref),
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
                  onPressed: state.isExporting
                      ? null
                      : () => _saveKeyfileToMountedVault(context, ref, state),
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

  Widget _buildKeyfileControls(
    BuildContext context,
    WidgetRef ref,
    KeyfilePassphraseGeneratorState state,
  ) {
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
          selected: {state.keyfileType},
          onSelectionChanged: (set) {
            ref
                .read(keyfilePassphraseGeneratorProvider.notifier)
                .setKeyfileType(set.first);
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
                  state.keyfileType == KeyfileType.binary
                      ? context.l10n.keyfileBinarySizeTitle
                      : context.l10n.keyfileImageResolutionTitle,
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                if (state.keyfileType == KeyfileType.binary)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: KeyfileSizePreset.values.map((preset) {
                      final isSelected = state.binaryPreset == preset;
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
                            ref
                                .read(keyfilePassphraseGeneratorProvider.notifier)
                                .setBinaryPreset(preset);
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
                      final isSelected = state.imagePreset == preset;
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
                            ref
                                .read(keyfilePassphraseGeneratorProvider.notifier)
                                .setImagePreset(preset);
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

  String _strengthLevelLabel(BuildContext context, PasswordStrengthLevel level) {
    return switch (level) {
      PasswordStrengthLevel.weak => context.l10n.passphraseStrengthWeak,
      PasswordStrengthLevel.good => context.l10n.passphraseStrengthGood,
      PasswordStrengthLevel.strong => context.l10n.passphraseStrengthStrong,
      PasswordStrengthLevel.unbreakable => context.l10n.passphraseStrengthUnbreakable,
    };
  }

  String _crackTimeLabel(BuildContext context, PasswordCrackTimeEstimate estimate) {
    return switch (estimate) {
      PasswordCrackTimeEstimate.instant => context.l10n.passphraseCrackTimeInstant,
      PasswordCrackTimeEstimate.shortTerm => context.l10n.passphraseCrackTimeShort,
      PasswordCrackTimeEstimate.centuries => context.l10n.passphraseCrackTimeCenturies,
      PasswordCrackTimeEstimate.millionsOfYears => context.l10n.passphraseCrackTimeMillionsOfYears,
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

  String _imagePresetLabel(BuildContext context, ImageKeyfileResolution preset) {
    return switch (preset) {
      ImageKeyfileResolution.res64 => context.l10n.keyfilePresetRes64,
      ImageKeyfileResolution.res256 => context.l10n.keyfilePresetRes256,
      ImageKeyfileResolution.res512 => context.l10n.keyfilePresetRes512,
    };
  }
}
