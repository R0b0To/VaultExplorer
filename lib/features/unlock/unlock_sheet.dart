import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';
import 'package:vaultexplorer/features/unlock/unlock_controller.dart';

enum _UnlockCredentialState {
  loading,
  missing,
  biometric,
  pattern,
  pin,
  password,
  none,
}

class UnlockSheet extends ConsumerStatefulWidget {
  final void Function(MountedContainer container, {ContainerRecord? record}) onMounted;
  final Route<void> Function(MountedContainer container)? openBrowserRoute;
  final String? initialUri;
  final String? initialName;
  final String? prefillPassword;
  final bool documentProvider;
  final List<String> autoMountFolders;
  final List<String> mountedUris;

  const UnlockSheet({
    super.key,
    required this.onMounted,
    this.openBrowserRoute,
    this.initialUri,
    this.initialName,
    this.prefillPassword,
    this.documentProvider = false,
    this.autoMountFolders = const [],
    this.mountedUris = const [],
  });

  @override
  ConsumerState<UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends ConsumerState<UnlockSheet> with WidgetsBindingObserver {
  late final TextEditingController _passwordCtrl;
  final _pimCtrl = TextEditingController();
  final _hiddenPasswordCtrl = TextEditingController();
  final _hiddenPimCtrl = TextEditingController();

  bool _obscure = true;
  bool _hiddenObscure = true;

  UnlockParams get _params => UnlockParams(
        initialUri: widget.initialUri,
        initialName: widget.initialName,
        prefillPassword: widget.prefillPassword,
        documentProvider: widget.documentProvider,
        autoMountFolders: widget.autoMountFolders,
        mountedUris: widget.mountedUris,
      );

  bool get _passwordPrefilled =>
      widget.prefillPassword != null && _passwordCtrl.text == widget.prefillPassword;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _passwordCtrl = TextEditingController(text: widget.prefillPassword ?? '');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordCtrl.dispose();
    _pimCtrl.dispose();
    _hiddenPasswordCtrl.dispose();
    _hiddenPimCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(unlockControllerProvider(_params).notifier).checkStoragePermission();
    }
  }

  void _onUnlock() {
    ref.read(unlockControllerProvider(_params).notifier).unlock(
          passwordText: _passwordCtrl.text,
          pimText: _pimCtrl.text,
          hiddenPasswordText: _hiddenPasswordCtrl.text,
          hiddenPimText: _hiddenPimCtrl.text,
          l10n: context.l10n,
          passwordPrefilled: _passwordPrefilled,
        );
  }

  _UnlockCredentialState _getCredentialState(UnlockState state) {
    if (state.loadingAuth) return _UnlockCredentialState.loading;
    if (state.containerMissing) return _UnlockCredentialState.missing;
    if (state.unlockMethod == ContainerUnlockMethod.biometrics && !state.showPasswordFallback) {
      return _UnlockCredentialState.biometric;
    }
    if (state.unlockMethod == ContainerUnlockMethod.pattern && !state.showPasswordFallback) {
      return _UnlockCredentialState.pattern;
    }
    if (state.unlockMethod == ContainerUnlockMethod.pin && !state.showPasswordFallback) {
      return _UnlockCredentialState.pin;
    }
    if (state.showPasswordFallback ||
        widget.initialUri == null ||
        state.unlockMethod == ContainerUnlockMethod.password ||
        state.unlockMethod == ContainerUnlockMethod.rememberPassword) {
      return _UnlockCredentialState.password;
    }
    return _UnlockCredentialState.none;
  }

  String _formatBadgeLabel(BuildContext context, UnlockState state) {
    if (state.isLuks) return context.l10n.formatContainerLabel('LUKS');
    if (state.isCryptomator) return context.l10n.formatVaultLabel('Cryptomator');
    if (state.isGocryptfs) return context.l10n.formatVaultLabel('Gocryptfs');
    if (state.isCryfs) return context.l10n.formatVaultLabel('CryFS');
    if (state.isBitlocker) return context.l10n.formatContainerLabel('BitLocker');
    if (state.containerFormat == 'veracrypt') return context.l10n.formatContainerLabel('VeraCrypt');
    return context.l10n.encryptedContainerLabel;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      unlockControllerProvider(_params).select((s) => s.mountedSuccess),
      (prev, next) {
        if (next != null && mounted) {
          HapticFeedback.lightImpact();
          widget.onMounted(next.container, record: next.record);
          if (widget.openBrowserRoute != null) {
            Navigator.of(context).pushReplacement(
              widget.openBrowserRoute!(next.container),
            );
          } else {
            Navigator.pop(context);
          }
        }
      },
    );
    ref.listen(
      unlockControllerProvider(_params).select((s) => s.biometricAutoTriggerTick),
      (prev, next) {
        if (mounted) {
          ref.read(unlockControllerProvider(_params).notifier).tryBiometric(context.l10n);
        }
      },
    );

    final state = ref.watch(unlockControllerProvider(_params));
    final cs = context.colors;
    final textTheme = context.typography;
    final wideLayout = context.screen.useWideLayout;
    final credState = _getCredentialState(state);

    return PopScope(
      canPop: !state.loading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && state.loading) {
          ref.read(unlockControllerProvider(_params).notifier).cancelUnlock();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHigh,
          title: Text(
            widget.initialUri != null
                ? context.l10n.unlockContainerTitle
                : context.l10n.mountContainerTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          actions: widget.initialUri == null && wideLayout
              ? [
                  _buildVaultKindSegmentedButton(context, state),
                  const SizedBox(width: 12),
                ]
              : null,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: state.loading
                ? LinearProgressIndicator(
                    color: cs.primary,
                    backgroundColor: cs.primaryContainer,
                  )
                : const SizedBox(height: 4),
          ),
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          child: SafeArea(
            child: wideLayout
                ? _buildWideLayout(context, state, credState, cs, textTheme)
                : _buildPortraitLayout(context, state, credState, cs, textTheme),
          ),
        ),
      ),
    );
  }

  Widget _buildWideLayout(
    BuildContext context,
    UnlockState state,
    _UnlockCredentialState credState,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final isPatternOrPin =
        credState == _UnlockCredentialState.pattern || credState == _UnlockCredentialState.pin;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              physics: isPatternOrPin ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPickerCard(context, state, cs, textTheme),
                  const SizedBox(height: 10),
                  ..._buildCredentialSection(context, state, credState, cs, textTheme),
                  ..._buildPrimaryActionSection(context, state, credState, cs, textTheme),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          const VerticalDivider(width: 1),
          const SizedBox(width: 14),
          Expanded(
            flex: 6,
            child: _buildRightPane(context, state, credState, cs, textTheme),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout(
    BuildContext context,
    UnlockState state,
    _UnlockCredentialState credState,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final isPatternOrPin =
        credState == _UnlockCredentialState.pattern || credState == _UnlockCredentialState.pin;

    return SingleChildScrollView(
      physics: isPatternOrPin ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPickerCard(context, state, cs, textTheme),
          const SizedBox(height: 10),
          ..._buildCredentialSection(context, state, credState, cs, textTheme),
          ..._buildPrimaryActionSection(context, state, credState, cs, textTheme),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildVaultKindSegmentedButton(BuildContext context, UnlockState state) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      segments: [
        ButtonSegment(
          value: 'container',
          label: Text(
            context.l10n.vaultKindContainerFile,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
          ),
          icon: const Icon(Icons.folder_zip_rounded, size: 16),
        ),
        ButtonSegment(
          value: 'directory_vault',
          label: Text(
            context.l10n.vaultKindFolderVault,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
          ),
          icon: const Icon(Icons.folder_shared_rounded, size: 16),
        ),
      ],
      selected: {state.isFolderVault ? 'directory_vault' : 'container'},
      onSelectionChanged: state.loading
          ? null
          : (sel) => ref.read(unlockControllerProvider(_params).notifier).setSelectedVaultKind(sel.first),
    );
  }

  Widget _buildPickerCard(
    BuildContext context,
    UnlockState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final hasSelection = state.selectedUri != null;
    final isWide = context.screen.useWideLayout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          children: [
            if (widget.initialUri == null && !isWide) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: _buildVaultKindSegmentedButton(context, state),
              ),
            ],
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: hasSelection ? cs.primaryContainer.withValues(alpha: 0.7) : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: ContainerFormatIcon(
                  format: hasSelection
                      ? ContainerFormat.fromWire(state.containerFormat)
                      : ContainerFormat.directoryVault,
                  color: hasSelection ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  size: 22,
                ),
              ),
              title: Text(
                state.selectedName ??
                    (state.isFolderVault
                        ? context.l10n.tapToSelectVaultFolder
                        : context.l10n.tapToSelectContainerFile),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: hasSelection ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                hasSelection
                    ? _formatBadgeLabel(context, state)
                    : (state.isFolderVault
                        ? 'Cryptomator | Gocryptfs | CryFS'
                        : 'VeraCrypt | LUKS | BitLocker'),
                style: textTheme.bodySmall?.copyWith(
                  color: hasSelection ? cs.primary : cs.onSurfaceVariant,
                  fontWeight: hasSelection ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: (hasSelection && widget.initialUri == null)
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: context.l10n.clearAllButton,
                      onPressed: state.loading
                          ? null
                          : () => ref.read(unlockControllerProvider(_params).notifier).clearSelection(),
                    )
                  : (widget.initialUri == null
                      ? Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant)
                      : null),
              onTap: state.loading || widget.initialUri != null
                  ? null
                  : () => ref.read(unlockControllerProvider(_params).notifier).pickFile(context.l10n),
            ),
          ],
        ),
        if (state.isFolderVault && !state.hasAllStorageAccess) ...[
          const SizedBox(height: 8),
          InlineBanner(
            state.isCryfs
                ? context.l10n.cryfsStorageAccessWarning
                : context.l10n.folderVaultStorageAccessWarning,
            tone: AppBannerTone.warning,
            icon: Icons.speed_rounded,
            trailing: TextButton(
              onPressed: () => ref.read(unlockControllerProvider(_params).notifier).requestStoragePermission(),
              child: Text(context.l10n.enableButtonLabel),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildCredentialSection(
    BuildContext context,
    UnlockState state,
    _UnlockCredentialState credState,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    switch (credState) {
      case _UnlockCredentialState.loading:
        return [
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ];

      case _UnlockCredentialState.missing:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.find_in_page_outlined, color: cs.error, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.containerMissingTitle,
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: cs.error),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.containerMissingExplanation,
                      style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () => ref.read(unlockControllerProvider(_params).notifier).relocateContainer(context.l10n),
                            child: Text(context.l10n.locateFileButtonLabel),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UnlockCredentialState.biometric:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.fingerprint_rounded, size: 44, color: cs.primary),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.biometricUnlockTitle,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => ref.read(unlockControllerProvider(_params).notifier).setShowPasswordFallback(true),
                            child: Text(context.l10n.usePasswordButtonLabel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                ref.read(unlockControllerProvider(_params).notifier).tryBiometric(context.l10n),
                            child: Text(context.l10n.authenticateButtonLabel),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UnlockCredentialState.pattern:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      context.l10n.drawUnlockPatternTitle,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    PatternLockView(
                      key: ValueKey(state.patternResetKey),
                      onPatternComplete: (p) => ref.read(unlockControllerProvider(_params).notifier).onPatternComplete(p, context.l10n),
                      showError: state.patternError,
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => ref.read(unlockControllerProvider(_params).notifier).setShowPasswordFallback(true),
                      child: Text(context.l10n.usePasswordInsteadButtonLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UnlockCredentialState.pin:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      context.l10n.enterUnlockPinTitle,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    PinLockView(
                      key: ValueKey(state.pinResetKey),
                      onPinComplete: (p) => ref.read(unlockControllerProvider(_params).notifier).onPinComplete(p, context.l10n),
                      showError: state.pinError,
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => ref.read(unlockControllerProvider(_params).notifier).setShowPasswordFallback(true),
                      child: Text(context.l10n.usePasswordInsteadButtonLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UnlockCredentialState.password:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  autofocus: widget.initialUri != null && widget.prefillPassword?.isEmpty != false,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _onUnlock(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    labelText: state.isPlainDiskImage
                        ? '${context.l10n.passwordFieldLabel} (optional)'
                        : context.l10n.passwordFieldLabel,
                    hintText: state.isPlainDiskImage
                        ? 'No password needed — this disk image isn\'t encrypted'
                        : state.isFolderVault
                            ? context.l10n.passwordHintFolderVault
                            : state.isBitlocker
                                ? context.l10n.passwordHintBitlocker
                                : context.l10n.passwordHintContainer,
                    prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: cs.primary),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_passwordPrefilled)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Tooltip(
                              message: context.l10n.usingSavedPasswordTooltip,
                              child: Icon(Icons.bookmark_rounded, size: 20, color: cs.primary),
                            ),
                          ),
                        PasswordVisibilityToggle(
                          obscured: _obscure,
                          onToggle: () => setState(() => _obscure = !_obscure),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
              if (!state.hasAdvancedSettings) ...[
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  value: state.readOnly,
                  onChanged: state.loading
                      ? null
                      : (val) {
                          ref.read(unlockControllerProvider(_params).notifier).setReadOnly(val);
                        },
                  title: Text(context.l10n.readOnlyModeLabel),
                  secondary: Icon(Icons.visibility_outlined, color: cs.primary, size: 22),
                ),
              ],
              if (state.hasAdvancedSettings) ...[
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: Icon(Icons.tune_rounded, size: 20, color: cs.primary),
                    title: Text(
                      context.l10n.advancedOptionsTitle,
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    children: _buildAdvancedOptionsSection(context, state, cs, textTheme),
                  ),
                ),
              ],
              if (widget.initialUri == null) ...[
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  value: state.remember,
                  onChanged: state.loading
                      ? null
                      : (val) {
                          ref.read(unlockControllerProvider(_params).notifier).setRemember(val);
                        },
                  title: Text(context.l10n.rememberContainerLabel),
                  subtitle: Text(
                    context.l10n.rememberContainerSubtitle,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  secondary: Icon(Icons.push_pin_outlined, color: cs.primary, size: 22),
                ),
              ],
            ],
          ),
        ];

      default:
        return const [];
    }
  }

  List<Widget> _buildAdvancedOptionsSection(
    BuildContext context,
    UnlockState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: KeyfilesPicker(
          keyfiles: state.keyfiles,
          picking: state.pickingKeyfiles,
          onPick: () => ref.read(unlockControllerProvider(_params).notifier).pickKeyfiles(),
          onRemove: (k) => ref.read(unlockControllerProvider(_params).notifier).removeKeyfile(k),
        ),
      ),
      if (state.isLuks && state.keyfiles.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Text(
            context.l10n.luksKeyfileReplacesPasswordNote,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
      if (state.isVeraCrypt) ...[
        AdvancedParamsPanel(
          pimController: _pimCtrl,
          cipherId: state.cipherId,
          hashId: state.hashId,
          enabled: !state.loading,
          onCipherChanged: (val) => ref.read(unlockControllerProvider(_params).notifier).setCipherId(val),
          onHashChanged: (val) => ref.read(unlockControllerProvider(_params).notifier).setHashId(val),
        ),
      ],
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        value: state.readOnly,
        onChanged: state.loading
            ? null
            : (val) {
                ref.read(unlockControllerProvider(_params).notifier).setReadOnly(val);
              },
        title: Text(context.l10n.readOnlyModeLabel),
        subtitle: Text(
          context.l10n.readOnlyModeContainerSubtitle,
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        secondary: Icon(Icons.visibility_outlined, color: cs.primary, size: 22),
      ),
      if (state.isVeraCrypt) ...[
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          value: state.protectHiddenVolume && !state.readOnly,
          onChanged: (state.loading || state.readOnly)
              ? null
              : (val) {
                  ref.read(unlockControllerProvider(_params).notifier).setProtectHiddenVolume(val);
                },
          title: Text(context.l10n.protectHiddenVolumeToggleTitle),
          subtitle: Text(
            state.readOnly
                ? context.l10n.readOnlyModeContainerSubtitle
                : context.l10n.protectHiddenVolumeToggleSubtitle,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          secondary: Icon(Icons.shield_outlined, color: cs.primary, size: 22),
        ),
        if (state.protectHiddenVolume && !state.readOnly) ...[
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _hiddenPasswordCtrl,
              obscureText: _hiddenObscure,
              enabled: !state.loading,
              decoration: InputDecoration(
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                labelText: context.l10n.hiddenPasswordLabel,
                prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
                suffixIcon: PasswordVisibilityToggle(
                  obscured: _hiddenObscure,
                  onToggle: () => setState(() => _hiddenObscure = !_hiddenObscure),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: KeyfilesPicker(
              keyfiles: state.hiddenKeyfiles,
              picking: state.pickingHiddenKeyfiles,
              onPick: () => ref.read(unlockControllerProvider(_params).notifier).pickHiddenKeyfiles(),
              onRemove: (k) => ref.read(unlockControllerProvider(_params).notifier).removeHiddenKeyfile(k),
              enabled: !state.loading,
            ),
          ),
          AdvancedParamsPanel(
            pimController: _hiddenPimCtrl,
            cipherId: state.hiddenCipherId,
            hashId: state.hiddenHashId,
            enabled: !state.loading,
            onCipherChanged: (val) => ref.read(unlockControllerProvider(_params).notifier).setHiddenCipherId(val),
            onHashChanged: (val) => ref.read(unlockControllerProvider(_params).notifier).setHiddenHashId(val),
          ),
        ],
      ],
    ];
  }

  Widget _buildRightPane(
    BuildContext context,
    UnlockState state,
    _UnlockCredentialState credState,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    switch (credState) {
      case _UnlockCredentialState.loading:
        return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));

      case _UnlockCredentialState.pattern:
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: PatternLockView(
              key: ValueKey(state.patternResetKey),
              onPatternComplete: (p) => ref.read(unlockControllerProvider(_params).notifier).onPatternComplete(p, context.l10n),
              showError: state.patternError,
            ),
          ),
        );

      case _UnlockCredentialState.pin:
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: PinLockView(
              key: ValueKey(state.pinResetKey),
              onPinComplete: (p) => ref.read(unlockControllerProvider(_params).notifier).onPinComplete(p, context.l10n),
              showError: state.pinError,
            ),
          ),
        );

      case _UnlockCredentialState.biometric:
        return Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.fingerprint_rounded, size: 56, color: cs.primary),
          ),
        );

      case _UnlockCredentialState.password:
      default:
        if (!state.hasAdvancedSettings) return const SizedBox.shrink();
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                children: _buildAdvancedOptionsSection(context, state, cs, textTheme),
              ),
            ],
          ),
        );
    }
  }

  List<Widget> _buildPrimaryActionSection(
    BuildContext context,
    UnlockState state,
    _UnlockCredentialState credState,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    if (credState != _UnlockCredentialState.password) return const [];
    final isButtonEnabled = state.selectedUri != null;

    return [
      if (state.error != null) ...[
        const SizedBox(height: 10),
        InlineErrorBanner(state.error!),
      ],
      const SizedBox(height: 10),
      FilledButton(
        onPressed: state.loading ? () {} : (isButtonEnabled ? _onUnlock : null),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: const StadiumBorder(),
        ),
        child: state.loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                state.isFolderVault
                    ? context.l10n.unlockVaultButtonLabel
                    : context.l10n.unlockContainerLabel,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
      ),
      if (state.loading && state.activeVolId != null) ...[
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: () => ref.read(unlockControllerProvider(_params).notifier).cancelUnlock(),
            child: Text(context.l10n.cancelUnlockButtonLabel),
          ),
        ),
      ],
    ];
  }
}