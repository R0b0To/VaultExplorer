import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';
import 'package:vaultexplorer/features/unlock/usb_unlock_controller.dart';

enum _UsbUnlockCredentialState {
  loading,
  biometric,
  pattern,
  pin,
  password,
}

class UsbUnlockSheet extends ConsumerStatefulWidget {
  final void Function(MountedContainer container, {ContainerRecord? record}) onMounted;
  final Route<void> Function(MountedContainer container)? openBrowserRoute;
  final bool documentProvider;
  final List<String> autoMountFolders;
  final ContainerRecord? existingRecord;
  final String? prefillPassword;
  final void Function(MountedContainer container, ContainerRecord migratedRecord, String oldUri)? onReconnected;
  final List<String> mountedUris;

  const UsbUnlockSheet({
    super.key,
    required this.onMounted,
    this.openBrowserRoute,
    this.documentProvider = false,
    this.autoMountFolders = const [],
    this.existingRecord,
    this.prefillPassword,
    this.onReconnected,
    this.mountedUris = const [],
  });

  @override
  ConsumerState<UsbUnlockSheet> createState() => _UsbUnlockSheetState();
}

class _UsbUnlockSheetState extends ConsumerState<UsbUnlockSheet> {
  late final TextEditingController _passwordCtrl;
  final _pimCtrl = TextEditingController();
  final _hiddenPasswordCtrl = TextEditingController();
  final _hiddenPimCtrl = TextEditingController();

  bool _obscure = true;
  bool _hiddenObscure = true;

  /// True until the password field has been fully cleared at least once
  /// since it was prefilled with a saved credential. Tracking "ever
  /// cleared" rather than "currently differs from the prefill" closes the
  /// trivial bypass where someone types one extra character (the field
  /// still contains — and would reveal — almost the entire real saved
  /// password) and hits show. Once genuinely cleared and retyped from
  /// scratch, normal show/hide and copy/select behavior resumes.
  bool _prefillCleared = false;

  UsbUnlockParams get _params => UsbUnlockParams(
        existingRecord: widget.existingRecord,
        prefillPassword: widget.prefillPassword,
        documentProvider: widget.documentProvider,
        autoMountFolders: widget.autoMountFolders,
        mountedUris: widget.mountedUris,
      );

  bool get _passwordPrefilled =>
      widget.prefillPassword != null && _passwordCtrl.text == widget.prefillPassword;

  /// While true, the password field's real characters can't be revealed
  /// via the show/hide toggle or copied via text selection — see
  /// [_prefillCleared].
  bool get _revealLocked => (widget.prefillPassword?.isNotEmpty ?? false) && !_prefillCleared;

  @override
  void initState() {
    super.initState();
    _passwordCtrl = TextEditingController(text: widget.prefillPassword ?? '');
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _pimCtrl.dispose();
    _hiddenPasswordCtrl.dispose();
    _hiddenPimCtrl.dispose();
    super.dispose();
  }

  void _onUnlock() {
    ref.read(usbUnlockControllerProvider(_params).notifier).unlock(
          passwordText: _passwordCtrl.text,
          pimText: _pimCtrl.text,
          hiddenPasswordText: _hiddenPasswordCtrl.text,
          hiddenPimText: _hiddenPimCtrl.text,
          l10n: context.l10n,
          passwordPrefilled: _passwordPrefilled,
        );
  }

  _UsbUnlockCredentialState _getCredentialState(UsbUnlockState state) {
    if (state.loadingAuth) return _UsbUnlockCredentialState.loading;
    if (state.unlockMethod == ContainerUnlockMethod.biometrics && !state.showPasswordFallback) {
      return _UsbUnlockCredentialState.biometric;
    }
    if (state.unlockMethod == ContainerUnlockMethod.pattern && !state.showPasswordFallback) {
      return _UsbUnlockCredentialState.pattern;
    }
    if (state.unlockMethod == ContainerUnlockMethod.pin && !state.showPasswordFallback) {
      return _UsbUnlockCredentialState.pin;
    }
    return _UsbUnlockCredentialState.password;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      usbUnlockControllerProvider(_params).select((s) => s.mountedSuccess),
      (prev, next) {
        if (next != null && mounted) {
          HapticFeedback.lightImpact();
          if (next.oldUri != null && next.record != null && widget.onReconnected != null) {
            widget.onReconnected!(next.container, next.record!, next.oldUri!);
          } else {
            widget.onMounted(next.container, record: next.record);
          }
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
      usbUnlockControllerProvider(_params).select((s) => s.biometricAutoTriggerTick),
      (prev, next) {
        if (mounted) {
          ref.read(usbUnlockControllerProvider(_params).notifier).tryBiometric(context.l10n);
        }
      },
    );

    final state = ref.watch(usbUnlockControllerProvider(_params));
    final cs = context.colors;
    final textTheme = context.typography;
    final wideLayout = context.screen.useWideLayout;
    final credState = _getCredentialState(state);

    return PopScope(
      canPop: !state.loading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && state.loading) {
          ref.read(usbUnlockControllerProvider(_params).notifier).cancelUnlock();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHigh,
          title: Text(
            widget.existingRecord != null
                ? context.l10n.reconnectUsbDriveTitle(widget.existingRecord!.label)
                : context.l10n.unlockUsbDriveTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (!state.loading && !state.requestingPermission)
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.read(usbUnlockControllerProvider(_params).notifier).loadDevices(),
              ),
          ],
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
    UsbUnlockState state,
    _UsbUnlockCredentialState credState,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final isPatternOrPin =
        credState == _UsbUnlockCredentialState.pattern || credState == _UsbUnlockCredentialState.pin;

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
                  _buildDevicePickerCard(state, cs, textTheme),
                  const SizedBox(height: 10),
                  ..._buildCredentialSection(context, state, credState, cs, textTheme),
                  ..._buildPrimaryActionSection(context, state, credState, cs, textTheme),
                ],
              ),
            ),
          ),
          const SizedBox(width: 28),
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
    UsbUnlockState state,
    _UsbUnlockCredentialState credState,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final isPatternOrPin =
        credState == _UsbUnlockCredentialState.pattern || credState == _UsbUnlockCredentialState.pin;

    return SingleChildScrollView(
      physics: isPatternOrPin ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDevicePickerCard(state, cs, textTheme),
          const SizedBox(height: 10),
          ..._buildCredentialSection(context, state, credState, cs, textTheme),
          ..._buildPrimaryActionSection(context, state, credState, cs, textTheme),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildRightPane(
    BuildContext context,
    UsbUnlockState state,
    _UsbUnlockCredentialState credState,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    switch (credState) {
      case _UsbUnlockCredentialState.loading:
        return const SizedBox.shrink();

      case _UsbUnlockCredentialState.pattern:
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: PatternLockView(
              key: ValueKey(state.patternResetKey),
              onPatternComplete: (p) => ref
                  .read(usbUnlockControllerProvider(_params).notifier)
                  .onPatternComplete(p, context.l10n),
              showError: state.patternError,
            ),
          ),
        );

      case _UsbUnlockCredentialState.pin:
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: PinLockView(
              key: ValueKey(state.pinResetKey),
              onPinComplete: (p) => ref
                  .read(usbUnlockControllerProvider(_params).notifier)
                  .onPinComplete(p, context.l10n),
              showError: state.pinError,
            ),
          ),
        );

      case _UsbUnlockCredentialState.biometric:
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

      case _UsbUnlockCredentialState.password:
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

  Widget _buildDevicePickerCard(UsbUnlockState state, ColorScheme cs, TextTheme textTheme) {
    if (state.loadingDevices) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }
    if (state.devices.isEmpty) {
      return SectionCard(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Center(
              child: Text(
                context.l10n.noUsbStorageDetectedTitle,
                style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ],
      );
    }

    return RadioGroup<UsbDeviceInfo>(
      groupValue: state.selected,
      onChanged: (UsbDeviceInfo? device) {
        if (device != null) {
          ref.read(usbUnlockControllerProvider(_params).notifier).selectDevice(device);
        }
      },
      child: SectionCard(
        children: [
          ...state.devices.map((d) {
            final isSelected = state.selected?.deviceName == d.deviceName;
            return ListTile(
              leading: Icon(
                Icons.usb_rounded,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
              title: Text(d.productName),
              trailing: Radio<UsbDeviceInfo>(
                value: d,
              ),
              onTap: () => ref
                  .read(usbUnlockControllerProvider(_params).notifier)
                  .selectDevice(d),
            );
          }),
        ],
      ),
    );
  }

  List<Widget> _buildCredentialSection(
    BuildContext context,
    UsbUnlockState state,
    _UsbUnlockCredentialState credState,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final isWide = context.screen.useWideLayout;

    switch (credState) {
      case _UsbUnlockCredentialState.loading:
        return [
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ];

      case _UsbUnlockCredentialState.biometric:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  children: [
                    if (!isWide) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.fingerprint_rounded, size: 44, color: cs.primary),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      context.l10n.biometricUnlockTitle,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => ref
                                .read(usbUnlockControllerProvider(_params).notifier)
                                .setShowPasswordFallback(true),
                            child: Text(context.l10n.usePasswordButtonLabel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                ref.read(usbUnlockControllerProvider(_params).notifier).tryBiometric(context.l10n),
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

      case _UsbUnlockCredentialState.pattern:
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
                    if (!isWide) ...[
                      const SizedBox(height: 14),
                      PatternLockView(
                        key: ValueKey(state.patternResetKey),
                        onPatternComplete: (p) =>
                            ref.read(usbUnlockControllerProvider(_params).notifier).onPatternComplete(p, context.l10n),
                        showError: state.patternError,
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => ref
                          .read(usbUnlockControllerProvider(_params).notifier)
                          .setShowPasswordFallback(true),
                      child: Text(context.l10n.usePasswordInsteadButtonLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UsbUnlockCredentialState.pin:
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
                    if (!isWide) ...[
                      const SizedBox(height: 14),
                      PinLockView(
                        key: ValueKey(state.pinResetKey),
                        onPinComplete: (p) =>
                            ref.read(usbUnlockControllerProvider(_params).notifier).onPinComplete(p, context.l10n),
                        showError: state.pinError,
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => ref
                          .read(usbUnlockControllerProvider(_params).notifier)
                          .setShowPasswordFallback(true),
                      child: Text(context.l10n.usePasswordInsteadButtonLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UsbUnlockCredentialState.password:
        final isUnlock = widget.existingRecord != null;
        final format = widget.existingRecord?.format ?? ContainerFormat.fromWire(state.containerFormat);
        final isKnownVeraCrypt = isUnlock && format == ContainerFormat.veracrypt;
        final isKnownLuks = isUnlock && format.isLuks;
        final hasDirectOptions = isKnownVeraCrypt || isKnownLuks;
        final isWide = context.screen.useWideLayout;

        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _passwordCtrl,
                  obscureText: _revealLocked ? true : _obscure,
                  enableInteractiveSelection: !_revealLocked,
                  autofocus: widget.existingRecord != null && widget.prefillPassword?.isEmpty != false,
                  onChanged: (val) {
                    if (val.isEmpty) _prefillCleared = true;
                    setState(() {});
                  },
                  onSubmitted: (_) => _onUnlock(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    labelText: context.l10n.passwordFieldLabel,
                    hintText: context.l10n.passwordHintContainer,
                    prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: cs.primary),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_passwordPrefilled)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Tooltip(
                              message: context.l10n.usingSavedPasswordTooltip,
                              child: Icon(Icons.bookmark_rounded, size: AppIconSize.standard, color: cs.primary),
                            ),
                          ),
                        PasswordVisibilityToggle(
                          obscured: _revealLocked ? true : _obscure,
                          enabled: !_revealLocked,
                          onToggle: () => setState(() => _obscure = !_obscure),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
              if (isKnownVeraCrypt) ...[
                PimInputField(
                  controller: _pimCtrl,
                  enabled: !state.loading,
                ),
              ],
              if (hasDirectOptions) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: KeyfilesPicker(
                    keyfiles: state.keyfiles,
                    picking: state.pickingKeyfiles,
                    onPick: () => ref.read(usbUnlockControllerProvider(_params).notifier).pickKeyfiles(),
                    onRemove: (k) => ref.read(usbUnlockControllerProvider(_params).notifier).removeKeyfile(k),
                  ),
                ),
              ],
              if (!state.hasAdvancedSettings) ...[
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  value: state.readOnly,
                  onChanged: state.loading
                      ? null
                      : (val) {
                          ref.read(usbUnlockControllerProvider(_params).notifier).setReadOnly(val);
                        },
                  title: Text(context.l10n.readOnlyModeLabel),
                  secondary: Icon(Icons.visibility_outlined, color: cs.primary, size: 22),
                ),
              ],
              if (state.hasAdvancedSettings && !isWide) ...[
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
              if (widget.existingRecord == null) ...[
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  value: state.remember,
                  onChanged: state.loading
                      ? null
                      : (val) {
                          ref.read(usbUnlockControllerProvider(_params).notifier).setRemember(val);
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
    }
  }

  List<Widget> _buildAdvancedOptionsSection(
    BuildContext context,
    UsbUnlockState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final isUnlock = widget.existingRecord != null;
    final format = widget.existingRecord?.format ?? ContainerFormat.fromWire(state.containerFormat);
    final isKnownVeraCrypt = isUnlock && format == ContainerFormat.veracrypt;
    final isKnownLuks = isUnlock && format.isLuks;
    final hasDirectOptions = isKnownVeraCrypt || isKnownLuks;

    return [
      if (!hasDirectOptions) ...[
        PimInputField(
          controller: _pimCtrl,
          enabled: !state.loading,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: KeyfilesPicker(
            keyfiles: state.keyfiles,
            picking: state.pickingKeyfiles,
            onPick: () => ref.read(usbUnlockControllerProvider(_params).notifier).pickKeyfiles(),
            onRemove: (k) => ref.read(usbUnlockControllerProvider(_params).notifier).removeKeyfile(k),
          ),
        ),
      ],
      AdvancedParamsPanel(
        collapsible: false,
        cipherId: state.cipherId,
        hashId: state.hashId,
        enabled: !state.loading,
        onCipherChanged: (val) => ref.read(usbUnlockControllerProvider(_params).notifier).setCipherId(val),
        onHashChanged: (val) => ref.read(usbUnlockControllerProvider(_params).notifier).setHashId(val),
      ),
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        value: state.readOnly,
        onChanged: state.loading
            ? null
            : (val) {
                ref.read(usbUnlockControllerProvider(_params).notifier).setReadOnly(val);
              },
        title: Text(context.l10n.readOnlyModeLabel),
        subtitle: Text(
          context.l10n.readOnlyModeContainerSubtitle,
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        secondary: Icon(Icons.visibility_outlined, color: cs.primary, size: 22),
      ),
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        value: state.protectHiddenVolume && !state.readOnly,
        onChanged: (state.loading || state.readOnly)
            ? null
            : (val) {
                ref.read(usbUnlockControllerProvider(_params).notifier).setProtectHiddenVolume(val);
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
              prefixIcon: Icon(Icons.key_rounded, size: AppIconSize.standard, color: cs.primary),
              suffixIcon: PasswordVisibilityToggle(
                obscured: _hiddenObscure,
                onToggle: () => setState(() => _hiddenObscure = !_hiddenObscure),
              ),
            ),
          ),
        ),
        PimInputField(
          controller: _hiddenPimCtrl,
          enabled: !state.loading,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: KeyfilesPicker(
            keyfiles: state.hiddenKeyfiles,
            picking: state.pickingHiddenKeyfiles,
            onPick: () => ref.read(usbUnlockControllerProvider(_params).notifier).pickHiddenKeyfiles(),
            onRemove: (k) => ref.read(usbUnlockControllerProvider(_params).notifier).removeHiddenKeyfile(k),
            enabled: !state.loading,
          ),
        ),
        AdvancedParamsPanel(
          collapsible: false,
          cipherId: state.hiddenCipherId,
          hashId: state.hiddenHashId,
          enabled: !state.loading,
          onCipherChanged: (val) => ref.read(usbUnlockControllerProvider(_params).notifier).setHiddenCipherId(val),
          onHashChanged: (val) => ref.read(usbUnlockControllerProvider(_params).notifier).setHiddenHashId(val),
        ),
      ],
    ];
  }

  String _unlockProgressLabel(BuildContext context, UsbUnlockState state) {
    final p = state.progress;
    if (p == null || p.total <= 0) return context.l10n.decryptingDriveLabel;
    if (ContainerFormat.isLuksWire(state.containerFormat)) {
      return p.total > 1
          ? context.l10n.luksKeyslotProgress(p.attempted, p.total)
          : context.l10n.luksKeyslotProgressUnknown;
    }
    if (ContainerFormat.isBitlockerWire(state.containerFormat)) {
      return p.total > 1
          ? context.l10n.bitlockerCredentialProgress(p.attempted, p.total)
          : context.l10n.bitlockerCredentialProgressUnknown;
    }
    final hashName = hashAlgorithmName(p.hashId);
    final cipherName = p.cipherId != 255 ? cipherAlgorithmName(p.cipherId) : '';
    final slotName = p.slot == 1 ? context.l10n.hiddenVolumeSlotName : context.l10n.standardVolumeSlotName;
    final algo = cipherName.isNotEmpty ? '$hashName + $cipherName' : hashName;
    return context.l10n.veracryptAlgoProgress(algo, slotName);
  }

  List<Widget> _buildPrimaryActionSection(
    BuildContext context,
    UsbUnlockState state,
    _UsbUnlockCredentialState credState,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    if (credState != _UsbUnlockCredentialState.password) return const [];
    final isButtonEnabled = state.selected != null;

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
            ? Text(
                _unlockProgressLabel(context, state),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
              )
            : Text(
                context.l10n.unlockDriveButton,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
      ),
      if (state.loading) ...[
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: () => ref.read(usbUnlockControllerProvider(_params).notifier).cancelUnlock(),
            child: Text(context.l10n.cancelUnlockButtonLabel),
          ),
        ),
      ],
    ];
  }
}