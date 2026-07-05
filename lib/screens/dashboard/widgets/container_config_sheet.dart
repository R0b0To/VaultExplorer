import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../../models/thumbnail_cache_mode.dart';
import '../../../services/app_settings_service.dart';
import '../../../services/vaultexplorer_api.dart';
import '../../../theme.dart';
import '../../../widgets/common_widgets.dart';
import '../../lock/pattern_setup_sheet.dart';
import '../../lock/pattern_lock_view.dart';
import '../../../utils/validation_utils.dart';

class ContainerConfigSheet extends StatefulWidget {
  final String uri;
  final String currentLabel;
  final ContainerRecord? existingRecord;
  final void Function(ContainerRecord record) onSaved;
  final VoidCallback? onForget;

  /// FIX: Accept the already-loaded [AppSettings] from [VaultDashboard]
  ///      instead of loading it again inside this sheet on every open.
  ///      Falls back to a fresh load only when null (e.g. standalone usage).
  final AppSettings? appSettings;

  const ContainerConfigSheet({
    Key? key,
    required this.uri,
    required this.currentLabel,
    this.existingRecord,
    required this.onSaved,
    this.onForget,
    this.appSettings,
  }) : super(key: key);

  @override
  State<ContainerConfigSheet> createState() => _ContainerConfigSheetState();
}

class _ContainerConfigSheetState extends State<ContainerConfigSheet> {
  late TextEditingController _labelCtrl;
  late TextEditingController _passwordCtrl;
  late ContainerUnlockMethod _unlockMethod;
  late bool _showPassword;
  late int  _autoCloseMins;
  late bool _documentProvider;
  ThumbnailCacheMode? _thumbnailCacheMode;
  bool _cacheDerivedKey = false;
  String? _patternHash;   // stored pattern hash (from Keystore or newly set)
  bool _biometricAvailable = false;
  late bool _settingsLocked;
  bool _changePassword = false;

  bool _saving          = false;
  bool _loadingPassword = true;

  static const _autoCloseOptions = [0, 1, 2, 5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    final rec         = widget.existingRecord;
    _labelCtrl        = TextEditingController(
        text: rec?.label.isNotEmpty == true ? rec!.label : widget.currentLabel);
    _passwordCtrl     = TextEditingController();
    _unlockMethod     = rec?.unlockMethod ?? ContainerUnlockMethod.password;
    _showPassword     = false;
    _autoCloseMins    = rec?.autoCloseMins ?? 0;
    _documentProvider = rec?.documentProvider ?? false;
    _thumbnailCacheMode = rec?.thumbnailCacheMode;
    _cacheDerivedKey = rec?.cacheDerivedKey ?? widget.appSettings?.defaultDerivedKeyCacheEnabled ?? false;
    _settingsLocked   = rec != null;
    _initAsync();
  }

  /// FIX: Uses the pre-loaded [AppSettings] when available; only falls back
  ///      to an async load when the sheet is opened without one (rare).
  Future<void> _initAsync() async {
    // 0. Check biometric capability
    try {
      final localAuth = LocalAuthentication();
      _biometricAvailable = await localAuth.canCheckBiometrics &&
          await localAuth.isDeviceSupported();
    } catch (_) {}

    // 1. Resolve thumbnail cache mode from app settings
    try {
      final settings = widget.appSettings ?? await AppSettingsService.loadSettings();
      if (mounted) {
        setState(() {
          _thumbnailCacheMode ??= settings.defaultThumbnailCacheMode;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _thumbnailCacheMode ??= ThumbnailCacheMode.appCache;
        });
      }
    }

    // 2. Load stored pattern hash if applicable
    if (_unlockMethod == ContainerUnlockMethod.pattern) {
      _patternHash = await ContainerRepository.instance.getPatternHash(widget.uri);
    }

    if (mounted) setState(() => _loadingPassword = false);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final label = _labelCtrl.text.trim().isEmpty
        ? widget.currentLabel
        : _labelCtrl.text.trim();

    final wasNone = widget.existingRecord == null ||
        widget.existingRecord!.unlockMethod == ContainerUnlockMethod.password;
    final needsPassword = _unlockMethod != ContainerUnlockMethod.password;
    final shouldSavePassword = needsPassword && (wasNone || _changePassword);

    final record = ContainerRecord(
  uri: widget.uri,
  label: label,
  rememberPassword: needsPassword,
  unlockMethod: _unlockMethod,
  autoCloseMins: _autoCloseMins,
  documentProvider: _documentProvider,
  thumbnailCacheMode: _thumbnailCacheMode,
  cacheDerivedKey: _cacheDerivedKey,
  pendingPassword: shouldSavePassword && _passwordCtrl.text.isNotEmpty
      ? _passwordCtrl.text
      : null,
  pendingPatternHash: _unlockMethod == ContainerUnlockMethod.pattern
      ? _patternHash
      : null,
  cipherId: widget.existingRecord?.cipherId ?? 255,
  hashId: widget.existingRecord?.hashId ?? 255,
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
      final hash = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _PatternVerifySheet(
          storedHash: _patternHash ?? '',
        ),
      );
      if (hash != null && mounted) {
        setState(() => _settingsLocked = false);
      }
    } else if (record.unlockMethod == ContainerUnlockMethod.rememberPassword) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => _PasswordVerifyDialog(uri: widget.uri),
      );
      if (ok == true && mounted) {
        setState(() => _settingsLocked = false);
      }
    } else if (record.unlockMethod == ContainerUnlockMethod.password) {
      final verifiedPassword = await showDialog<String>(
        context: context,
        builder: (context) => _RealPasswordGateDialog(
          uri: widget.uri,
          cipherId: record.cipherId,
          hashId: record.hashId,
          documentProvider: _documentProvider,
        ),
      );
      // FIX: previously this only checked `ok == true` and discarded the
      // password the user just typed to pass verification — they'd then
      // have to type it again in the "Container password" field below to
      // actually set up biometrics/pattern/remember-password. Reuse it.
      if (verifiedPassword != null && mounted) {
        setState(() {
          _settingsLocked = false;
          _passwordCtrl.text = verifiedPassword;
        });
      }
    }
  }
  

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppBottomSheet(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.settings_rounded, size: AppIconSize.standard, color: cs.primary),
              const SizedBox(width: 10),
              Text('Container Settings',
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 20),

            // ── Label ────────────────────────────────────────────────────
            TextField(
              controller: _labelCtrl,
              decoration: InputDecoration(
                labelText: 'Display Name',
                prefixIcon: Icon(Icons.label_outline_rounded, size: AppIconSize.small),
                hintText: 'My Vault',
              ),
            ),
            const SizedBox(height: 16),

            // ── Unlock Method ─────────────────────────────────────────
            const SectionLabel('Unlock Method'),
            if (_settingsLocked) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: AppIconSize.feature, color: cs.primary),
                    const SizedBox(height: 12),
                    Text(
                      'Security settings are locked',
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Authenticate using the current unlock method to modify.',
                      style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _authenticateSettings,
                      icon: Icon(
                        widget.existingRecord?.unlockMethod.icon ?? Icons.lock_open_rounded,
                        size: AppIconSize.small,
                      ),
                      label: const Text('Unlock Settings'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              DropdownButtonFormField<ContainerUnlockMethod>(
                initialValue: _unlockMethod,
                decoration: const InputDecoration(
                  labelText: 'How to unlock',
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
                          Icon(m.icon, size: AppIconSize.small,
                              color: cs.onSurfaceVariant),
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
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _unlockMethod.subtitle,
                  style: textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                ),
              ),

              // ── Option to update password if already configured ──────
              if (widget.existingRecord != null &&
                  widget.existingRecord!.unlockMethod != ContainerUnlockMethod.password &&
                  _unlockMethod != ContainerUnlockMethod.password) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _changePassword,
                        onChanged: (v) => setState(() {
                          _changePassword = v ?? false;
                          if (!v!) _passwordCtrl.clear();
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() {
                        _changePassword = !_changePassword;
                        if (!_changePassword) _passwordCtrl.clear();
                      }),
                      child: Text(
                        'Update saved password',
                        style: textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],

              // ── Password field (shown for new setups or if change requested) ──
              if (_unlockMethod != ContainerUnlockMethod.password &&
                  (widget.existingRecord == null ||
                   widget.existingRecord!.unlockMethod == ContainerUnlockMethod.password ||
                   _changePassword)) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: !_showPassword,
                  autofillHints: null,
                  decoration: InputDecoration(
                    labelText: 'Container password',
                    prefixIcon: Icon(Icons.lock_rounded, size: AppIconSize.small),
                    // FIX: this was the one spot in the app using the non-outlined
                    // visibility/visibility_off glyphs instead of the _outlined
                    // variants used everywhere else — now unified via the shared
                    // PasswordVisibilityToggle widget.
                    suffixIcon: PasswordVisibilityToggle(
                      obscured: !_showPassword,
                      onToggle: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                    hintText: 'Enter container password',
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.security_rounded,
                      size: AppIconSize.inline, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Password is encrypted with a device-bound key in Android '
                      'Keystore. It is protected even if the APK is extracted, '
                      'but not if the device is rooted and the Keystore is bypassed.',
                      style: textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ]),
              ],

              // ── Pattern setup button ───────────────────────────────────
              if (_unlockMethod == ContainerUnlockMethod.pattern) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _setupPattern,
                  icon: Icon(
                    _patternHash != null
                        ? Icons.check_circle_rounded
                        : Icons.pattern_rounded,
                    size: AppIconSize.small,
                    color: _patternHash != null ? cs.primary : null,
                  ),
                  label: Text(_patternHash != null
                      ? 'Change Pattern'
                      : 'Set Pattern'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ],

              const SizedBox(height: 14),
              SettingsToggleRow(
                icon: Icons.security,
                title: 'Cache Derived Key',
                subtitle: 'Store derived key material in Android Keystore and reuse it for biometric, pattern, and password unlocks',
                value: _cacheDerivedKey,
                onChanged: (v) => setState(() => _cacheDerivedKey = v),
              ),
            ],
            const SizedBox(height: 16),

            // ── Auto-lock ─────────────────────────────────────────────────
            const SectionLabel('Auto-Lock'),
            DropdownButtonFormField<int>(
              initialValue: _autoCloseMins,
              decoration: const InputDecoration(
                labelText: 'Lock container after',
                prefixIcon: Icon(Icons.timer_rounded, size: AppIconSize.small),
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

            // ── Document Provider ─────────────────────────────────────────
            const SectionLabel('Android Integration'),
            SettingsToggleRow(
              icon: Icons.folder_shared_rounded,
              title: 'Expose as Document Provider',
              subtitle:
                  'Makes this container visible in Android\'s system file '
                  'picker when unlocked',
              value: _documentProvider,
              onChanged: (v) => setState(() => _documentProvider = v),
            ),
            const SizedBox(height: 16),

            // ── Thumbnail Caching ─────────────────────────────────────────
            const SectionLabel('Thumbnail Caching'),
            if (_loadingPassword)
              const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
            else
              DropdownButtonFormField<ThumbnailCacheMode?>(
                initialValue: _thumbnailCacheMode,
                decoration: const InputDecoration(
                  labelText: 'Thumbnail Cache Mode',
                  prefixIcon: Icon(Icons.cached_rounded, size: AppIconSize.small),
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
            const SizedBox(height: 24),

            if (widget.onForget != null) ...[
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onForget!();
                },
                icon: Icon(Icons.delete_outline_rounded,
                    size: AppIconSize.small, color: cs.error),
                label: Text('Remove from dashboard',
                    style: textTheme.labelLarge?.copyWith(color: cs.error)),
              ),
              const SizedBox(height: 12),
            ],

            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Verification Sheets/Dialogs ──────────────────────────────────────────────

class _PatternVerifySheet extends StatefulWidget {
  final String storedHash;
  const _PatternVerifySheet({Key? key, required this.storedHash}) : super(key: key);

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
  const _PasswordVerifyDialog({Key? key, required this.uri}) : super(key: key);

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
              // FIX: this was the actual bug — previously used the non-outlined
              // Icons.visibility / Icons.visibility_off pair while every other
              // password field in the app used the _outlined variants. Now
              // unified via PasswordVisibilityToggle.
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
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
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
  const _RealPasswordGateDialog({
    required this.uri,
    required this.cipherId,
    required this.hashId,
    required this.documentProvider,
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

  // USB-backed containers are unlocked/locked through a separate native
  // call keyed by the bare device name (no "usb:" prefix) — see
  // unlockUsbContainer / _expectedDeviceName in usb_unlock_sheet.dart.
  // widget.uri here is the ContainerRecord uri, which for USB entries is
  // stored as "usb:<deviceName>".
  bool get _isUsb => widget.uri.startsWith('usb:');
  String get _usbDeviceName => widget.uri.substring(4);

  @override
  void dispose() {
    _pwCtrl.dispose();
    _pimCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_pwCtrl.text.isEmpty) {
      setState(() => _error = 'Password is required');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final pim = clampPim(_pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0);
      // FIX: "password" method stores nothing to compare a re-entry
      // against — a genuine unlock attempt is the only real proof. Lock
      // it straight back down afterward; this exists purely to gate
      // settings access, not to leave the container mounted.
      //
      // FIX: this used to always call unlockContainer(widget.uri, ...),
      // which only understands content:// / file:// document uris. For a
      // USB-backed container widget.uri is "usb:<deviceName>", so that
      // call would never succeed — it needs unlockUsbContainer with the
      // bare device name instead, and the matching lockContainer identifier
      // afterward.
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
              cacheDerivedKey: false,
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
              cacheDerivedKey: false,
            );
      if (result == null) {
        if (mounted) setState(() { _loading = false; _error = 'Incorrect password'; });
        return;
      }
      await vaultExplorerApi.lockContainer(_isUsb ? _usbDeviceName : widget.uri);
      // Return the verified password itself (not just a bool) so the
      // caller can reuse it — the user already proved they know it via a
      // genuine unlock, no need to make them type it a second time to set
      // up biometrics/pattern/remember-password.
      if (mounted) Navigator.pop(context, _pwCtrl.text);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Verification failed'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Container Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'This container has no stored password to check against — '
            'enter it directly to confirm before changing security settings.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pwCtrl,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Container password',
              suffixIcon: PasswordVisibilityToggle(
                obscured: _obscure,
                onToggle: () => setState(() => _obscure = !_obscure),
              ),
              errorText: _error,
            ),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pimCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'PIM (leave blank if not used)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _loading ? null : _verify,
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Verify'),
        ),
      ],
    );
  }
}