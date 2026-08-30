import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_automation_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/features/dashboard/widgets/automation_settings_controller.dart';

class AutomationSettingsScreen extends ConsumerStatefulWidget {
  final String uri;
  final String containerFormat;
  const AutomationSettingsScreen({
    super.key,
    required this.uri,
    required this.containerFormat,
  });
  @override
  ConsumerState<AutomationSettingsScreen> createState() =>
      _AutomationSettingsScreenState();
}

class _AutomationSettingsScreenState
    extends ConsumerState<AutomationSettingsScreen> {
  static const _tutorialUrl =
      'https://github.com/R0b0To/VaultExplorer/blob/main/docs/vaultexplorer-automation-setup.md';
  static const _packageName = 'com.aeidolon.vaultexplorer';
  static const _className =
      'com.aeidolon.vaultexplorer.automation.VaultAutomationReceiver';
  static const _actionUnlock =
      'com.aeidolon.vaultexplorer.action.UNLOCK_VAULT';
  static const _actionLock = 'com.aeidolon.vaultexplorer.action.LOCK_VAULT';
  static const _actionImport =
      'com.aeidolon.vaultexplorer.action.IMPORT_FILE';
  static const _actionExport =
      'com.aeidolon.vaultexplorer.action.EXPORT_FILE';
  static const _actionImportFolder =
      'com.aeidolon.vaultexplorer.action.IMPORT_FOLDER';
  static const _actionExportFolder =
      'com.aeidolon.vaultexplorer.action.EXPORT_FOLDER';
  static const _actionTakePhoto =
      'com.aeidolon.vaultexplorer.action.TAKE_PHOTO';
  static const _actionStartRecording =
      'com.aeidolon.vaultexplorer.action.START_RECORDING';
  static const _actionStopRecording =
      'com.aeidolon.vaultexplorer.action.STOP_RECORDING';
  static const _actionWipe = 'com.aeidolon.vaultexplorer.action.WIPE_FILE';

  final _passwordCtrl = TextEditingController();
  bool _passwordObscured = true;
  final _automationPimCtrl = TextEditingController();
  bool _appliedLoadedPim = false;

  bool get _isUsbSource => widget.uri.startsWith('usb:');

  bool get _isLuks => ContainerFormat.fromWire(widget.containerFormat).isLuks;

  bool get _isVeraCryptOrLuks {
    final fmt = ContainerFormat.fromWire(widget.containerFormat);
    return fmt == ContainerFormat.veracrypt || fmt.isLuks;
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _automationPimCtrl.dispose();
    super.dispose();
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    showAppSnackBar(
      context,
      message: context.l10n.labelCopiedToClipboard(label),
      tone: AppBannerTone.success,
    );
  }

  Future<void> _setTier(AutomationTier tier) async {
    final ok = await ref
        .read(automationSettingsProvider(widget.uri, widget.containerFormat).notifier)
        .setTier(tier);
    if (!mounted || ok) return;
    showAppSnackBar(
      context,
      message: context.l10n.automationUpdateSettingsFailedMessage,
      tone: AppBannerTone.error,
    );
  }

  Future<void> _setCaptureEnabled(bool enabled) async {
    final error = await ref
        .read(automationSettingsProvider(widget.uri, widget.containerFormat).notifier)
        .setCaptureEnabled(enabled, context.l10n);
    if (!mounted || error == null) return;
    showAppSnackBar(context, message: error, tone: AppBannerTone.error);
  }

  Future<void> _savePassword() async {
    final l10n = context.l10n;
    final clearing = _passwordCtrl.text.isEmpty;
    final ok = await ref
        .read(automationSettingsProvider(widget.uri, widget.containerFormat).notifier)
        .savePassword(_passwordCtrl.text);
    if (!mounted) return;
    if (ok) _passwordCtrl.clear();
    showAppSnackBar(
      context,
      message: !ok
          ? l10n.automationSavePasswordFailedMessage
          : clearing
              ? l10n.automationPasswordClearedMessage
              : l10n.automationPasswordSavedMessage,
      tone: ok ? AppBannerTone.success : AppBannerTone.error,
    );
  }

  Future<void> _pickAutomationKeyfiles() async {
    final error = await ref
        .read(automationSettingsProvider(widget.uri, widget.containerFormat).notifier)
        .pickAutomationKeyfiles(context.l10n);
    if (!mounted || error == null) return;
    showAppSnackBar(context, message: error, tone: AppBannerTone.error);
  }

  Future<void> _removeAutomationKeyfile(KeyfileRef keyfile) async {
    final error = await ref
        .read(automationSettingsProvider(widget.uri, widget.containerFormat).notifier)
        .removeAutomationKeyfile(keyfile, context.l10n);
    if (!mounted || error == null) return;
    showAppSnackBar(context, message: error, tone: AppBannerTone.error);
  }

  Future<void> _saveAutomationPim() async {
    final l10n = context.l10n;
    final result = await ref
        .read(automationSettingsProvider(widget.uri, widget.containerFormat).notifier)
        .saveAutomationPim(_automationPimCtrl.text);
    if (!mounted) return;
    // Reflect the clamped value back so a value the person typed above
    // the cap (see clampPim's doc comment) doesn't keep showing something
    // that isn't what actually got stored.
    if (result.ok && result.pim != null) {
      _automationPimCtrl.text = result.pim.toString();
    }
    showAppSnackBar(
      context,
      message: result.ok
          ? l10n.automationPimSavedMessage
          : l10n.automationUpdateSettingsFailedMessage,
      tone: result.ok ? AppBannerTone.success : AppBannerTone.error,
    );
  }

  Future<void> _regenerateToken() async {
    final l10n = context.l10n;
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.automationRegenerateTokenDialogTitle,
      message: l10n.automationRegenerateTokenDialogMessage,
      confirmLabel: l10n.automationRegenerateConfirmLabel,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (!confirmed) return;
    final ok = await ref
        .read(automationSettingsProvider(widget.uri, widget.containerFormat).notifier)
        .regenerateToken();
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: ok
          ? l10n.automationTokenRegeneratedMessage
          : l10n.automationRegenerateTokenFailedMessage,
      tone: ok ? AppBannerTone.success : AppBannerTone.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(automationSettingsProvider(widget.uri, widget.containerFormat));
    ref.listen<AutomationSettingsState>(automationSettingsProvider(widget.uri, widget.containerFormat), (previous, next) {
      if (!_appliedLoadedPim && next.loadedPimText != null) {
        _appliedLoadedPim = true;
        _automationPimCtrl.text = next.loadedPimText!;
      }
    });

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final wideLayout = context.screen.useWideLayout;
    final maskedToken = List.filled(8, '•').join();

    final leftColumnWidgets = <Widget>[
      SectionHeader(l10n.automationThisVaultSectionHeader),
      SectionCard(
        children: [
          OptionPickerTile<AutomationTier>(
            label: l10n.automationAccessLabel,
            value: state.tier,
            enabled: !state.savingTier,
            options: AutomationTier.values
                .map(
                  (t) => SelectOption(
                    value: t,
                    label: t.label(l10n),
                    subtitle: t.subtitle(l10n),
                  ),
                )
                .toList(),
            onChanged: _setTier,
          ),
        ],
      ),
      if (state.tier != AutomationTier.none) ...[
        const SizedBox(height: 24),
        SectionHeader(l10n.automationPasswordSectionHeader),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            state.hasStoredPassword
                ? l10n.automationPasswordStoredHint
                : l10n.automationPasswordNotStoredHint,
            style: textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordCtrl,
          obscureText: _passwordObscured,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: state.hasStoredPassword
                ? l10n.automationNewPasswordFieldLabel
                : l10n.automationPasswordFieldLabel,
            suffixIcon: PasswordVisibilityToggle(
              obscured: _passwordObscured,
              onToggle: () => setState(
                () => _passwordObscured = !_passwordObscured,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: state.savingPassword ? null : _savePassword,
            child: Text(
              _passwordCtrl.text.isEmpty && state.hasStoredPassword
                  ? l10n.automationClearPasswordButton
                  : l10n.automationSavePasswordButton,
            ),
          ),
        ),
      ],
      if (state.tier != AutomationTier.none && _isVeraCryptOrLuks) ...[
        const SizedBox(height: 24),
        SectionHeader(l10n.automationKeyfilesPimSectionHeader),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.automationKeyfilesPimDescription,
            style: textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SectionCard(
          children: [
            KeyfilesPicker(
              keyfiles: state.automationKeyfiles,
              picking: state.pickingAutomationKeyfiles,
              onPick: _pickAutomationKeyfiles,
              onRemove: _removeAutomationKeyfile,
              enabled: !state.savingAutomationKeyfiles,
            ),
          ],
        ),
        if (_isLuks && state.automationKeyfiles.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              l10n.luksKeyfileReplacesPasswordNote,
              style: textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _automationPimCtrl,
          enabled: !state.savingAutomationPim,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: l10n.pimOptionalLabel,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: state.savingAutomationPim ? null : _saveAutomationPim,
            child: Text(l10n.automationSavePimButton),
          ),
        ),
      ],
      if (state.tier == AutomationTier.full) ...[
        const SizedBox(height: 24),
        SectionHeader(l10n.automationCameraSectionHeader),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.automationCameraDescription,
            style: textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SectionCard(
          children: [
            SwitchListTile(
              title: Text(l10n.automationAllowCameraCapture),
              value: state.captureEnabled,
              onChanged: state.savingCapture ? null : _setCaptureEnabled,
            ),
          ],
        ),
      ],
      const SizedBox(height: 24),
      SectionHeader(l10n.automationTokenSectionHeader),
      Text(
        l10n.automationTokenDescription,
        style: textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 8),
      SectionCard(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            title: Text(
              state.tokenVisible ? (state.token ?? '') : maskedToken,
              style: textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    state.tokenVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => ref
                      .read(
                        automationSettingsProvider(
                          widget.uri,
                          widget.containerFormat,
                        ).notifier,
                      )
                      .toggleTokenVisible(),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: l10n.copy,
                  onPressed: state.token == null
                      ? null
                      : () => _copy(
                          l10n.automationTokenSectionHeader,
                          state.token!,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _regenerateToken,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(l10n.automationRegenerateTokenButton),
      ),
    ];

    final rightColumnWidgets = <Widget>[
      SectionHeader(l10n.automationConfigSectionHeader),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          l10n.automationConfigIntro,
          style: textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ),
      const SizedBox(height: 8),
      SectionCard(
        children: [
          _CopyRow(
            label: l10n.automationConfigPackageLabel,
            value: _packageName,
            onCopy: _copy,
          ),
          _CopyRow(
            label: l10n.automationConfigClassLabel,
            value: _className,
            onCopy: _copy,
          ),
          _CopyRow(
            label: l10n.automationConfigVaultUriLabel,
            value: widget.uri,
            onCopy: _copy,
          ),
        ],
      ),
      const SizedBox(height: 16),
      SectionHeader(l10n.automationConfigActionsSectionHeader),
      SectionCard(
        children: [
          _CopyRow(
            label: l10n.automationActionUnlockLabel,
            value: _actionUnlock,
            onCopy: _copy,
          ),
          _CopyRow(
            label: l10n.automationActionLockLabel,
            value: _actionLock,
            onCopy: _copy,
          ),
          _CopyRow(
            label: l10n.automationActionImportLabel,
            value: _actionImport,
            onCopy: _copy,
          ),
          _CopyRow(
            label: l10n.automationActionExportLabel,
            value: _actionExport,
            onCopy: _copy,
          ),
          _CopyRow(
            label: l10n.automationActionImportFolderLabel,
            value: _actionImportFolder,
            onCopy: _copy,
          ),
          _CopyRow(
            label: l10n.automationActionExportFolderLabel,
            value: _actionExportFolder,
            onCopy: _copy,
          ),
          if (state.tier == AutomationTier.full && state.captureEnabled) ...[
            _CopyRow(
              label: l10n.automationActionTakePhotoLabel,
              value: _actionTakePhoto,
              onCopy: _copy,
            ),
            _CopyRow(
              label: l10n.automationActionStartRecordingLabel,
              value: _actionStartRecording,
              onCopy: _copy,
            ),
            _CopyRow(
              label: l10n.automationActionStopRecordingLabel,
              value: _actionStopRecording,
              onCopy: _copy,
            ),
          ],
          _CopyRow(
            label: l10n.automationActionWipeLabel,
            value: _actionWipe,
            onCopy: _copy,
          ),
        ],
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          l10n.automationDocCommentFootnote,
          style: textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => ref.read(vaultFileIoApiProvider).launchUrl(_tutorialUrl),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 8,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.menu_book_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.automationTutorialLinkLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.automationScreenTitle)),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isUsbSource)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          l10n.automationUsbUnsupportedMessage,
                          style: textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    else if (wideLayout)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: leftColumnWidgets,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: rightColumnWidgets,
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...leftColumnWidgets,
                          const SizedBox(height: 24),
                          ...rightColumnWidgets,
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final void Function(String label, String value) onCopy;
  const _CopyRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      title: Text(
        label,
        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          value,
          style: textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.copy_rounded),
        tooltip: context.l10n.copy,
        onPressed: () => onCopy(label, value),
      ),
      onTap: () => onCopy(label, value),
    );
  }
}