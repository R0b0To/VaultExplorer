import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';
import 'package:vaultexplorer/features/unlock/usb_unlock_controller.dart';

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

  UsbUnlockParams get _params => UsbUnlockParams(
        existingRecord: widget.existingRecord,
        prefillPassword: widget.prefillPassword,
        documentProvider: widget.documentProvider,
        autoMountFolders: widget.autoMountFolders,
        mountedUris: widget.mountedUris,
      );

  GestureTapCallback? get dismissKeyboard => null;

  bool get _passwordPrefilled =>
      widget.prefillPassword != null && _passwordCtrl.text == widget.prefillPassword;

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
          ),
          actions: [
            if (!state.loading && !state.requestingPermission)
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.read(usbUnlockControllerProvider(_params).notifier).loadDevices(),
              ),
          ],
          bottom: state.loading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(
                    color: cs.primary,
                    backgroundColor: cs.primaryContainer,
                  ),
                )
              : null,
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: dismissKeyboard,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDevicePickerCard(state, cs, textTheme),
                  const SizedBox(height: 10),
                  _buildCredentialSection(state, cs, textTheme),
                  if (state.unlockMethod == ContainerUnlockMethod.password) ...[
                    const SizedBox(height: 10),
                    _buildAdvancedOptionsSection(state, cs, textTheme),
                  ],
                  _buildPrimaryActionSection(state, cs, textTheme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

    return SectionCard(
      children: [
        ...state.devices.map((d) {
          final isSelected = state.selected?.deviceName == d.deviceName;
          return ListTile(
            leading: Icon(Icons.usb_rounded, color: isSelected ? cs.primary : cs.onSurfaceVariant),
            title: Text(d.productName),
            trailing: Radio<UsbDeviceInfo>(
              value: d,
              groupValue: state.selected,
              onChanged: (_) => ref.read(usbUnlockControllerProvider(_params).notifier).selectDevice(d),
            ),
            onTap: () => ref.read(usbUnlockControllerProvider(_params).notifier).selectDevice(d),
          );
        }),
      ],
    );
  }

  Widget _buildCredentialSection(UsbUnlockState state, ColorScheme cs, TextTheme textTheme) {
    if (state.loadingAuth) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    if (state.unlockMethod == ContainerUnlockMethod.pattern && !state.showPasswordFallback) {
      return SectionCard(
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
                  onPatternComplete: (p) =>
                      ref.read(usbUnlockControllerProvider(_params).notifier).onPatternComplete(p, context.l10n),
                  showError: state.patternError,
                ),
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
      );
    }

    if (state.unlockMethod == ContainerUnlockMethod.pin && !state.showPasswordFallback) {
      return SectionCard(
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
                  onPinComplete: (p) =>
                      ref.read(usbUnlockControllerProvider(_params).notifier).onPinComplete(p, context.l10n),
                  showError: state.pinError,
                ),
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
      );
    }

    if (state.unlockMethod == ContainerUnlockMethod.biometrics && !state.showPasswordFallback) {
      return SectionCard(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              children: [
                Icon(Icons.fingerprint_rounded, size: 48, color: cs.primary),
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
      );
    }

    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              labelText: context.l10n.passwordFieldLabel,
              prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: cs.primary),
              suffixIcon: PasswordVisibilityToggle(
                obscured: _obscure,
                onToggle: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _onUnlock(),
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedOptionsSection(
    UsbUnlockState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return SectionCard(
      children: [
        KeyfilesPicker(
          keyfiles: state.keyfiles,
          picking: state.pickingKeyfiles,
          onPick: () => ref.read(usbUnlockControllerProvider(_params).notifier).pickKeyfiles(),
          onRemove: (k) =>
              ref.read(usbUnlockControllerProvider(_params).notifier).removeKeyfile(k),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          value: state.readOnly,
          onChanged: state.loading
              ? null
              : (v) => ref.read(usbUnlockControllerProvider(_params).notifier).setReadOnly(v),
          title: Text(context.l10n.readOnlyModeLabel),
          secondary: Icon(Icons.visibility_outlined, color: cs.primary),
        ),
      ],
    );
  }

  Widget _buildPrimaryActionSection(
    UsbUnlockState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error != null) ...[
          const SizedBox(height: 10),
          InlineErrorBanner(state.error!),
        ],
        const SizedBox(height: 10),
        FilledButton(
          onPressed: state.loading ? null : _onUnlock,
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
                  context.l10n.unlockDriveButton,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
        ),
      ],
    );
  }
}