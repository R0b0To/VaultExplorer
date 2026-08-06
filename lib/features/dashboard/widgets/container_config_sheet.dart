import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_setup_sheet.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/features/dashboard/widgets/change_password_screen.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

class ContainerConfigScreen extends StatefulWidget {
  final String uri;
  final String currentLabel;
  final ContainerRecord? existingRecord;
  final void Function(ContainerRecord record) onSaved;
  final AppSettings? appSettings;
  final MountedContainer? mountedContainer;
  const ContainerConfigScreen({
    super.key,
    required this.uri,
    required this.currentLabel,
    this.existingRecord,
    required this.onSaved,
    this.appSettings,
    this.mountedContainer,
  });
  @override
  State<ContainerConfigScreen> createState() => _ContainerConfigScreenState();
}

class _ContainerConfigScreenState extends State<ContainerConfigScreen> with KeyfilePickerMixin {
  late TextEditingController _labelCtrl;
  late TextEditingController _passwordCtrl;
  late ContainerUnlockMethod _unlockMethod;
  late bool _showPassword;
  late int _autoCloseMins;
  late bool _documentProvider;
  ThumbnailCacheMode? _thumbnailCacheMode;
  ThumbnailQuality? _thumbnailQuality;
  bool _cacheDerivedKey = false;
  int _cipherId = 255;
  int _hashId = 255;
  String? _patternHash;
  bool _biometricAvailable = false;
  late bool _settingsLocked;
  bool _changePassword = false;
  String get _containerFormat =>
      widget.existingRecord?.containerFormat ??
      widget.mountedContainer?.containerFormat ??
      'veracrypt';
  bool get _isCryptomator => ContainerFormat.isCryptomatorWire(_containerFormat);
  bool get _isGocryptfs => ContainerFormat.isGocryptfsWire(_containerFormat);
  bool get _isCryfs => ContainerFormat.isCryfsWire(_containerFormat);
  bool get _isBitlocker => ContainerFormat.isBitlockerWire(_containerFormat);
  bool _saving = false;
  bool _loadingPassword = true;
  late String _initialLabel;
  late ContainerUnlockMethod _initialUnlockMethod;
  late int _initialAutoCloseMins;
  late bool _initialDocumentProvider;
  late int _initialCipherId;
  late int _initialHashId;
  ThumbnailCacheMode? _initialThumbnailCacheMode;
  ThumbnailQuality? _initialThumbnailQuality;
  bool? _initialCacheDerivedKey;
  String? _initialPatternHash;
  static const _autoCloseOptions = [0, 1, 2, 5, 10, 15, 30, 60];

  @override
  void onKeyfilePickError(String message) {
    if (mounted) {
      showAppSnackBar(context, message: message, tone: AppBannerTone.error);
    }
  }

  @override
  void initState() {
    super.initState();
    final rec = widget.existingRecord;
    if (rec != null &&
        rec.unlockMethod != ContainerUnlockMethod.password &&
        rec.keyfiles.isNotEmpty) {
      keyfiles.addAll(rec.keyfiles.map((k) => (uri: k['uri']!, displayName: k['name']!)));
    }
    _initialLabel = rec?.label.isNotEmpty == true ? rec!.label : widget.currentLabel;
    _initialUnlockMethod = rec?.unlockMethod ?? ContainerUnlockMethod.password;
    _initialAutoCloseMins = rec?.autoCloseMins ?? 0;
    _initialDocumentProvider =
        rec?.documentProvider ?? widget.appSettings?.defaultDocumentProvider ?? false;
    _initialCipherId = rec?.cipherId ?? 255;
    _initialHashId = rec?.hashId ?? 255;
    _initialCacheDerivedKey = rec?.cacheDerivedKey;
    _labelCtrl = TextEditingController(text: _initialLabel);
    _passwordCtrl = TextEditingController();
    _labelCtrl.addListener(() => setState(() {}));
    _unlockMethod = _initialUnlockMethod;
    _showPassword = false;
    _autoCloseMins = _initialAutoCloseMins;
    _documentProvider = _initialDocumentProvider;
    _thumbnailCacheMode = rec?.thumbnailCacheMode;
    _thumbnailQuality = rec?.thumbnailQuality;
    _cacheDerivedKey =
        rec?.cacheDerivedKey ?? widget.appSettings?.defaultDerivedKeyCacheEnabled ?? false;
    _cipherId = _initialCipherId;
    _hashId = _initialHashId;
    final recentlyUnlocked = widget.mountedContainer != null &&
        DateTime.now().difference(widget.mountedContainer!.mountedAt) <
            const Duration(seconds: 30);
    _settingsLocked = rec != null && !recentlyUnlocked;
    _initAsync();
  }

  bool _clearingCache = false;
  Future<void> _clearThumbnailCache() async {
    final confirm = await showAppConfirmDialog(
      context,
      title: context.l10n.clearThumbnailCacheDialogTitle,
      message: context.l10n.clearThumbnailCacheDialogMessage,
      confirmLabel: context.l10n.clearCacheButton,
      isDestructive: true,
    );
    if (!confirm || !mounted) return;
    setState(() => _clearingCache = true);
    bool appCacheCleared = false;
    bool containerCacheCleared = false;
    bool isLocked = false;
    try {
      await ThumbnailCacheService.clearAppCacheByUri(widget.uri);
      appCacheCleared = true;
      await ThumbnailCacheService.clearInContainerCacheByUri(widget.uri);
      containerCacheCleared = true;
    } on PlatformException catch (e) {
      if (e.code == 'NOT_MOUNTED') {
        isLocked = true;
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _clearingCache = false);
        if (isLocked) {
          showAppSnackBar(
            context,
            message: context.l10n.appCacheClearedUnlockMessage,
            tone: AppBannerTone.warning,
          );
        } else if (appCacheCleared && containerCacheCleared) {
          showAppSnackBar(
            context,
            message: context.l10n.allThumbnailCachesClearedMessage,
            tone: AppBannerTone.success,
          );
        } else if (appCacheCleared) {
          showAppSnackBar(
            context,
            message: context.l10n.appCacheClearedContainerFailedMessage,
            tone: AppBannerTone.warning,
          );
        } else {
          showAppSnackBar(
            context,
            message: context.l10n.failedToClearThumbnailCachesMessage,
            tone: AppBannerTone.error,
          );
        }
      }
    }
  }

  Future<void> _initAsync() async {
    try {
      final tempPw = await AppSecureStorage.instance.read(key: 'temp_pw_${widget.uri}');
      if (tempPw != null && tempPw.isNotEmpty && mounted) {
        setState(() => _passwordCtrl.text = tempPw);
      }
    } catch (_) {}
    try {
      final localAuth = LocalAuthentication();
      _biometricAvailable = await localAuth.canCheckBiometrics &&
          await localAuth.isDeviceSupported();
    } catch (_) {}
    try {
      final settings = widget.appSettings ?? await AppSettingsService.loadSettings();
      if (mounted) {
        setState(() {
          _thumbnailCacheMode ??= settings.defaultThumbnailCacheMode;
          _initialThumbnailCacheMode = _thumbnailCacheMode;
          _thumbnailQuality ??= settings.defaultThumbnailQuality;
          _initialThumbnailQuality = _thumbnailQuality;
          if (widget.appSettings == null && widget.existingRecord == null) {
            _cacheDerivedKey = settings.defaultDerivedKeyCacheEnabled;
          }
          _initialCacheDerivedKey ??= _cacheDerivedKey;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _thumbnailCacheMode ??= ThumbnailCacheMode.appCache;
          _initialThumbnailCacheMode = _thumbnailCacheMode;
        });
      }
    }
    if (_unlockMethod == ContainerUnlockMethod.pattern) {
      _patternHash = await ContainerRepository.instance.getPatternHash(widget.uri);
      _initialPatternHash = _patternHash;
    }
    if (mounted) setState(() => _loadingPassword = false);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _isModified {
    if (widget.existingRecord == null) return true;
    if (_labelCtrl.text.trim() != _initialLabel) return true;
    if (_unlockMethod != _initialUnlockMethod) return true;
    if (_autoCloseMins != _initialAutoCloseMins) return true;
    if (_documentProvider != _initialDocumentProvider) return true;
    if (_thumbnailCacheMode != _initialThumbnailCacheMode) return true;
    if (_thumbnailQuality != _initialThumbnailQuality) return true;
    if (_cacheDerivedKey != _initialCacheDerivedKey) return true;
    if (_cipherId != _initialCipherId) return true;
    if (_hashId != _initialHashId) return true;
    if (_changePassword) return true;
    if (_patternHash != _initialPatternHash) return true;
    final initialKeyfilesCount =
        (widget.existingRecord?.unlockMethod != ContainerUnlockMethod.password)
            ? (widget.existingRecord?.keyfiles.length ?? 0)
            : 0;
    final currentKeyfilesCount =
        (_unlockMethod != ContainerUnlockMethod.password) ? keyfiles.length : 0;
    if (currentKeyfilesCount != initialKeyfilesCount) return true;
    if (_unlockMethod != ContainerUnlockMethod.password && initialKeyfilesCount > 0) {
      final initialUris =
          widget.existingRecord?.keyfiles.map((k) => k['uri']).toSet() ?? {};
      final currentUris = keyfiles.map((k) => k.uri).toSet();
      if (initialUris.difference(currentUris).isNotEmpty ||
          currentUris.difference(initialUris).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  bool get _wasPasswordless =>
      widget.existingRecord == null ||
      widget.existingRecord!.unlockMethod == ContainerUnlockMethod.password;

  bool get _unlockMethodNeedsPassword =>
      _unlockMethod != ContainerUnlockMethod.password;

  bool get _needsPasswordSetup {
    if (!_unlockMethodNeedsPassword) return false;
    if (_wasPasswordless || _changePassword) {
      if (_passwordCtrl.text.isEmpty && !_cacheDerivedKey && keyfiles.isEmpty) {
        return true;
      }
    }
    return false;
  }

  bool get _needsPatternSetup =>
      _unlockMethod == ContainerUnlockMethod.pattern && _patternHash == null;

  bool get _canSave => !_needsPasswordSetup && !_needsPatternSetup;

  Future<void> _save() async {
    if (_needsPatternSetup) {
      showAppSnackBar(
        context,
        message: context.l10n.patternSetupRequiredBeforeSaving,
        tone: AppBannerTone.warning,
      );
      return;
    }
    setState(() => _saving = true);
    final label = _labelCtrl.text.trim().isEmpty
        ? widget.currentLabel
        : _labelCtrl.text.trim();
    final needsPassword = _unlockMethodNeedsPassword;
    final shouldSavePassword =
        needsPassword && (_wasPasswordless || _changePassword);

    final record = ContainerRecord(
      uri: widget.uri,
      label: label,
      rememberPassword: needsPassword,
      unlockMethod: _unlockMethod,
      autoCloseMins: _autoCloseMins,
      documentProvider: _documentProvider,
      documentProviderFolders: widget.existingRecord?.documentProviderFolders ?? const [],
      thumbnailCacheMode: _thumbnailCacheMode,
      thumbnailQuality: _thumbnailQuality,
      cacheDerivedKey: _cacheDerivedKey,
      pendingPassword: shouldSavePassword ? _passwordCtrl.text : null,
      pendingPatternHash: _unlockMethod == ContainerUnlockMethod.pattern
          ? _patternHash
          : null,
      cipherId: _cipherId,
      hashId: _hashId,
      containerFormat: _containerFormat,
      keyfiles: needsPassword
          ? keyfiles.map((k) => {'uri': k.uri, 'name': k.displayName}).toList()
          : const [],
    );

    await ContainerRepository.instance.save(record);
    if (!_cacheDerivedKey) {
      await vaultExplorerApi.clearDerivedKey(widget.uri);
    }
    widget.onSaved(record);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _setupPattern() async {
    final hash = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PatternSetupSheet(),
    );
    if (hash != null && mounted) {
      setState(() => _patternHash = hash);
    }
  }

  Future<void> _authenticateSettings() async {
    final record = widget.existingRecord;
    if (record == null) return;
    if (record.unlockMethod == ContainerUnlockMethod.biometrics) {
      try {
        final localAuth = LocalAuthentication();
        final ok = await localAuth.authenticate(
          localizedReason: context.l10n.authenticateToModifySettingsPrompt,
          persistAcrossBackgrounding: true,
        );
        if (ok && mounted) {
          final savedPassword = await ContainerRepository.instance.getPassword(widget.uri);
          setState(() {
            _settingsLocked = false;
            if (savedPassword != null) _passwordCtrl.text = savedPassword;
          });
        }
      } catch (_) {}
    } else if (record.unlockMethod == ContainerUnlockMethod.pattern) {
      if (_patternHash == null) {
        if (mounted) setState(() => _settingsLocked = false);
        return;
      }
      final hash = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _PatternVerifySheet(
          storedHash: _patternHash!,
        ),
      );
      if (hash != null && mounted) {
        final savedPassword = await ContainerRepository.instance.getPassword(widget.uri);
        setState(() {
          _settingsLocked = false;
          if (savedPassword != null) _passwordCtrl.text = savedPassword;
        });
      }
    } else {
      final savedPassword = await ContainerRepository.instance.getPassword(widget.uri);
      if (!mounted) return;
      final verified = await showDialog<
          ({String password, List<KeyfileRef> keyfiles, int cipherId, int hashId})>(
        context: context,
        builder: (context) => _RealPasswordGateDialog(
          uri: widget.uri,
          cipherId: record.cipherId,
          hashId: record.hashId,
          documentProvider: _documentProvider,
          cacheDerivedKey: _cacheDerivedKey,
          containerFormat: record.containerFormat,
          initialKeyfiles: record.keyfiles,
          initialPassword: savedPassword,
        ),
      );
      if (verified != null && mounted) {
        setState(() {
          _settingsLocked = false;
          _passwordCtrl.text = verified.password;
          keyfiles.clear();
          keyfiles.addAll(verified.keyfiles);
          _cipherId = verified.cipherId;
          _hashId = verified.hashId;
        });
      }
    }
  }

  Future<void> _editDisplayName() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _DisplayNameDialog(
        initialText: _labelCtrl.text,
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      _labelCtrl.text = result.trim();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.uri.startsWith('usb:') ? context.l10n.usbVaultSettingsTitle : context.l10n.vaultSettingsTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              _containerFormat.toUpperCase(),
              style: textTheme.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(context.l10n.generalSectionHeader),
                  SectionCard(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        title: Text(
                            _labelCtrl.text.trim().isEmpty
                                ? _initialLabel
                                : _labelCtrl.text.trim(),
                          ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: context.l10n.renameTooltip,
                          onPressed: _editDisplayName,
                        ),
                        onTap: _editDisplayName,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SectionHeader(context.l10n.securityCredentialsSectionHeader),
                  SectionCard(
                    children: [
                      if (_settingsLocked) ...[
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: cs.outlineVariant.withValues(alpha: 0)),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  context.l10n.securityOptionsLockedTitle,
                                  style: textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  context.l10n.authenticateOriginalCredentialsMessage,
                                  style: textTheme.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _authenticateSettings,
                                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  label: Text(context.l10n.unlockSettingsButton),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        OptionPickerTile<ContainerUnlockMethod>(
                          label: context.l10n.unlockCredentialsLabel,
                          value: _unlockMethod,
                          subtitle: _unlockMethod.subtitle,
                          options: ContainerUnlockMethod.values
                              .where((m) =>
                                  m != ContainerUnlockMethod.biometrics ||
                                  _biometricAvailable ||
                                  _unlockMethod == m)
                              .map((m) {
                                final isUnavailableBio =
                                    m == ContainerUnlockMethod.biometrics &&
                                        !_biometricAvailable;
                                return SelectOption(
                                  value: m,
                                  label: isUnavailableBio
                                      ? '${m.label} ${context.l10n.unavailableSuffixLabel}'
                                      : m.label,
                                  subtitle: m.subtitle,
                                );
                              })
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _unlockMethod = v;
                              if (v == ContainerUnlockMethod.password) {
                                _passwordCtrl.clear();
                                keyfiles.clear();
                              }
                            });
                          },
                        ),
                        if (widget.existingRecord != null &&
                            widget.existingRecord!.unlockMethod !=
                                ContainerUnlockMethod.password &&
                            _unlockMethod != ContainerUnlockMethod.password &&
                            !_changePassword) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: FilledButton.tonalIcon(
                              onPressed: () =>
                                  setState(() => _changePassword = true),
                              icon: const Icon(Icons.key_rounded, size: 18),
                              label: Text(context.l10n.updateSavedCredentialsButton),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: cs.surfaceContainerHighest,
                                foregroundColor: cs.primary,
                              ),
                            ),
                          ),
                        ],
                        if (_unlockMethod != ContainerUnlockMethod.password &&
                            (widget.existingRecord == null ||
                                widget.existingRecord!.unlockMethod ==
                                    ContainerUnlockMethod.password ||
                                _changePassword)) ...[
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: _passwordCtrl,
                                  obscureText: !_showPassword,
                                  autofillHints: null,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: cs.surfaceContainerHighest,
                                    labelText: context.l10n.containerPasswordOptionalLabel,
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        PasswordVisibilityToggle(
                                          obscured: !_showPassword,
                                          onToggle: () => setState(
                                              () => _showPassword = !_showPassword),
                                        ),
                                        if (widget.existingRecord != null &&
                                            widget.existingRecord!.unlockMethod !=
                                                ContainerUnlockMethod.password)
                                          IconButton(
                                            icon: const Icon(Icons.close_rounded,
                                                size: 20),
                                            tooltip: context.l10n.cancelUpdatingPasswordTooltip,
                                            onPressed: () => setState(() {
                                              _changePassword = false;
                                              _passwordCtrl.clear();
                                            }),
                                          ),
                                      ],
                                    ),
                                    hintText: context.l10n.passwordHintContainer,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    context.l10n.passwordKeystoreEncryptedHelperText,
                                    style: textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant, height: 1.3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!_isCryptomator && !_isGocryptfs && !_isCryfs && !_isBitlocker) ...[
                            KeyfilesPicker(
                              keyfiles: keyfiles,
                              picking: pickingKeyfiles,
                              onPick: pickKeyfiles,
                              onRemove: removeKeyfile,
                            ),
                          ],
                        ],
                        if (_unlockMethod == ContainerUnlockMethod.pattern) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: OutlinedButton(
                              onPressed: _setupPattern,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(_patternHash != null
                                  ? context.l10n.changePatternButton
                                  : context.l10n.setPatternButton),
                            ),
                          ),
                        ],
                        if (!_isCryptomator &&
                            !_isGocryptfs &&
                            !_isBitlocker) ...[
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(context.l10n.cacheDerivedKeyLabel,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                _isCryfs
                                    ? context.l10n.cryfsSkipScryptKdfSubtitle
                                    : context.l10n.reuseKeyMaterialKeystoreSubtitle,
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                            value: _cacheDerivedKey,
                            onChanged: (v) => setState(() => _cacheDerivedKey = v),
                          ),
                          if (!_isCryfs)
                            AdvancedParamsPanel(
                              cipherId: _cipherId,
                              hashId: _hashId,
                              subtitle:
                                  context.l10n.pinAlgorithmSkipAutoDetectSubtitle,
                              onCipherChanged: (val) =>
                                  setState(() => _cipherId = val),
                              onHashChanged: (val) =>
                                  setState(() => _hashId = val),
                            ),
                        ],
                      ],
                      if (widget.existingRecord != null) ...[
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: Icon(Icons.key_rounded, color: cs.primary),
                          title: Text(
                            context.l10n.changeContainerPasswordTitle,
                            style: textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          trailing: Icon(Icons.chevron_right_rounded,
                              color: cs.onSurfaceVariant),
                          onTap: () async {
                            final fmt = widget.existingRecord?.containerFormat;
                            if (fmt == 'luks1' || fmt == 'luks2') {
                              showAppSnackBar(
                                context,
                                message:
                                    context.l10n.luksPasswordChangeNotSupportedMessage,
                                tone: AppBannerTone.warning,
                              );
                            } else if (fmt == 'cryptomator') {
                              showAppSnackBar(
                                context,
                                message:
                                    context.l10n.cryptomatorPasswordChangeNotSupportedMessage,
                                tone: AppBannerTone.warning,
                              );
                            } else if (fmt == 'gocryptfs') {
                              showAppSnackBar(
                                context,
                                message:
                                    context.l10n.gocryptfsPasswordChangeNotSupportedMessage,
                                tone: AppBannerTone.warning,
                              );
                            } else if (fmt == 'cryfs') {
                              showAppSnackBar(
                                context,
                                message:
                                    context.l10n.cryfsPasswordChangeNotSupportedMessage,
                                tone: AppBannerTone.warning,
                              );
                            } else if (fmt == 'bitlocker') {
                              showAppSnackBar(
                                context,
                                message:
                                    context.l10n.bitlockerCredentialsChangeNotSupportedMessage,
                                tone: AppBannerTone.warning,
                              );
                            } else {
                              final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChangePasswordScreen(
                                      uri: widget.uri,
                                      initialCipherId:
                                          widget.existingRecord!.cipherId,
                                      initialHashId:
                                          widget.existingRecord!.hashId,
                                    ),
                                  ),
                                );
                              if (result is List<KeyfileRef>) {
                                setState(() {
                                  keyfiles.clear();
                                  keyfiles.addAll(result);
                                });
                              }
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  SectionHeader(context.l10n.systemIntegrationSectionHeader),
                  SectionCard(
                    children: [
                      OptionPickerTile<int>(
                        label: context.l10n.autoLockDurationLabel,
                        value: _autoCloseMins,
                        options: _autoCloseOptions.map((mins) {
                          final label = mins == 0
                              ? context.l10n.neverAutoLockOption
                              : context.l10n.nMinutes(mins);
                          return SelectOption(value: mins, label: label);
                        }).toList(),
                        onChanged: (v) => setState(() => _autoCloseMins = v),
                      ),
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        title: Text(context.l10n.androidFileProviderTitle,
                            style: textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            context.l10n.exposeContentToFilePickerSubtitle,
                            style: textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                        value: _documentProvider,
                        onChanged: (v) => setState(() => _documentProvider = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SectionHeader(context.l10n.thumbnailStorageSectionHeader),
                  SectionCard(
                    children: [
                      if (_loadingPassword)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else ...[
                        OptionPickerTile<ThumbnailCacheMode>(
                          label: context.l10n.cacheModeLabel,
                          value: _thumbnailCacheMode ?? ThumbnailCacheMode.appCache,
                          subtitle: _thumbnailCacheMode?.label ?? context.l10n.useGlobalDefaultSubtitle,
                          options: ThumbnailCacheMode.values.map((mode) {
                            return SelectOption(
                              value: mode,
                              label: mode.label,
                              subtitle: mode.description,
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => _thumbnailCacheMode = v),
                        ),
                        ThumbnailQualityTile(
                          label: context.l10n.thumbnailQualityLabel,
                          value: _thumbnailQuality ?? ThumbnailQuality.defaultQuality,
                          onChanged: (v) => setState(() => _thumbnailQuality = v),
                        ),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          title: Text(
                            context.l10n.clearThumbnailCacheTitle,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            context.l10n.removeCachedThumbnailsSubtitle,
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          trailing: _clearingCache
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.chevron_right_rounded,
                                  color: cs.onSurfaceVariant,
                                ),
                          onTap: _clearingCache ? null : _clearThumbnailCache,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomSaveBar(),
    );
  }

  Widget _buildBottomSaveBar() {
    final isModified = _isModified;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: !isModified
          ? const SizedBox(width: double.infinity, height: 0)
          : Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                border: Border(
                    top: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.3))),
              ),
              child: SafeArea(
                minimum:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_canSave) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 18, color: cs.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _needsPatternSetup
                                  ? context.l10n.patternSetupRequiredAboveBeforeSaving
                                  : context.l10n.passwordOrCacheDerivedKeyRequiredMessage,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    FilledButton(
                      onPressed: (_saving || !_canSave) ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: const StadiumBorder(),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(
                              context.l10n.saveConfigurationButton,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _PatternVerifySheet extends StatefulWidget {
  final String storedHash;
  const _PatternVerifySheet({required this.storedHash});
  @override
  State<_PatternVerifySheet> createState() => _PatternVerifySheetState();
}

class _PatternVerifySheetState extends State<_PatternVerifySheet> {
  String? _error;
  bool _showError = false;
  int _resetKey = 0;

  Future<void> _onPatternComplete(List<int> pattern) async {
    final ok = await verifyPattern(pattern, widget.storedHash);
    if (ok) {
      if (mounted) Navigator.pop(context, widget.storedHash);
    } else {
      setState(() {
        _error = context.l10n.incorrectPatternError;
        _showError = true;
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _showError = false;
            _error = null;
            _resetKey++;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AppBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.verifyPatternTitle,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          PatternLockView(
            key: ValueKey(_resetKey),
            onPatternComplete: _onPatternComplete,
            showError: _showError,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: textTheme.bodySmall?.copyWith(color: cs.error)),
          ],
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
        ],
      ),
    );
  }
}

class _RealPasswordGateDialog extends StatefulWidget {
  final String uri;
  final int cipherId;
  final int hashId;
  final bool documentProvider;
  final bool cacheDerivedKey;
  final String containerFormat;
  final List<Map<String, String>> initialKeyfiles;
  final String? initialPassword;
  const _RealPasswordGateDialog({
    required this.uri,
    required this.cipherId,
    required this.hashId,
    required this.documentProvider,
    required this.cacheDerivedKey,
    this.containerFormat = 'veracrypt',
    this.initialKeyfiles = const [],
    this.initialPassword,
  });
  @override
  State<_RealPasswordGateDialog> createState() => _RealPasswordGateDialogState();
}

class _RealPasswordGateDialogState extends State<_RealPasswordGateDialog>
    with KeyfilePickerMixin {
  final _pwCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();
  String? _error;
  bool _obscure = true;
  bool _loading = false;
  @override
  void onKeyfilePickError(String message) => setState(() => _error = message);
  bool get _isUsb => widget.uri.startsWith('usb:');
  String get _usbDeviceName => widget.uri.substring(4);
  bool get _isCryptomator => ContainerFormat.isCryptomatorWire(widget.containerFormat);
  bool get _isGocryptfs => ContainerFormat.isGocryptfsWire(widget.containerFormat);
  bool get _isCryfs => ContainerFormat.isCryfsWire(widget.containerFormat);
  bool get _isBitlocker => ContainerFormat.isBitlockerWire(widget.containerFormat);
  int? _activeVolId;
  late final void Function(int) _onUnlockStarted;

  @override
  void initState() {
    super.initState();
    if (widget.initialPassword != null && widget.initialPassword!.isNotEmpty) {
      _pwCtrl.text = widget.initialPassword!;
    }
    if (widget.initialKeyfiles.isNotEmpty) {
      keyfiles.addAll(widget.initialKeyfiles.map((k) => (uri: k['uri']!, displayName: k['name']!)));
    }
    _onUnlockStarted = (volId) {
      if (mounted) setState(() => _activeVolId = volId);
    };
    VaultExplorerApi.addUnlockStartedListener(_onUnlockStarted);
  }

  @override
  void dispose() {
    if (_loading && _activeVolId != null) {
      vaultExplorerApi.cancelUnlock(_activeVolId!);
    }
    VaultExplorerApi.removeUnlockStartedListener(_onUnlockStarted);
    _pwCtrl.dispose();
    _pimCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_pwCtrl.text.isEmpty && keyfiles.isEmpty) {
      setState(() => _error = context.l10n.passwordOrKeyfilesRequired);
      return;
    }
    setState(() { _loading = true; _error = null; });
    if (_isCryptomator || _isGocryptfs || _isCryfs) {
      try {
        final result = _isCryptomator
            ? await vaultExplorerApi.unlockCryptomatorVault(
                widget.uri,
                _pwCtrl.text,
                displayName: '',
                documentProvider: widget.documentProvider,
              )
            : _isGocryptfs
                ? await vaultExplorerApi.unlockGocryptfsVault(
                    widget.uri,
                    _pwCtrl.text,
                    displayName: '',
                    documentProvider: widget.documentProvider,
                  )
                : await vaultExplorerApi.unlockCryfsVault(
                    widget.uri,
                    _pwCtrl.text,
                    displayName: '',
                    documentProvider: widget.documentProvider,
                  );
        if (result == null) {
          if (mounted) setState(() { _loading = false; _error = context.l10n.incorrectPasswordError; });
          return;
        }
        await vaultExplorerApi.lockContainer(widget.uri);
        if (mounted) {
          Navigator.pop(context, (
            password: _pwCtrl.text,
            keyfiles: List<KeyfileRef>.from(keyfiles),
            cipherId: 255,
            hashId: 255,
          ));
        }
      } catch (e) {
        final isCancelled = e is PlatformException && e.code == 'CANCELLED';
        if (mounted && !isCancelled) {
          setState(() { _loading = false; _error = context.l10n.verificationFailedError; });
        }
      }
      return;
    }
    try {
      final pim = clampPim(_pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0);
      final keyfilePaths = keyfiles.map((k) => k.uri).toList();
      final result = _isUsb
          ? await vaultExplorerApi.unlockUsbContainer(
              _usbDeviceName,
              _pwCtrl.text,
              pim,
              displayName: '',
              documentProvider: widget.documentProvider,
              cipherId: widget.cipherId,
              hashId: widget.hashId,
              preservedKey: null,
              cacheDerivedKey: widget.cacheDerivedKey,
              keyfilePaths: keyfilePaths,
            )
          : await vaultExplorerApi.unlockContainer(
              widget.uri,
              _pwCtrl.text,
              pim,
              displayName: '',
              documentProvider: widget.documentProvider,
              cipherId: widget.cipherId,
              hashId: widget.hashId,
              preservedKey: null,
              cacheDerivedKey: widget.cacheDerivedKey,
              keyfilePaths: keyfilePaths,
            );
      if (result == null) {
        if (mounted) setState(() { _loading = false; _error = context.l10n.incorrectCredentialsError; });
        return;
      }
      await vaultExplorerApi.lockContainer(_isUsb ? _usbDeviceName : widget.uri);
      if (mounted) {
        Navigator.pop(context, (
          password: _pwCtrl.text,
          keyfiles: List<KeyfileRef>.from(keyfiles),
          cipherId: result.matchedCipherId,
          hashId: result.matchedHashId,
        ));
      }
    } catch (e) {
      final isCancelled = e is PlatformException && e.code == 'CANCELLED';
      if (mounted && !isCancelled) {
        setState(() { _loading = false; _error = context.l10n.verificationFailedError; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(context.l10n.verifyCredentialsTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pwCtrl,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                labelText: context.l10n.containerPasswordOptionalLabel,
                suffixIcon: PasswordVisibilityToggle(
                  obscured: _obscure,
                  onToggle: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _verify(),
            ),
            if (!_isCryptomator && !_isGocryptfs && !_isCryfs && !_isBitlocker) ...[
              const SizedBox(height: 16),
              KeyfilesPicker(
                keyfiles: keyfiles,
                picking: pickingKeyfiles,
                onPick: pickKeyfiles,
                onRemove: removeKeyfile,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pimCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  labelText: context.l10n.pimOptionalLabel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (_loading && _activeVolId != null) {
              vaultExplorerApi.cancelUnlock(_activeVolId!);
            }
            Navigator.pop(context);
          },
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _verify,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(context.l10n.verifyButton),
        ),
      ],
    );
  }
}

class _DisplayNameDialog extends StatefulWidget {
  final String initialText;
  const _DisplayNameDialog({required this.initialText});
  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.displayNameTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: context.l10n.containerNameHint),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}