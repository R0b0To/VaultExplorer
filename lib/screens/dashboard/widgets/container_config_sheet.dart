import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../../../models/mounted_container.dart';
import '../../../models/thumbnail_cache_mode.dart';
import '../../../models/thumbnail_quality.dart';
import '../../../services/app_settings_service.dart';
import '../../../services/vaultexplorer_api.dart';
import '../../../theme.dart';
import '../../../widgets/common_widgets.dart';
import '../../lock/pattern_setup_sheet.dart';
import '../../lock/pattern_lock_view.dart';
import '../../../utils/validation_utils.dart';
import 'change_password_screen.dart';
import '../../../services/thumbnail_cache_service.dart';

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
  int _cipherId = 255; // Auto
  int _hashId = 255; // Auto
  String? _patternHash;
  bool _biometricAvailable = false;
  late bool _settingsLocked;
  bool _changePassword = false;

  bool _saving = false;
  bool _loadingPassword = true;

  // --- Initial state trackers (used to determine if edits occurred) ---
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
    _initialDocumentProvider = rec?.documentProvider ?? false;
    _initialCipherId = rec?.cipherId ?? 255;
    _initialHashId = rec?.hashId ?? 255;
    _initialCacheDerivedKey = rec?.cacheDerivedKey;

    _labelCtrl = TextEditingController(text: _initialLabel);
    _passwordCtrl = TextEditingController();

    // Trigger UI updates when typing so the save bar can appear/disappear dynamically
    _labelCtrl.addListener(() => setState(() {}));

    _unlockMethod = _initialUnlockMethod;
    _showPassword = false;
    _autoCloseMins = _initialAutoCloseMins;
    _documentProvider = _initialDocumentProvider;
    _thumbnailCacheMode = rec?.thumbnailCacheMode;
    _thumbnailQuality = rec?.thumbnailQuality;
    _cacheDerivedKey = rec?.cacheDerivedKey ?? widget.appSettings?.defaultDerivedKeyCacheEnabled ?? false;
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
      // 1. Clear local App Cache (always runs as it is stored in device application storage)
      await ThumbnailCacheService.clearAppCacheByUri(widget.uri);
      appCacheCleared = true;

      // 2. Clear inside-container cache
      await ThumbnailCacheService.clearInContainerCacheByUri(widget.uri);
      containerCacheCleared = true;
    } on PlatformException catch (e) {
      if (e.code == 'NOT_MOUNTED') {
        isLocked = true;
      }
    } catch (_) {
      // Handle other unexpected issues silently or via flags
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

          // If appSettings wasn't available synchronously in initState (so
          // _cacheDerivedKey fell back to `false`), apply the real default now
          // — but only for brand-new containers; an existing record's saved
          // value always wins.
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

  // Check if any fields differ from their initial state
  bool get _isModified {
    // If it's completely unrecorded yet (new container), treat it as modified
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
      pendingPassword: shouldSavePassword
          ? _passwordCtrl.text
          : null,
      pendingPatternHash: _unlockMethod == ContainerUnlockMethod.pattern
          ? _patternHash
          : null,
      cipherId: _cipherId,
      hashId: _hashId,
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.uri.startsWith('usb:') ? 'USB Vault Settings' : 'File Vault Settings',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // SECTION 1: General Info Card
              AppCard(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionHeader(title: 'General Settings', icon: Icons.badge_outlined),
                  TextField(
                    controller: _labelCtrl,
                    decoration: InputDecoration(
                      labelText: 'Display Name',
                      prefixIcon: Icon(Icons.label_outline_rounded, size: 20, color: cs.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // SECTION 2: Security settings Card
              AppCard(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionHeader(title: 'Security Settings', icon: Icons.shield_outlined),
                  if (_settingsLocked) ...[
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: cs.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer.withValues(alpha: 0.4),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.lock_outline_rounded, size: 32, color: cs.primary),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Security options locked',
                              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Confirm original credentials to unlock modification panels.',
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _authenticateSettings,
                              icon: Icon(
                                widget.existingRecord?.unlockMethod.icon ?? Icons.lock_open_rounded,
                                size: 16,
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              label: const Text('Unlock credentials'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    DropdownButtonFormField<ContainerUnlockMethod>(
                      initialValue: _unlockMethod,
                      decoration: InputDecoration(
                        labelText: 'Unlock Credentials',
                        prefixIcon: Icon(Icons.vpn_key_outlined, size: 20, color: cs.primary),
                      ),
                      items: ContainerUnlockMethod.values
                          .where((m) =>
                              m != ContainerUnlockMethod.biometrics ||
                              _biometricAvailable ||
                              _unlockMethod == m)
                          .map((m) {
                            final isUnavailableBio = m == ContainerUnlockMethod.biometrics && !_biometricAvailable;
                            return DropdownMenuItem(
                              value: m,
                              child: Row(children: [
                                Icon(m.icon, size: 18, color: cs.onSurfaceVariant),
                                const SizedBox(width: 10),
                                Text(isUnavailableBio
                                    ? '${m.label} (Unavailable)'
                                    : m.label),
                              ]),
                            );
                          })
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _unlockMethod = v;
                          if (v == ContainerUnlockMethod.password) {
                            _passwordCtrl.clear();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        _unlockMethod.subtitle,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                      ),
                    ),

                    if (widget.existingRecord != null &&
                        widget.existingRecord!.unlockMethod != ContainerUnlockMethod.password &&
                        _unlockMethod != ContainerUnlockMethod.password) ...[
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: _changePassword,
                        title: Text('Update saved password', style: textTheme.bodyMedium),
                        onChanged: (v) => setState(() {
                          _changePassword = v ?? false;
                          if (!v!) _passwordCtrl.clear();
                        }),
                        controlAffinity: ListTileControlAffinity.leading,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        tileColor: cs.surfaceContainer,
                      ),
                    ],

                    if (_unlockMethod != ContainerUnlockMethod.password &&
                        (widget.existingRecord == null ||
                         widget.existingRecord!.unlockMethod == ContainerUnlockMethod.password ||
                         _changePassword)) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: !_showPassword,
                        autofillHints: null,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Container password (leave blank if keyfile-only)',
                          prefixIcon: Icon(Icons.lock_rounded, size: 20, color: cs.primary),
                          suffixIcon: PasswordVisibilityToggle(
                            obscured: !_showPassword,
                            onToggle: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                          hintText: 'Enter container password',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.security_rounded, size: 16, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Password is encrypted using an Android Keystore hardware-bound key. For keyfile-only volumes, leave this field completely empty.',
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (_unlockMethod == ContainerUnlockMethod.pattern) ...[
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _setupPattern,
                        icon: Icon(
                          _patternHash != null
                              ? Icons.check_circle_rounded
                              : Icons.pattern_rounded,
                          size: 18,
                          color: _patternHash != null ? cs.primary : null,
                        ),
                        label: Text(_patternHash != null
                            ? 'Change Pattern'
                            : 'Set Pattern'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: Text('Cache Derived Key', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                      subtitle: Text('Reuse key material in Android Keystore securely for quick checks.', style: textTheme.bodySmall),
                      value: _cacheDerivedKey,
                      onChanged: (v) => setState(() => _cacheDerivedKey = v),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      tileColor: cs.surfaceContainer,
                    ),
                    const SizedBox(height: 16),
                    AdvancedParamsPanel(
                      cipherId: _cipherId,
                      hashId: _hashId,
                      subtitle: 'Pin the algorithm to skip auto-detection on unlock.',
                      onCipherChanged: (val) => setState(() => _cipherId = val),
                      onHashChanged: (val) => setState(() => _hashId = val),
                    ),
                    if (widget.existingRecord != null) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          if (widget.existingRecord?.containerFormat == 'luks1' ||
                              widget.existingRecord?.containerFormat == 'luks2') {
                            showAppSnackBar(
                              context,
                              message: 'LUKS password changing is not supported in-app. Use cryptsetup on Linux.',
                              tone: AppBannerTone.warning,
                            );
                          } else {
                            Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChangePasswordScreen(
            uri: widget.uri,
            initialCipherId: widget.existingRecord!.cipherId,
            initialHashId: widget.existingRecord!.hashId,
          ),
        ),
      );
    }
  },
  icon: const Icon(Icons.password_rounded),
                        label: const Text('Change Container Password'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          foregroundColor: cs.error,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // SECTION 3: System Settings Card
              AppCard(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionHeader(title: 'System Settings', icon: Icons.tune_rounded),
                  DropdownButtonFormField<int>(
                    initialValue: _autoCloseMins,
                    decoration: InputDecoration(
                      labelText: 'Auto-Lock duration',
                      prefixIcon: Icon(Icons.timer_rounded, size: 20, color: cs.primary),
                    ),
                    items: _autoCloseOptions.map((mins) {
                      final label = mins == 0
                          ? 'Never'
                          : mins == 1
                              ? '1 minute'
                              : '$mins minutes';
                      return DropdownMenuItem(value: mins, child: Text(label));
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _autoCloseMins = v);
                    },
                  ),
                  const SizedBox(height: 16),

                  SwitchListTile(
                    title: Text('Android integration', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text('Expose content to System File Picker when unlocked.', style: textTheme.bodySmall),
                    value: _documentProvider,
                    onChanged: (v) => setState(() => _documentProvider = v),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: cs.surfaceContainer,
                  ),
                  const SizedBox(height: 16),

                  _SectionHeader(title: 'Thumbnail Caching', icon: Icons.cached_rounded),
                  if (_loadingPassword)
                    const Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                  else
                    DropdownButtonFormField<ThumbnailCacheMode?>(
                      initialValue: _thumbnailCacheMode,
                      decoration: InputDecoration(
                        labelText: 'Cache Mode',
                        prefixIcon: Icon(Icons.cached_rounded, size: 20, color: cs.primary),
                      ),
                      items: ThumbnailCacheMode.values
                          .map((mode) => DropdownMenuItem<ThumbnailCacheMode?>(
                                value: mode,
                                child: Text(mode.label),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _thumbnailCacheMode = v),
                    ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _thumbnailCacheMode?.description ??
                          'Uses the default setting configured globally in App Settings.',
                      style: textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                    ),
                  ),
                 const SizedBox(height: 16),
                  if (!_loadingPassword) ...[
                    DropdownButtonFormField<ThumbnailQuality?>(
                      initialValue: _thumbnailQuality,
                      decoration: InputDecoration(
                        labelText: 'Thumbnail Quality',
                        prefixIcon: Icon(Icons.high_quality_rounded, size: 20, color: cs.primary),
                      ),
                      items: ThumbnailQuality.values
                          .map((q) => DropdownMenuItem<ThumbnailQuality?>(
                                value: q,
                                child: Text(q.label),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _thumbnailQuality = v),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _clearingCache ? null : _clearThumbnailCache,
                      icon: _clearingCache
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_sweep_rounded),
                      label: const Text('Clear Thumbnail Cache'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        foregroundColor: cs.error,
                      ),
                    ),
                  ],
                    
                ],
              ),
            ],
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
                border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha:0.5))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                minimum: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_canSave) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 20, color: cs.error),
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
                      const SizedBox(height: 12),
                    ],
                    FilledButton(
                      onPressed: (_saving || !_canSave) ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: const StadiumBorder(),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Text(
                              'Save configurations',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ── Private Header Component ──────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Verification Sheets/Dialogs ──────────────────────────────────────────────

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
          Row(children: [
            Icon(Icons.pattern_rounded, size: AppIconSize.standard, color: cs.primary),
            const SizedBox(width: 10),
            Text('Verify Pattern',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ]),
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
  const _RealPasswordGateDialog({
    required this.uri,
    required this.cipherId,
    required this.hashId,
    required this.documentProvider,
    required this.cacheDerivedKey,
  });

  @override
  State<_RealPasswordGateDialog> createState() => _RealPasswordGateDialogState();
}

class _RealPasswordGateDialogState extends State<_RealPasswordGateDialog> {
  final _pwCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();
  String? _error;
  bool _obscure = true;
  bool _loading = false;
  final List<KeyfileRef> _keyfiles = [];
  bool _pickingKeyfiles = false;

  bool get _isUsb => widget.uri.startsWith('usb:');
  String get _usbDeviceName => widget.uri.substring(4);

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

  Future<void> _pickKeyfiles() async {
    setState(() => _pickingKeyfiles = true);
    try {
      final picked = await vaultExplorerApi.pickKeyfiles();
      if (!mounted) return;
      setState(() {
        for (final k in picked) {
          if (!_keyfiles.any((existing) => existing.uri == k.uri)) {
            _keyfiles.add(k);
          }
        }
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Could not pick keyfiles');
    } finally {
      if (mounted) setState(() => _pickingKeyfiles = false);
    }
  }

  void _removeKeyfile(KeyfileRef keyfile) {
    setState(() => _keyfiles.removeWhere((k) => k.uri == keyfile.uri));
  }

  Future<void> _verify() async {
    if (_pwCtrl.text.isEmpty && _keyfiles.isEmpty) {
      setState(() => _error = 'Password or keyfiles required');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final pim = clampPim(_pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0);
      final keyfilePaths = _keyfiles.map((k) => k.uri).toList();

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
      title: Row(
        children: [
          Icon(Icons.lock_person_outlined, color: cs.primary),
          const SizedBox(width: 12),
          const Text('Verify Credentials'),
        ],
      ),
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
                prefixIcon: Icon(Icons.key_outlined, size: 20, color: cs.primary),
                suffixIcon: PasswordVisibilityToggle(
                  obscured: _obscure,
                  onToggle: () => setState(() => _obscure = !_obscure),
                ),
                filled: true,
                fillColor: cs.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
              ),
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 16),

            KeyfilesPicker(
              keyfiles: _keyfiles,
              picking: _pickingKeyfiles,
              onPick: _pickKeyfiles,
              onRemove: _removeKeyfile,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _pimCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'PIM (optional)',
                prefixIcon: Icon(Icons.tune_rounded, size: 20, color: cs.primary),
                filled: true,
                fillColor: cs.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
              ),
            ),
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