import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_setup_sheet.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
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

class _ContainerConfigScreenState extends State<ContainerConfigScreen> {
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
  void initState() {
    super.initState();
    final rec = widget.existingRecord;
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
    _settingsLocked = rec != null;
    _initAsync();
  }

  bool _clearingCache = false;

  Future<void> _clearThumbnailCache() async {
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
            message: 'App cache cleared. Unlock container to clear inside cache.',
            tone: AppBannerTone.warning,
          );
        } else if (appCacheCleared && containerCacheCleared) {
          showAppSnackBar(
            context,
            message: 'All thumbnail caches cleared successfully.',
            tone: AppBannerTone.success,
          );
        } else if (appCacheCleared) {
          showAppSnackBar(
            context,
            message: 'App cache cleared, but failed to clear inside container.',
            tone: AppBannerTone.warning,
          );
        } else {
          showAppSnackBar(
            context,
            message: 'Failed to clear thumbnail caches.',
            tone: AppBannerTone.error,
          );
        }
      }
    }
  }

  Future<void> _initAsync() async {
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
    return false;
  }

  bool get _wasPasswordless =>
      widget.existingRecord == null ||
      widget.existingRecord!.unlockMethod == ContainerUnlockMethod.password;

  bool get _unlockMethodNeedsPassword =>
      _unlockMethod != ContainerUnlockMethod.password;

  bool get _needsPasswordSetup => false;

  bool get _needsPatternSetup =>
      _unlockMethod == ContainerUnlockMethod.pattern && _patternHash == null;

  bool get _canSave => !_needsPasswordSetup && !_needsPatternSetup;

  Future<void> _save() async {
    if (_needsPatternSetup) {
      showAppSnackBar(
        context,
        message: 'Set up a pattern before saving.',
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
          localizedReason: 'Authenticate to modify settings',
          options: const AuthenticationOptions(stickyAuth: true),
        );
        if (ok && mounted) {
          setState(() => _settingsLocked = false);
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
        setState(() => _settingsLocked = false);
      }
    } else if (record.unlockMethod == ContainerUnlockMethod.rememberPassword) {
      final savedPassword =
          await ContainerRepository.instance.getPassword(widget.uri);
      if (savedPassword == null || savedPassword.isEmpty) {
        if (mounted) setState(() => _settingsLocked = false);
        return;
      }
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => _PasswordVerifyDialog(uri: widget.uri),
      );
      if (ok == true && mounted) {
        setState(() => _settingsLocked = false);
      }
    } else if (record.unlockMethod == ContainerUnlockMethod.password) {
      final verified = await showDialog<({String password, int cipherId, int hashId})>(
        context: context,
        builder: (context) => _RealPasswordGateDialog(
          uri: widget.uri,
          cipherId: record.cipherId,
          hashId: record.hashId,
          documentProvider: _documentProvider,
          cacheDerivedKey: _cacheDerivedKey,
          containerFormat: record.containerFormat,
        ),
      );
      if (verified != null && mounted) {
        setState(() {
          _settingsLocked = false;
          _passwordCtrl.text = verified.password;
          _cipherId = verified.cipherId;
          _hashId = verified.hashId;
        });
      }
    }
  }

  Widget _buildSectionGroup({required List<Widget> children}) {
    if (children.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(children.length, (index) {
        final isFirst = index == 0;
        final isLast = index == children.length - 1;
        final isOnly = children.length == 1;

        BorderRadius radius;
        if (isOnly) {
          radius = BorderRadius.circular(20);
        } else if (isFirst) {
          radius = const BorderRadius.vertical(
            top: Radius.circular(20),
            bottom: Radius.circular(4),
          );
        } else if (isLast) {
          radius = const BorderRadius.vertical(
            top: Radius.circular(4),
            bottom: Radius.circular(20),
          );
        } else {
          radius = BorderRadius.circular(4);
        }

        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 2.0),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: ListTileTheme(
              tileColor: Colors.transparent,
              child: children[index],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSectionHeader(String title) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Text(
        title,
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: cs.primary,
          letterSpacing: -0.1,
        ),
      ),
    );
  }


  Widget _buildSelectTile<T>({
    required String label,
    required T value,
    required List<_SelectOption<T>> options,
    required ValueChanged<T> onChanged,
    String? subtitle,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final currentOption = options.firstWhere(
      (opt) => opt.value == value,
      orElse: () => options.first,
    );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      title: Text(
        label,
        style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              currentOption.label,
              style: textTheme.labelMedium?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (dialogContext) {
            final dialogTheme = Theme.of(dialogContext);
            final mediaQuery = MediaQuery.of(dialogContext);
            final isLandscape =
                mediaQuery.orientation == Orientation.landscape;

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  maxHeight: isLandscape
                      ? mediaQuery.size.height * 0.85
                      : mediaQuery.size.height * 0.75,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          label,
                          style: dialogTheme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: options.map((opt) {
                              final isSelected = opt.value == value;
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? cs.primaryContainer
                                          .withValues(alpha: 0.5)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: RadioListTile<T>(
                                  activeColor: cs.primary,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 2,
                                  ),
                                  value: opt.value,
                                  groupValue: value,
                                  title: Text(
                                    opt.label,
                                    style: dialogTheme.textTheme.bodyMedium
                                        ?.copyWith(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isSelected ? cs.primary : null,
                                    ),
                                  ),
                                  subtitle: opt.subtitle != null
                                      ? Text(
                                          opt.subtitle!,
                                          style: dialogTheme
                                              .textTheme.bodySmall
                                              ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        )
                                      : null,
                                  onChanged: (T? newValue) {
                                    if (newValue != null) {
                                      Navigator.of(dialogContext).pop();
                                      onChanged(newValue);
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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
              widget.uri.startsWith('usb:') ? 'USB Vault Settings' : 'Vault Settings',
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
                  // ── General ─────────────────────────────────────────────
                  _buildSectionHeader('General'),
                  _buildSectionGroup(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: TextField(
                          controller: _labelCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Display Name',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Security & Credentials ──────────────────────────────
                  _buildSectionHeader('Security & Credentials'),
                  _buildSectionGroup(
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
                              color: cs.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Security Options Locked',
                              style: textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Authenticate with original container credentials to modify security settings.',
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
                              label: const Text('Unlock Settings'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    _buildSelectTile<ContainerUnlockMethod>(
                      label: 'Unlock Credentials',
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
                            return _SelectOption(
                              value: m,
                              label: isUnavailableBio
                                  ? '${m.label} (Unavailable)'
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
                          }
                        });
                      },
                    ),
                    if (widget.existingRecord != null &&
                        widget.existingRecord!.unlockMethod !=
                            ContainerUnlockMethod.password &&
                        _unlockMethod != ContainerUnlockMethod.password) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        value: _changePassword,
                        title: Text('Update saved password',
                            style: textTheme.bodyMedium),
                        onChanged: (v) => setState(() {
                          _changePassword = v ?? false;
                          if (!v!) _passwordCtrl.clear();
                        }),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                    if (_unlockMethod != ContainerUnlockMethod.password &&
                        (widget.existingRecord == null ||
                            widget.existingRecord!.unlockMethod ==
                                ContainerUnlockMethod.password ||
                            _changePassword)) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: TextField(
                          controller: _passwordCtrl,
                          obscureText: !_showPassword,
                          autofillHints: null,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText:
                                'Container password (optional for keyfile-only)',
                            suffixIcon: PasswordVisibilityToggle(
                              obscured: !_showPassword,
                              onToggle: () => setState(
                                  () => _showPassword = !_showPassword),
                            ),
                            hintText: 'Enter container password',
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Password is encrypted using Android Keystore. Leave blank if using keyfiles only.',
                          style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant, height: 1.3),
                        ),
                      ),
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
                              ? 'Change Pattern'
                              : 'Set Pattern'),
                        ),
                      ),
                    ],
                    if (!_isCryptomator &&
                        !_isGocryptfs &&
                        !_isCryfs &&
                        !_isBitlocker) ...[
                   
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        title: Text('Cache Derived Key',
                            style: textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        subtitle: Text('Reuse key material in Android Keystore',
                            style: textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                        value: _cacheDerivedKey,
                        onChanged: (v) => setState(() => _cacheDerivedKey = v),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: AdvancedParamsPanel(
                          cipherId: _cipherId,
                          hashId: _hashId,
                          subtitle:
                              'Pin algorithm to skip auto-detection on unlock.',
                          onCipherChanged: (val) =>
                              setState(() => _cipherId = val),
                          onHashChanged: (val) =>
                              setState(() => _hashId = val),
                        ),
                      ),
                    ],
                    if (widget.existingRecord != null) ...[
                  
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: OutlinedButton(
                          onPressed: () {
                            final fmt = widget.existingRecord?.containerFormat;
                            if (fmt == 'luks1' || fmt == 'luks2') {
                              showAppSnackBar(
                                context,
                                message:
                                    'LUKS password changing is not supported in-app. Use cryptsetup on Linux.',
                                tone: AppBannerTone.warning,
                              );
                            } else if (fmt == 'cryptomator') {
                              showAppSnackBar(
                                context,
                                message:
                                    'Cryptomator vault passwords cannot be changed in-app.',
                                tone: AppBannerTone.warning,
                              );
                            } else if (fmt == 'gocryptfs') {
                              showAppSnackBar(
                                context,
                                message:
                                    'Gocryptfs vault passwords cannot be changed in-app.',
                                tone: AppBannerTone.warning,
                              );
                            } else if (fmt == 'cryfs') {
                              showAppSnackBar(
                                context,
                                message:
                                    'CryFS vault passwords cannot be changed in-app.',
                                tone: AppBannerTone.warning,
                              );
                            } else if (fmt == 'bitlocker') {
                              showAppSnackBar(
                                context,
                                message:
                                    'BitLocker credentials cannot be changed in-app. Use "Manage BitLocker" on Windows.',
                                tone: AppBannerTone.warning,
                              );
                            } else {
                              Navigator.push(
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
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            foregroundColor: cs.error,
                          ),
                          child: const Text('Change Container Password'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // ── System & Integration ────────────────────────────────
              _buildSectionHeader('System & Integration'),
              _buildSectionGroup(
                children: [
                  _buildSelectTile<int>(
                    label: 'Auto-Lock Duration',
                    value: _autoCloseMins,
                    subtitle: _autoCloseMins == 0
                        ? 'Container will not auto-lock'
                        : 'Locks after $_autoCloseMins minute${_autoCloseMins == 1 ? '' : 's'} of inactivity',
                    options: _autoCloseOptions.map((mins) {
                      final label = mins == 0
                          ? 'Never'
                          : mins == 1
                              ? '1 minute'
                              : '$mins minutes';
                      return _SelectOption(value: mins, label: label);
                    }).toList(),
                    onChanged: (v) => setState(() => _autoCloseMins = v),
                  ),
                 
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    title: Text('Android File Provider',
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        'Expose content to System File Picker when unlocked',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    value: _documentProvider,
                    onChanged: (v) => setState(() => _documentProvider = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Thumbnail Storage ──────────────────────────────────
              _buildSectionHeader('Thumbnail Storage'),
              _buildSectionGroup(
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
                    _buildSelectTile<ThumbnailCacheMode>(
                      label: 'Cache Mode',
                      value: _thumbnailCacheMode ?? ThumbnailCacheMode.appCache,
                      subtitle: _thumbnailCacheMode?.description ??
                          'Uses default global app settings.',
                      options: ThumbnailCacheMode.values.map((mode) {
                        return _SelectOption(
                          value: mode,
                          label: mode.label,
                          subtitle: mode.description,
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _thumbnailCacheMode = v),
                    ),
                 
                    _buildSelectTile<ThumbnailQuality>(
                      label: 'Thumbnail Quality',
                      value: _thumbnailQuality ?? ThumbnailQuality.medium,
                      options: ThumbnailQuality.values.map((q) {
                        return _SelectOption(
                          value: q,
                          label: q.label,
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _thumbnailQuality = v),
                    ),
                 
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        onPressed: _clearingCache ? null : _clearThumbnailCache,
                        icon: _clearingCache
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.delete_sweep_rounded, size: 18),
                        label: const Text('Clear Thumbnail Cache'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          foregroundColor: cs.primary,
                        ),
                      ),
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
                                  ? 'Set up a pattern above before saving.'
                                  : 'Configure required security settings above before saving.',
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
                          : const Text(
                              'Save Configuration',
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

  void _onPatternComplete(List<int> pattern) {
    final hash = hashPattern(pattern);
    if (hash == widget.storedHash) {
      Navigator.pop(context, hash);
    } else {
      setState(() {
        _error = 'Incorrect pattern';
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
          Text('Verify Pattern',
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
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _PasswordVerifyDialog extends StatefulWidget {
  final String uri;
  const _PasswordVerifyDialog({required this.uri});

  @override
  State<_PasswordVerifyDialog> createState() => _PasswordVerifyDialogState();
}

class _PasswordVerifyDialogState extends State<_PasswordVerifyDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final saved = await ContainerRepository.instance.getPassword(widget.uri);
    if (saved == _ctrl.text) {
      if (mounted) Navigator.pop(context, true);
    } else {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Incorrect password';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Current password',
              suffixIcon: PasswordVisibilityToggle(
                obscured: _obscure,
                onToggle: () => setState(() => _obscure = !_obscure),
              ),
              errorText: _error,
            ),
            onSubmitted: (_) => _verify(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _verify,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Verify'),
        ),
      ],
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

  const _RealPasswordGateDialog({
    required this.uri,
    required this.cipherId,
    required this.hashId,
    required this.documentProvider,
    required this.cacheDerivedKey,
    this.containerFormat = 'veracrypt',
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
      setState(() => _error = 'Password or keyfiles required');
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
          if (mounted) setState(() { _loading = false; _error = 'Incorrect password'; });
          return;
        }
        await vaultExplorerApi.lockContainer(widget.uri);
        if (mounted) {
          Navigator.pop(context, (
            password: _pwCtrl.text,
            cipherId: 255,
            hashId: 255,
          ));
        }
      } catch (e) {
        final isCancelled = e is PlatformException && e.code == 'CANCELLED';
        if (mounted && !isCancelled) {
          setState(() { _loading = false; _error = 'Verification failed'; });
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
        if (mounted) setState(() { _loading = false; _error = 'Incorrect credentials'; });
        return;
      }
      await vaultExplorerApi.lockContainer(_isUsb ? _usbDeviceName : widget.uri);
      if (mounted) {
        Navigator.pop(context, (
          password: _pwCtrl.text,
          cipherId: result.matchedCipherId,
          hashId: result.matchedHashId,
        ));
      }
    } catch (e) {
      final isCancelled = e is PlatformException && e.code == 'CANCELLED';
      if (mounted && !isCancelled) {
        setState(() { _loading = false; _error = 'Verification failed'; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Verify Credentials'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'No credentials are saved on this dashboard. Enter current password and keyfiles to prove ownership.',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _pwCtrl,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Container password (optional for keyfile-only)',
                suffixIcon: PasswordVisibilityToggle(
                  obscured: _obscure,
                  onToggle: () => setState(() => _obscure = !_obscure),
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
                decoration: const InputDecoration(
                  labelText: 'PIM (optional)',
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
          child: const Text('Cancel'),
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
              : const Text('Verify'),
        ),
      ],
    );
  }
}

class _SelectOption<T> {
  final T value;
  final String label;
  final String? subtitle;

  const _SelectOption({
    required this.value,
    required this.label,
    this.subtitle,
  });
}