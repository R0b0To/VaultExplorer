import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/camera/vault_camera_controller.dart';

class AutomationSettingsScreen extends StatefulWidget {
  final String uri;
  final String containerFormat;
  const AutomationSettingsScreen({
    super.key,
    required this.uri,
    required this.containerFormat,
  });
  @override
  State<AutomationSettingsScreen> createState() =>
      _AutomationSettingsScreenState();
}

class _AutomationSettingsScreenState extends State<AutomationSettingsScreen> {
  static const _api = VaultExplorerApi();
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

  bool _loading = true;
  String? _token;
  AutomationTier _tier = AutomationTier.none;
  bool _hasStoredPassword = false;
  bool _captureEnabled = false;
  bool _tokenVisible = false;
  bool _savingTier = false;
  bool _savingPassword = false;
  bool _savingCapture = false;
  final _passwordCtrl = TextEditingController();
  bool _passwordObscured = true;

  // Keyfiles/PIM only apply to standard VeraCrypt/LUKS containers -- see
  // VaultAutomationReceiver.handleUnlock, which only ever consults
  // AutomationSettings.getStoredKeyfiles/getStoredPim for that unlock path.
  // Folder vaults (Cryptomator/gocryptfs/CryFS) and BitLocker have no
  // equivalent concept, same gating unlock_sheet.dart uses for its own
  // "Advanced options" card (_isVeraCrypt || _isLuks).
  List<KeyfileRef> _automationKeyfiles = [];
  bool _pickingAutomationKeyfiles = false;
  bool _savingAutomationKeyfiles = false;
  final _automationPimCtrl = TextEditingController();
  bool _savingAutomationPim = false;

  bool get _isUsbSource => widget.uri.startsWith('usb:');

  String? get _formatForAutomation {
    final fmt = ContainerFormat.fromWire(widget.containerFormat);
    return fmt.isFolderVault ? widget.containerFormat : null;
  }

  bool get _isLuks => ContainerFormat.fromWire(widget.containerFormat).isLuks;

  bool get _isVeraCryptOrLuks {
    final fmt = ContainerFormat.fromWire(widget.containerFormat);
    return fmt == ContainerFormat.veracrypt || fmt.isLuks;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _automationPimCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = await _api.getAutomationToken();
    final config = await _api.getAutomationVaultConfig(widget.uri);
    // getAutomationVaultConfig only reports whether keyfiles are stored
    // (hasStoredKeyfiles), same as it does for the password -- the actual
    // paths (needed to render them as removable chips) come from the
    // dedicated getAutomationKeyfiles call instead. Skipped entirely for
    // formats that can't use them so a folder vault doesn't fire a call
    // whose result would just be discarded.
    final storedKeyfiles = _isVeraCryptOrLuks
        ? await _api.getAutomationKeyfiles(widget.uri)
        : null;
    final storedPim =
        _isVeraCryptOrLuks ? await _api.getAutomationPim(widget.uri) : null;
    if (!mounted) return;
    setState(() {
      _token = token;
      _tier = config.tier;
      _hasStoredPassword = config.hasStoredPassword;
      _captureEnabled = config.captureEnabled;
      _automationKeyfiles = (storedKeyfiles ?? const [])
          .map((uri) => (uri: uri, displayName: _displayNameForKeyfileUri(uri)))
          .toList();
      _automationPimCtrl.text =
          (storedPim != null && storedPim > 0) ? storedPim.toString() : '';
      _loading = false;
    });
  }

  /// getAutomationKeyfiles only returns the raw stored URI/path strings, not
  /// a resolved display name (see AutomationSettingsHandlers.kt --
  /// AutomationSettings has never needed to persist one), so a friendly
  /// label for a previously-saved keyfile is derived here rather than
  /// shown as the full URI.
  String _displayNameForKeyfileUri(String uri) {
    final segments = Uri.tryParse(uri)?.pathSegments ?? const <String>[];
    final last = segments.isNotEmpty ? segments.last : '';
    if (last.isEmpty) return uri;
    try {
      return Uri.decodeComponent(last);
    } catch (_) {
      return last;
    }
  }

  Future<void> _setTier(AutomationTier tier) async {
    setState(() => _savingTier = true);
    final ok = await _api.setAutomationTier(
      widget.uri,
      tier,
      format: _formatForAutomation,
    );
    if (!mounted) return;
    setState(() {
      _savingTier = false;
      if (ok) {
        _tier = tier;
        // Kotlin clears the stored capture opt-in server-side any time the
        // vault leaves full tier (see AutomationSettings.setTier's doc
        // comment) -- mirror that here so the switch doesn't keep showing
        // "on" for a moment after dropping to lifecycle-only.
        if (tier != AutomationTier.full) _captureEnabled = false;
      }
    });
    if (!ok) {
      showAppSnackBar(
        context,
        message: context.l10n.automationUpdateSettingsFailedMessage,
        tone: AppBannerTone.error,
      );
    }
  }

  /// Turning this on lets a headless automation trigger (TAKE_PHOTO /
  /// START_RECORDING) open the camera with no Activity and no UI on
  /// screen at all -- unlike the in-app camera_capture_screen.dart flow,
  /// there's no later moment where CAMERA/RECORD_AUDIO would naturally get
  /// requested, so this switch has to do that itself before the opt-in is
  /// persisted. Otherwise the first automation trigger would just fail
  /// with CAMERA_ERROR (permission denied) with nothing on screen to
  /// explain why. Mirrors camera_capture_screen.dart's own
  /// hasPermissions()/requestPermissions() sequence.
  Future<void> _setCaptureEnabled(bool enabled) async {
    setState(() => _savingCapture = true);
    if (enabled) {
      final hasPerms = await VaultCameraController.hasPermissions();
      if (!hasPerms) {
        final granted = await VaultCameraController.requestPermissions();
        if (!mounted) return;
        if (!granted) {
          setState(() => _savingCapture = false);
          showAppSnackBar(
            context,
            message: context.l10n.cameraPermissionsRequiredMessage,
            tone: AppBannerTone.error,
          );
          return;
        }
      }
    }
    final ok = await _api.setAutomationCaptureEnabled(widget.uri, enabled);
    if (!mounted) return;
    setState(() {
      _savingCapture = false;
      if (ok) _captureEnabled = enabled;
    });
    if (!ok) {
      showAppSnackBar(
        context,
        message: context.l10n.automationUpdateSettingsFailedMessage,
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _savePassword() async {
    final clearing = _passwordCtrl.text.isEmpty;
    setState(() => _savingPassword = true);
    final ok = await _api.setAutomationPassword(
      widget.uri,
      clearing ? null : _passwordCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _savingPassword = false;
      if (ok) {
        _hasStoredPassword = !clearing;
        _passwordCtrl.clear();
      }
    });
    final l10n = context.l10n;
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
    setState(() => _pickingAutomationKeyfiles = true);
    try {
      final picked = await _api.pickKeyfiles();
      if (!mounted) return;
      final merged = [..._automationKeyfiles];
      for (final k in picked) {
        if (!merged.any((existing) => existing.uri == k.uri)) {
          merged.add(k);
        }
      }
      setState(() => _automationKeyfiles = merged);
      await _saveAutomationKeyfiles();
    } on PlatformException catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: e.message ?? context.l10n.couldNotPickKeyfiles,
          tone: AppBannerTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _pickingAutomationKeyfiles = false);
    }
  }

  Future<void> _removeAutomationKeyfile(KeyfileRef keyfile) async {
    setState(
      () => _automationKeyfiles = _automationKeyfiles
          .where((k) => k.uri != keyfile.uri)
          .toList(),
    );
    await _saveAutomationKeyfiles();
  }

  Future<void> _saveAutomationKeyfiles() async {
    setState(() => _savingAutomationKeyfiles = true);
    final paths = _automationKeyfiles.map((k) => k.uri).toList();
    final ok = await _api.setAutomationKeyfiles(
      widget.uri,
      paths.isEmpty ? null : paths,
    );
    if (!mounted) return;
    setState(() => _savingAutomationKeyfiles = false);
    if (!ok) {
      showAppSnackBar(
        context,
        message: context.l10n.automationUpdateSettingsFailedMessage,
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _saveAutomationPim() async {
    final l10n = context.l10n;
    setState(() => _savingAutomationPim = true);
    final raw = _automationPimCtrl.text.trim();
    final pim = raw.isEmpty ? null : clampPim(int.tryParse(raw) ?? 0);
    final ok = await _api.setAutomationPim(widget.uri, pim);
    if (!mounted) return;
    setState(() {
      _savingAutomationPim = false;
      // Reflect the clamped value back so a value the person typed above
      // the cap (see clampPim's doc comment) doesn't keep showing
      // something that isn't what actually got stored.
      if (ok && pim != null) _automationPimCtrl.text = pim.toString();
    });
    showAppSnackBar(
      context,
      message: ok
          ? l10n.automationPimSavedMessage
          : l10n.automationUpdateSettingsFailedMessage,
      tone: ok ? AppBannerTone.success : AppBannerTone.error,
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
    final newToken = await _api.regenerateAutomationToken();
    if (!mounted) return;
    if (newToken != null) {
      setState(() {
        _token = newToken;
        _tokenVisible = true;
      });
      showAppSnackBar(
        context,
        message: l10n.automationTokenRegeneratedMessage,
        tone: AppBannerTone.success,
      );
    } else {
      showAppSnackBar(
        context,
        message: l10n.automationRegenerateTokenFailedMessage,
        tone: AppBannerTone.error,
      );
    }
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    showAppSnackBar(
      context,
      message: context.l10n.labelCopiedToClipboard(label),
      tone: AppBannerTone.success,
    );
  }

  @override
  Widget build(BuildContext context) {
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
            value: _tier,
            enabled: !_savingTier,
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
      if (_tier != AutomationTier.none) ...[
        const SizedBox(height: 24),
        SectionHeader(l10n.automationPasswordSectionHeader),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            _hasStoredPassword
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
            labelText: _hasStoredPassword
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
            onPressed: _savingPassword ? null : _savePassword,
            child: Text(
              _passwordCtrl.text.isEmpty && _hasStoredPassword
                  ? l10n.automationClearPasswordButton
                  : l10n.automationSavePasswordButton,
            ),
          ),
        ),
      ],
      if (_tier != AutomationTier.none && _isVeraCryptOrLuks) ...[
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
              keyfiles: _automationKeyfiles,
              picking: _pickingAutomationKeyfiles,
              onPick: _pickAutomationKeyfiles,
              onRemove: _removeAutomationKeyfile,
              enabled: !_savingAutomationKeyfiles,
            ),
          ],
        ),
        if (_isLuks && _automationKeyfiles.isNotEmpty) ...[
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
          enabled: !_savingAutomationPim,
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
            onPressed: _savingAutomationPim ? null : _saveAutomationPim,
            child: Text(l10n.automationSavePimButton),
          ),
        ),
      ],
      if (_tier == AutomationTier.full) ...[
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
              value: _captureEnabled,
              onChanged: _savingCapture
                  ? null
                  : _setCaptureEnabled,
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
              _tokenVisible ? (_token ?? '') : maskedToken,
              style: textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    _tokenVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(
                    () => _tokenVisible = !_tokenVisible,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: l10n.copy,
                  onPressed: _token == null
                      ? null
                      : () => _copy(
                          l10n.automationTokenSectionHeader,
                          _token!,
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
          if (_tier == AutomationTier.full && _captureEnabled) ...[
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
          onTap: () => _api.launchUrl(_tutorialUrl),
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
      body: _loading
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