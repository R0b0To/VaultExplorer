import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/vaultexplorer_api.dart';
import '../../services/app_settings_service.dart';
import '../../models/mounted_container.dart';
import '../../models/usb_device_info.dart';
import '../../utils/validation_utils.dart';
import 'package:local_auth/local_auth.dart';
import '../lock/pattern_lock_view.dart';

class UsbUnlockSheet extends StatefulWidget {
  /// Called on every successful mount. [remember] reports whether the
  /// caller should persist a fresh ContainerRecord for this uri — mirrors
  /// the "Remember drive on dashboard" checkbox. It only matters for a
  /// brand-new mount (no [existingRecord]); reconnects of an
  /// already-saved record always pass true, since a record already exists
  /// either way. Defaults to true so this stays a drop-in ValueChanged for
  /// the file-based unlock flow, which has no such checkbox.
  final void Function(MountedContainer container, {bool remember}) onMounted;
  final bool documentProvider;

  /// Set when unlocking from a saved dashboard entry (a "reconnect") rather
  /// than a fresh "Add Vault → Mount USB Drive" flow. Drives device
  /// auto-selection, password prefill, and title text; also triggers uri
  /// migration in [_unlock] if the device enumerated under a different path
  /// than last time.
  final ContainerRecord? existingRecord;

  /// Prefetched from Keystore by the caller when [existingRecord]'s
  /// unlockMethod is [ContainerUnlockMethod.rememberPassword] — mirrors how
  /// the file-based UnlockSheet handles its equivalent case. Not fetched
  /// automatically here since doing so requires an async Keystore read the
  /// caller already has better context to trigger (e.g. before even
  /// opening the sheet, to avoid a visible flash of an empty field).
  final String? prefillPassword;

  /// Called instead of [onMounted] when [existingRecord] is non-null AND the
  /// device's actual path differs from [existingRecord].uri — i.e. the
  /// drive reconnected under a new bus address. The caller (VaultDashboard)
  /// uses this to reconcile its own in-memory container-record map against
  /// the migration this sheet already performed via [ContainerRepository]
  /// directly. Not invoked for a fresh mount or when the path didn't change
  /// (in both of those cases [onMounted] is used as before).
  final void Function(
    MountedContainer container,
    ContainerRecord migratedRecord,
    String oldUri,
  )?
  onReconnected;

  const UsbUnlockSheet({
    Key? key,
    required this.onMounted,
    this.documentProvider = false,
    this.existingRecord,
    this.prefillPassword,
    this.onReconnected,
  }) : super(key: key);

  @override
  State<UsbUnlockSheet> createState() => _UsbUnlockSheetState();
}

class _UsbUnlockSheetState extends State<UsbUnlockSheet> {
  final _passwordCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();

  List<UsbDeviceInfo> _devices = [];
  UsbDeviceInfo? _selected;
  bool _obscure = true;
  bool _loadingDevices = true;
  bool _requestingPermission = false;
  bool _unlocking = false;
  String? _error;
  int _cipherId = 255; // Auto
  int _hashId = 255; // Auto
  bool _remember = false;

  // ── Unlock method state ──────────────────────────────────────────────────
  ContainerUnlockMethod _unlockMethod = ContainerUnlockMethod.password;
  bool _showPasswordFallback = false;
  bool _patternError = false;
  int _patternResetKey = 0;
  String? _storedPatternHash;
  bool _loadingAuth = true;

  /// True once [_loadDevices] has run and [existingRecord] names a device
  /// that isn't among the currently connected drives — i.e. the saved
  /// drive needs to be physically reconnected, or the user needs to pick
  /// whichever drive it now enumerates as.
  bool _reconnectTargetMissing = false;

  /// The raw USB device path (e.g. "/dev/bus/usb/002/002") this sheet was
  /// last saved under, extracted from existingRecord.uri (format
  /// "usb:<deviceName>"). Null for a fresh mount.
  String? get _expectedDeviceName {
    final uri = widget.existingRecord?.uri;
    if (uri == null || !uri.startsWith('usb:')) return null;
    return uri.substring(4);
  }

  bool get _passwordPrefilled =>
      widget.prefillPassword?.isNotEmpty == true &&
      _passwordCtrl.text == widget.prefillPassword;

  @override
  void initState() {
    super.initState();
    if (widget.prefillPassword != null && widget.prefillPassword!.isNotEmpty) {
      _passwordCtrl.text = widget.prefillPassword!;
    }
     if (widget.existingRecord != null) {
      _cipherId = widget.existingRecord!.cipherId;
      _hashId = widget.existingRecord!.hashId;
    }
    _loadDevices();
    _initUnlockMethod();
  }

  Future<void> _initUnlockMethod() async {
    final record = widget.existingRecord;
    if (record == null) {
      if (mounted) setState(() => _loadingAuth = false);
      return;
    }

    try {
      _unlockMethod = record.unlockMethod;

      if (_unlockMethod == ContainerUnlockMethod.pattern) {
        _storedPatternHash = await ContainerRepository.instance.getPatternHash(
          record.uri,
        );
      }

      if (mounted) setState(() => _loadingAuth = false);

      // Auto-trigger biometric prompt.
      if (_unlockMethod == ContainerUnlockMethod.biometrics) {
        _tryBiometric();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAuth = false);
    }
  }

  Future<void> _tryBiometric() async {
    final record = widget.existingRecord;
    if (record == null) return;
    try {
      final localAuth = LocalAuthentication();
      final ok = await localAuth.authenticate(
        localizedReason: 'Authenticate to unlock USB drive',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (ok && mounted) {
        final appSettings = await AppSettingsService.loadSettings();
        final shouldUseCachedKey = record.cacheDerivedKey ||
            appSettings.defaultDerivedKeyCacheEnabled;
        // FIX: the derived-key cache is keyed by the bare device name
        // everywhere else in this file (_unlock()'s own preload lookup,
        // the 'deviceName' passed to unlockUsbContainer) — never by the
        // "usb:"-prefixed record uri. Looking it up under record.uri here
        // was a guaranteed cache miss, so this silently fell through to a
        // full password-based derivation on every biometric unlock.
        final deviceName = _expectedDeviceName;
        final cachedKey = shouldUseCachedKey && deviceName != null
            ? await vaultExplorerApi.loadDerivedKey(deviceName)
            : null;
        debugPrint('usb unlock: biometric cached-key present=${cachedKey != null && cachedKey.isNotEmpty} for ${record.uri}');
        if (cachedKey != null && cachedKey.isNotEmpty) {
          await _unlock(
            preservedKey: cachedKey,
            shouldCacheDerivedKeyOverride: shouldUseCachedKey,
          );
          return;
        }

        final pw = await ContainerRepository.instance.getPassword(
          record.uri,
        );
        if (pw != null && pw.isNotEmpty) {
          _passwordCtrl.text = pw;
          await _unlock(
            shouldCacheDerivedKeyOverride: shouldUseCachedKey,
            passwordOverride: pw,
          );
        } else {
          setState(() {
            _error = 'No saved password found. Please enter it manually.';
            _showPasswordFallback = true;
          });
        }
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Biometric error: ${e.message}';
          _showPasswordFallback = true;
        });
      }
    }
  }

  Future<void> _onPatternComplete(List<int> pattern) async {
    final record = widget.existingRecord;
    if (record == null) return;
    if (_storedPatternHash == null) {
      setState(() {
        _error = 'No pattern configured. Please enter password manually.';
        _showPasswordFallback = true;
      });
      return;
    }

    final attempt = hashPattern(pattern);
    if (attempt == _storedPatternHash) {
      // FIX: this used to skip straight to the saved password, always
      // doing a full password-based derivation — unlike the file-based
      // sheet's equivalent pattern handler (and this sheet's own
      // _tryBiometric), which try the cached derived key first.
      // _unlock() itself won't do this preload on our behalf here: its
      // internal check only fires when _unlockMethod == rememberPassword,
      // not pattern, so pattern/biometric are expected to look the key up
      // themselves and hand it in via preservedKey.
      final appSettings = await AppSettingsService.loadSettings();
      final shouldUseCachedKey = record.cacheDerivedKey ||
          appSettings.defaultDerivedKeyCacheEnabled;
      final deviceName = _expectedDeviceName;
      final cachedKey = shouldUseCachedKey && deviceName != null
          ? await vaultExplorerApi.loadDerivedKey(deviceName)
          : null;
      debugPrint('usb unlock: pattern cached-key present=${cachedKey != null && cachedKey.isNotEmpty} for ${record.uri}');

      if (cachedKey != null && cachedKey.isNotEmpty) {
        await _unlock(
          preservedKey: cachedKey,
          shouldCacheDerivedKeyOverride: shouldUseCachedKey,
        );
        return;
      }

      final pw = await ContainerRepository.instance.getPassword(
        record.uri,
      );
      if (pw != null && pw.isNotEmpty) {
        _passwordCtrl.text = pw;
        await _unlock(
          shouldCacheDerivedKeyOverride: shouldUseCachedKey,
          passwordOverride: pw,
        );
      } else {
        setState(() {
          _error = 'No saved password found. Please enter it manually.';
          _showPasswordFallback = true;
        });
      }
    } else {
      setState(() {
        _patternError = true;
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _patternError = false;
            _patternResetKey++;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _pimCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() => _loadingDevices = true);
    try {
      final devices = await vaultExplorerApi.listUsbDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _loadingDevices = false;

          final expected = _expectedDeviceName;
          if (expected != null) {
            // Reconnect flow: try to find the same physical drive under its
            // previously-saved path. If it's not there (unplugged, or
            // re-enumerated under a different bus address), leave nothing
            // preselected and surface that clearly rather than silently
            // defaulting to some other connected drive.
            final matches = devices.where((d) => d.deviceName == expected);
            _selected = matches.isEmpty ? null : matches.first;
            _reconnectTargetMissing = matches.isEmpty;
          } else if (devices.length == 1) {
            _selected = devices.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDevices = false;
          _error = 'Failed to list USB devices: $e';
        });
      }
    }
  }

  Future<void> _ensurePermission(UsbDeviceInfo device) async {
    if (device.hasPermission) return;
    setState(() => _requestingPermission = true);
    final granted = await vaultExplorerApi.requestUsbPermission(device.deviceName);
    if (mounted) {
      setState(() {
        _requestingPermission = false;
        if (!granted) _error = 'USB permission denied';
      });
    }
    if (granted) await _loadDevices();
  }

  Future<void> _unlock({
    Uint8List? preservedKey,
    bool? shouldCacheDerivedKeyOverride,
    String? passwordOverride,
  }) async {
    final device = _selected;
    if (device == null) {
      setState(() => _error = 'Select a USB drive first');
      return;
    }
    var effectivePassword = (passwordOverride ?? _passwordCtrl.text).trim();
    if (effectivePassword.isEmpty && preservedKey == null) {
      setState(() => _error = 'Password is required');
      return;
    }

    setState(() { _unlocking = true; _error = null; });

    try {
      if (!device.hasPermission) {
        await _ensurePermission(device);
        final refreshed = _devices.firstWhere((d) => d.deviceName == device.deviceName, orElse: () => device);
        if (!refreshed.hasPermission) {
          setState(() => _error = 'USB permission is required to continue');
          return;
        }
      }

      final pim = clampPim(_pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0);
      final displayName = widget.existingRecord?.label ?? device.productName;

      final appSettings = await AppSettingsService.loadSettings();
      final isReconnect = widget.existingRecord != null;
      final shouldCacheDerivedKey = shouldCacheDerivedKeyOverride ??
          ((isReconnect || _remember) &&
              ((widget.existingRecord?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled));


      final shouldPreloadCachedKey = preservedKey == null &&
          _unlockMethod == ContainerUnlockMethod.rememberPassword &&
          _passwordPrefilled &&
          (widget.existingRecord?.cacheDerivedKey ?? false);
      final resolvedPreservedKey = preservedKey ??
          (shouldPreloadCachedKey
              ? await vaultExplorerApi.loadDerivedKey(device.deviceName)
              : null);
      debugPrint('usb unlock: method=$_unlockMethod shouldCacheDerivedKey=$shouldCacheDerivedKey preservedKeyLen=${resolvedPreservedKey?.length ?? 0}');

      var result = await vaultExplorerApi.unlockUsbContainer(
        device.deviceName,
        effectivePassword,
        pim,
        displayName: displayName,
        documentProvider: widget.documentProvider,
        cipherId: _cipherId,
        hashId: _hashId,
        preservedKey: resolvedPreservedKey,
        cacheDerivedKey: shouldCacheDerivedKey,
      );

      // FIX: same stale-key fallback as the file-based sheet — a bus path
      // that re-enumerated onto a different drive would otherwise fail
      // outright instead of falling back to the actual password.
      if (result == null && resolvedPreservedKey != null) {
        await vaultExplorerApi.clearDerivedKey(device.deviceName);
        if (effectivePassword.isEmpty && widget.existingRecord != null) {
          effectivePassword =
              (await ContainerRepository.instance.getPassword(widget.existingRecord!.uri))?.trim() ?? '';
        }
        if (effectivePassword.isNotEmpty) {
          result = await vaultExplorerApi.unlockUsbContainer(
            device.deviceName,
            effectivePassword,
            pim,
            displayName: displayName,
            documentProvider: widget.documentProvider,
            cipherId: _cipherId,
            hashId: _hashId,
            preservedKey: null,
            cacheDerivedKey: shouldCacheDerivedKey,
          );
        }
      }

      if (result == null) {
        setState(() => _error = 'Incorrect password or unsupported drive');
        return;
      }

  

      final newUri = 'usb:${device.deviceName}';
      final tempContainer = MountedContainer(
        uri: newUri,
        displayName: displayName,
        volId: result.volId,
        rootFiles: result.files,
        mountedAt: DateTime.now(),
        totalSpace: 0,
        freeSpace: 0,
      );
      final space = await vaultExplorerApi.getSpaceInfo(tempContainer);
      final total = (space != null && space.isNotEmpty) ? space[0] : 0;
      final free = (space != null && space.length > 1) ? space[1] : 0;
      final finalContainer = tempContainer.copyWith(
        totalSpace: total,
        freeSpace: free,
      );

      final existing = widget.existingRecord;
      if (existing != null && existing.uri != newUri) {
        // FIX: USB device paths are assigned by
        // bus enumeration order and can change across unplug/replug cycles
        // — unlike a file container's persistent content:// uri, which
        // never changes once granted. Without this, re-unlocking a saved
        // USB entry whose path drifted would either fail outright (old
        // path no longer resolves to anything) or silently create a second,
        // unrelated-looking dashboard entry every time it drifted again.
        //
        // Migrate the saved settings — label, unlock method, remembered
        // password/pattern, auto-close, thumbnail cache mode, and the
        // matched cipher/hash — onto the new uri and remove the stale one,
        // so the dashboard entry keeps working across reconnects instead
        // of rotting.
        final savedPassword = await ContainerRepository.instance.getPassword(
          existing.uri,
        );
        final savedPatternHash = await ContainerRepository.instance
            .getPatternHash(existing.uri);
        await ContainerRepository.instance.remove(existing.uri);

        final migrated = ContainerRecord(
          uri: newUri,
          label: existing.label,
          rememberPassword: existing.rememberPassword,
          unlockMethod: existing.unlockMethod,
          autoCloseMins: existing.autoCloseMins,
          documentProvider: existing.documentProvider,
          thumbnailCacheMode: existing.thumbnailCacheMode,
          cacheDerivedKey: shouldCacheDerivedKey,
          pendingPassword: savedPassword,
          pendingPatternHash: savedPatternHash,
          // FIX (perf): carry the resolved cipher/hash through the
          // migration too, so a path-drifted reconnect doesn't silently
          // fall back to full auto-detect forever.
          cipherId: result.matchedCipherId,
          hashId: result.matchedHashId,
        );
        await ContainerRepository.instance.save(migrated);

        widget.onReconnected?.call(finalContainer, migrated, existing.uri);
      } else if (existing != null) {
        // Same device, same uri — just keep the remembered cipher/hash in
        // sync with whatever actually unlocked successfully this time
        // (covers first-time resolution from 255/auto, and the rare case
        // where a manually-picked combination differs from what's stored).
        if (existing.cipherId != result.matchedCipherId ||
            existing.hashId != result.matchedHashId) {
          await ContainerRepository.instance.save(
            existing.copyWith(
              cacheDerivedKey: shouldCacheDerivedKey,
              cipherId: result.matchedCipherId,
              hashId: result.matchedHashId,
            ),
          );
        }
        widget.onMounted(finalContainer);
      } else {
        // Brand-new USB mount with no saved record yet. Create one now
        // with the resolved cipher/hash already populated, so the default
        // record VaultDashboard._onContainerMounted would otherwise create
        // (with cipherId/hashId left at 255/auto) never overwrites it —
        // that method only fills in a record if one isn't already present.
        if (_remember) {
    await ContainerRepository.instance.save(
      ContainerRecord(
        uri: newUri,
        label: displayName,
        documentProvider: widget.documentProvider,
        cacheDerivedKey: shouldCacheDerivedKey,
        cipherId: result.matchedCipherId,
        hashId: result.matchedHashId,
      ),
    );
  }
        // FIX: previously always onMounted(finalContainer) with no way for
        // the dashboard to know whether _remember was checked — it would
        // then persist a default ContainerRecord itself the first time it
        // saw this uri, saving the drive to the dashboard even when the
        // user left the checkbox unchecked. Pass _remember through so the
        // dashboard's own "first time seeing this uri" save honors it.
        widget.onMounted(finalContainer, remember: _remember);
      }

      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e is PlatformException ? (e.message ?? e.toString()) : e.toString());
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    final busy = _unlocking || _requestingPermission;
    final isReconnect = widget.existingRecord != null;

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isReconnect
                      ? 'Reconnect "${widget.existingRecord!.label}"'
                      : 'Unlock USB Drive',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                
                const SizedBox(height: 16),

                if (_loadingDevices)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  // ── Reconnect-target-missing banner ─────────────────────
                  if (isReconnect && _reconnectTargetMissing) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.usb_off_rounded, size: 28, color: cs.onTertiaryContainer),
                          const SizedBox(height: 8),
                          Text(
                            'Couldn\'t find "${widget.existingRecord!.label}"',
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.onTertiaryContainer,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Plug the drive back in and tap Retry, or select it below '
                            'if it shows up under a different name.',
                            style: textTheme.bodySmall?.copyWith(color: cs.onTertiaryContainer),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          TextButton(onPressed: _loadDevices, child: const Text('Retry')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_devices.isEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.usb_off_rounded, size: 32, color: cs.onSurfaceVariant),
                          const SizedBox(height: 8),
                          Text('No USB mass-storage drives detected',
                              style: textTheme.bodyMedium, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          TextButton(onPressed: _loadDevices, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  ] else ...[
                    ..._devices.map((d) => RadioListTile<UsbDeviceInfo>(
                          value: d,
                          // ignore: deprecated_member_use
                          groupValue: _selected,
                          onChanged: busy ? null : (v) => setState(() => _selected = v),
                          title: Text(d.productName),
                          subtitle: Text(d.hasPermission ? 'Ready' : 'Permission required'),
                          secondary: Icon(Icons.usb_rounded,
                              color: d.hasPermission ? cs.primary : cs.onSurfaceVariant),
                        )),
                    const SizedBox(height: 12),

                    if (_loadingAuth)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_unlockMethod == ContainerUnlockMethod.biometrics && !_showPasswordFallback) ...[
                      Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: _unlocking ? 0.3 : 1.0,
                              child: IgnorePointer(
                                ignoring: _unlocking,
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.fingerprint_rounded,
                                      size: 64,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Waiting for biometric...',
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextButton(
                                      onPressed: _tryBiometric,
                                      child: const Text('Retry'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _showPasswordFallback = true),
                                      child: const Text('Use Password'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_unlocking)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Unlocking...',
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ]
                    else if (_unlockMethod == ContainerUnlockMethod.pattern && !_showPasswordFallback) ...[
                      Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: _unlocking ? 0.3 : 1.0,
                              child: IgnorePointer(
                                ignoring: _unlocking,
                                child: Column(
                                  children: [
                                    Text(
                                      _patternError
                                          ? 'Wrong pattern — try again'
                                          : 'Draw your unlock pattern',
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: _patternError ? cs.error : cs.onSurfaceVariant,
                                        fontWeight: _patternError ? FontWeight.bold : null,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    PatternLockView(
                                      key: ValueKey(_patternResetKey),
                                      onPatternComplete: _onPatternComplete,
                                      showError: _patternError,
                                    ),
                                    const SizedBox(height: 12),
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _showPasswordFallback = true),
                                      child: const Text('Use Password'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_unlocking)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Unlocking...',
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ]
                    else ...[
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        enabled: !busy,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.key_outlined, size: 18),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pimCtrl,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'PIM  (leave blank for default)',
                          prefixIcon: Icon(Icons.tune_rounded, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<int>(
                        initialValue: _cipherId,
                        decoration: const InputDecoration(
                          labelText: 'Encryption Algorithm',
                          prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                        ),
                        items: const [
                          DropdownMenuItem(value: 255, child: Text('Auto-detect')),
                          DropdownMenuItem(value: 0, child: Text('AES')),
                          DropdownMenuItem(value: 1, child: Text('Serpent')),
                          DropdownMenuItem(value: 2, child: Text('Twofish')),
                          DropdownMenuItem(value: 3, child: Text('AES-Twofish')),
                          DropdownMenuItem(value: 4, child: Text('Serpent-AES')),
                          DropdownMenuItem(value: 5, child: Text('Twofish-Serpent')),
                          DropdownMenuItem(value: 6, child: Text('AES-Twofish-Serpent')),
                          DropdownMenuItem(value: 7, child: Text('Serpent-Twofish-AES')),
                        ],
                        onChanged: busy ? null : (val) {
                          if (val != null) setState(() => _cipherId = val);
                        },
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<int>(
                        initialValue: _hashId,
                        decoration: const InputDecoration(
                          labelText: 'Hash Algorithm',
                          prefixIcon: Icon(Icons.tag_rounded, size: 18),
                        ),
                        items: const [
                          DropdownMenuItem(value: 255, child: Text('Auto-detect')),
                          DropdownMenuItem(value: 0, child: Text('SHA-512')),
                          DropdownMenuItem(value: 1, child: Text('SHA-256')),
                          DropdownMenuItem(value: 2, child: Text('Whirlpool')),
                          DropdownMenuItem(value: 3, child: Text('Streebog')),
                          DropdownMenuItem(value: 4, child: Text('BLAKE2s-256')),
                        ],
                        onChanged: busy ? null : (val) {
                          if (val != null) setState(() => _hashId = val);
                        },
                      ),
                      const SizedBox(height: 12),

                      if (!isReconnect) ...[
                        Row(
                          children: [
                            Checkbox(
                              value: _remember,
                              onChanged: busy ? null : (v) => setState(() => _remember = v ?? false),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: busy ? null : () => setState(() => _remember = !_remember),
                              child: Text('Remember drive on dashboard', style: textTheme.bodyMedium),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 20, color: cs.onErrorContainer),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(_error!,
                                    style: textTheme.bodySmall?.copyWith(color: cs.onErrorContainer)),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: busy || _devices.isEmpty || _selected == null ? null : _unlock,
                        style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                        child: busy
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : Text(isReconnect ? 'Unlock' : 'Unlock Drive'),
                      ),
                    ],
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}