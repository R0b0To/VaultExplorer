import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';

class UsbUnlockSheet extends StatefulWidget {
  final void Function(MountedContainer container, {ContainerRecord? record}) onMounted;
  final bool documentProvider;
  final ContainerRecord? existingRecord;
  final String? prefillPassword;
  final void Function(MountedContainer container, ContainerRecord migratedRecord, String oldUri)? onReconnected;
  final List<String> mountedUris;

  const UsbUnlockSheet({
    super.key,
    required this.onMounted,
    this.documentProvider = false,
    this.existingRecord,
    this.prefillPassword,
    this.onReconnected,
    this.mountedUris = const [],
  });

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
  bool _readOnly = false;
  String? _error;
  int _cipherId = 255; // Auto
  int _hashId = 255; // Auto
  bool _remember = false;
  final List<KeyfileRef> _keyfiles = [];
  bool _pickingKeyfiles = false;

  String _containerFormat = 'veracrypt';

  /// Format getters for format-specific UI branching
  bool get _isLuks => _containerFormat == 'luks1' || _containerFormat == 'luks2';
  bool get _isBitlocker => _containerFormat == 'bitlocker';

  // ── Cancel / progress state ──────────────────────────────────────────────
  int? _activeVolId;
  UnlockProgress? _progress;
  late final void Function(int) _onUnlockStarted;
  late final void Function(UnlockProgress) _onUnlockProgress;

  Future<void>? _loadDevicesFuture;

  ContainerUnlockMethod _unlockMethod = ContainerUnlockMethod.password;
  bool _showPasswordFallback = false;
  bool _patternError = false;
  int _patternResetKey = 0;
  String? _storedPatternHash;
  bool _loadingAuth = true;
  bool _reconnectTargetMissing = false;
  bool _isAuthenticating = false;

  String? get _expectedDeviceName {
    final uri = widget.existingRecord?.uri;
    if (uri == null || !uri.startsWith('usb:')) return null;
    return uri.substring(4);
  }

  bool get _passwordPrefilled =>
      widget.prefillPassword?.isNotEmpty == true &&
      _passwordCtrl.text == widget.prefillPassword;

  String get _unlockProgressLabel {
    final p = _progress;
    if (p == null || p.total <= 0) return 'Decrypting drive...';
    if (_isLuks) {
      return p.total > 1
          ? 'Trying keyslot ${p.attempted} of ${p.total}…'
          : 'Trying keyslot…';
    }
    if (_isBitlocker) {
      return p.total > 1
          ? 'Verifying credential ${p.attempted} of ${p.total}…'
          : 'Verifying credential…';
    }
    final hashName = hashAlgorithmName(p.hashId);
    final cipherName = p.cipherId != 255 ? cipherAlgorithmName(p.cipherId) : '';
    final slotName = p.slot == 1 ? 'Hidden Volume' : 'Standard Volume';
    
    final algo = cipherName.isNotEmpty ? '$hashName + $cipherName' : hashName;

    return p.total > 1
        ? 'Trying $algo ($slotName)…'
        : 'Trying $algo ($slotName)…';
  }

  @override
  void initState() {
    super.initState();
    if (widget.prefillPassword != null && widget.prefillPassword!.isNotEmpty) {
      _passwordCtrl.text = widget.prefillPassword!;
    }
    if (widget.existingRecord != null) {
      _cipherId = widget.existingRecord!.cipherId;
      _hashId = widget.existingRecord!.hashId;
      _containerFormat = widget.existingRecord!.containerFormat;
    }
    _loadDevicesFuture = _loadDevices();
    _initUnlockMethod();

    _onUnlockStarted = (volId) {
      if (mounted) setState(() => _activeVolId = volId);
    };
    _onUnlockProgress = (progress) {
      if (mounted && progress.volId == _activeVolId) {
        setState(() {
          _progress = progress;
          if (progress.containerFormat != 'veracrypt') {
            _containerFormat = progress.containerFormat;
          }
        });
      }
    };
    VaultExplorerApi.addUnlockStartedListener(_onUnlockStarted);
    VaultExplorerApi.addUnlockProgressListener(_onUnlockProgress);
  }

  Future<void> _initUnlockMethod() async {
    final record = widget.existingRecord;
    if (record == null) {
      if (mounted) setState(() => _loadingAuth = false);
      return;
    }

    try {
      _unlockMethod = record.unlockMethod;
      _readOnly = record.readOnly;

      if (_unlockMethod == ContainerUnlockMethod.pattern) {
        _storedPatternHash = await ContainerRepository.instance.getPatternHash(record.uri);
      }

      if (mounted) setState(() => _loadingAuth = false);

      if (_unlockMethod == ContainerUnlockMethod.biometrics) {
        if (_loadDevicesFuture != null) {
          await _loadDevicesFuture;
        }
        // Small delay allows route & device scan animations to settle before prompting biometrics
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (mounted && _selected != null && !_reconnectTargetMissing) {
          _tryBiometric();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAuth = false);
    }
  }

  Future<void> _tryBiometric() async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;

    final record = widget.existingRecord;
    if (record == null) {
      _isAuthenticating = false;
      return;
    }
    
    if (_selected == null) {
      if (mounted) setState(() => _error = 'Select a USB drive first');
      _isAuthenticating = false;
      return;
    }

    try {
      final localAuth = LocalAuthentication();
      final canCheck = await localAuth.canCheckBiometrics;
      final isSupported = await localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) {
        if (mounted) {
          setState(() {
            _error = 'Biometrics not available on this device';
            _showPasswordFallback = true;
          });
        }
        return;
      }

      final ok = await localAuth.authenticate(
        localizedReason: 'Authenticate to unlock USB drive',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (ok && mounted) {
        final appSettings = await AppSettingsService.loadSettings();
        final shouldUseCachedKey = record.cacheDerivedKey || appSettings.defaultDerivedKeyCacheEnabled;
        final deviceName = _expectedDeviceName;
        final cachedKey = shouldUseCachedKey && deviceName != null
            ? await vaultExplorerApi.loadDerivedKey(deviceName)
            : null;
        debugPrint('usb unlock: biometric cached-key present=${cachedKey != null && cachedKey.isNotEmpty} for ${record.uri}');
        if (cachedKey != null && cachedKey.isNotEmpty) {
          await _unlock(preservedKey: cachedKey, shouldCacheDerivedKeyOverride: shouldUseCachedKey);
          return;
        }

        final pw = await ContainerRepository.instance.getPassword(record.uri);
        if (pw != null && pw.isNotEmpty) {
          _passwordCtrl.text = pw;
          await _unlock(shouldCacheDerivedKeyOverride: shouldUseCachedKey, passwordOverride: pw);
        } else {
          setState(() {
            _error = 'No saved password found. Please enter it manually.';
            _showPasswordFallback = true;
          });
        }
      }
    } on PlatformException catch (e) {
      if (e.code == 'auth_in_progress' ||
          e.code == 'AuthenticationInProgress' ||
          (e.message?.contains('Authentication in progress') ?? false)) {
        // Silently swallow race condition error on startup/transitions
        return;
      }
      if (mounted) {
        setState(() {
          _error = 'Biometric error: ${e.message}';
          _showPasswordFallback = true;
        });
      }
    } finally {
      _isAuthenticating = false;
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
      final appSettings = await AppSettingsService.loadSettings();
      final shouldUseCachedKey = record.cacheDerivedKey || appSettings.defaultDerivedKeyCacheEnabled;
      final deviceName = _expectedDeviceName;
      final cachedKey = shouldUseCachedKey && deviceName != null
          ? await vaultExplorerApi.loadDerivedKey(deviceName)
          : null;
      debugPrint('usb unlock: pattern cached-key present=${cachedKey != null && cachedKey.isNotEmpty} for ${record.uri}');

      if (cachedKey != null && cachedKey.isNotEmpty) {
        await _unlock(preservedKey: cachedKey, shouldCacheDerivedKeyOverride: shouldUseCachedKey);
        return;
      }

      final pw = await ContainerRepository.instance.getPassword(record.uri);
      if (pw != null && pw.isNotEmpty) {
        _passwordCtrl.text = pw;
        await _unlock(shouldCacheDerivedKeyOverride: shouldUseCachedKey, passwordOverride: pw);
      } else {
        setState(() {
          _error = 'No saved password found. Please enter it manually.';
          _showPasswordFallback = true;
        });
      }
    } else {
      setState(() => _patternError = true);
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
    if (_unlocking && _activeVolId != null) {
      vaultExplorerApi.cancelUnlock(_activeVolId!);
    }
    VaultExplorerApi.removeUnlockStartedListener(_onUnlockStarted);
    VaultExplorerApi.removeUnlockProgressListener(_onUnlockProgress);
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
            final matches = devices.where((d) => d.deviceName == expected);
            _selected = matches.isEmpty ? null : matches.first;
            _reconnectTargetMissing = matches.isEmpty;
          } else if (devices.length == 1) {
            final d = devices.first;
            final isAlreadyMounted = widget.mountedUris.contains('usb:${d.deviceName}');
            _selected = isAlreadyMounted ? null : d;
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

  Future<T?> _unlockSwallowingStaleAuthFail<T>(Future<T> Function() attempt) async {
    try {
      return await attempt();
    } on PlatformException catch (e) {
      if (e.code == 'AUTH_FAIL') return null;
      rethrow;
    }
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
    
    final newUri = 'usb:${device.deviceName}';
    if (widget.mountedUris.contains(newUri)) {
      setState(() => _error = 'This USB device is already active and mounted.');
      return;
    }

    var effectivePassword = (passwordOverride ?? _passwordCtrl.text).trim();
    if (effectivePassword.isEmpty && preservedKey == null && _keyfiles.isEmpty) {
      setState(() => _error = 'Password or keyfiles required');
      return;
    }

    setState(() { _unlocking = true; _error = null; _activeVolId = null; _progress = null; });

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
      final keyfilePaths = _keyfiles.map((k) => k.uri).toList();

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

      var result = resolvedPreservedKey == null
          ? await vaultExplorerApi.unlockUsbContainer(
              device.deviceName,
              effectivePassword,
              pim,
              displayName: displayName,
              documentProvider: widget.documentProvider,
              cipherId: _cipherId,
              hashId: _hashId,
              preservedKey: resolvedPreservedKey,
              cacheDerivedKey: shouldCacheDerivedKey,
              keyfilePaths: keyfilePaths,
              readOnly: _readOnly,
            )
          : await _unlockSwallowingStaleAuthFail(() => vaultExplorerApi.unlockUsbContainer(
              device.deviceName,
              effectivePassword,
              pim,
              displayName: displayName,
              documentProvider: widget.documentProvider,
              cipherId: _cipherId,
              hashId: _hashId,
              preservedKey: resolvedPreservedKey,
              cacheDerivedKey: shouldCacheDerivedKey,
              keyfilePaths: keyfilePaths,
              readOnly: _readOnly,
            ));

      if (result == null && resolvedPreservedKey != null) {
        await vaultExplorerApi.clearDerivedKey(device.deviceName);
        if (effectivePassword.isEmpty && widget.existingRecord != null) {
          effectivePassword =
              (await ContainerRepository.instance.getPassword(widget.existingRecord!.uri))?.trim() ?? '';
        }
        if (effectivePassword.isNotEmpty || keyfilePaths.isNotEmpty) {
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
            keyfilePaths: keyfilePaths,
            readOnly: _readOnly,
          );
        }
      }

      if (result == null) {
        setState(() => _error = 'Incorrect password/keyfiles or unsupported drive');
        return;
      }

      final tempContainer = MountedContainer(
        uri: newUri,
        displayName: displayName,
        volId: result.volId,
        rootFiles: result.files,
        mountedAt: DateTime.now(),
        totalSpace: 0,
        freeSpace: 0,
        readOnly: _readOnly,
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
        final savedPassword = await ContainerRepository.instance.getPassword(existing.uri);
        final savedPatternHash = await ContainerRepository.instance.getPatternHash(existing.uri);
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
          readOnly: _readOnly,
          pendingPassword: savedPassword,
          pendingPatternHash: savedPatternHash,
          cipherId: result.matchedCipherId,
          hashId: result.matchedHashId,
          containerFormat: result.containerFormat,
        );
        await ContainerRepository.instance.save(migrated);

        widget.onReconnected?.call(finalContainer, migrated, existing.uri);
      } else if (existing != null) {
        var effectiveExisting = existing;
        if (existing.cipherId != result.matchedCipherId ||
            existing.hashId != result.matchedHashId ||
            existing.containerFormat != result.containerFormat ||
            existing.readOnly != _readOnly) {   
          effectiveExisting = existing.copyWith(
            cacheDerivedKey: shouldCacheDerivedKey,
            readOnly: _readOnly,   
            cipherId: result.matchedCipherId,
            hashId: result.matchedHashId,
            containerFormat: result.containerFormat,
          );
          await ContainerRepository.instance.save(effectiveExisting);
        }
        widget.onMounted(finalContainer, record: effectiveExisting);
      } else {
        ContainerRecord? savedRecord;
        if (_remember) {
          savedRecord = ContainerRecord(
            uri: newUri,
            label: displayName,
            documentProvider: widget.documentProvider,
            cacheDerivedKey: shouldCacheDerivedKey,
            readOnly: _readOnly,
            cipherId: result.matchedCipherId,
            hashId: result.matchedHashId,
            containerFormat: result.containerFormat,
          );
          await ContainerRepository.instance.save(savedRecord);
        }
        widget.onMounted(finalContainer, record: savedRecord);
      }

      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      final isCancelled = e is PlatformException && e.code == 'CANCELLED';
      if (!isCancelled) {
        setState(() => _error = e is PlatformException ? (e.message ?? e.toString()) : e.toString());
      }
    } finally {
      if (mounted) {
        setState(() { _unlocking = false; _activeVolId = null; _progress = null; });
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final busy = _unlocking || _requestingPermission;
    final isReconnect = widget.existingRecord != null;

    final inputDecorationTheme = InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isReconnect ? 'Reconnect "${widget.existingRecord!.label}"' : 'Unlock USB Drive',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: _unlocking
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  color: cs.primary,
                  backgroundColor: cs.primaryContainer,
                ),
              )
            : null,
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: inputDecorationTheme,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loadingDevices)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  )
                else ...[
                  // Reconnect Drive Offline Banner
                  if (isReconnect && _reconnectTargetMissing) ...[
                    Card(
                      elevation: 0,
                      color: cs.tertiaryContainer.withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(color: cs.tertiary.withValues(alpha: 0.25)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.tertiaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.usb_off_rounded, size: 28, color: cs.onTertiaryContainer),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Couldn\'t find "${widget.existingRecord!.label}"',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.onTertiaryContainer,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Plug the drive back in and tap Retry, or select it below if it shows up under a different name.',
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onTertiaryContainer.withValues(alpha: 0.85),
                                height: 1.35,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _loadDevices,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Retry Connection'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Empty State: No Devices Found
                  if (_devices.isEmpty) ...[
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHigh,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.usb_off_rounded, size: 36, color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No USB Storage Detected',
                              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Connect an OTG flash drive to mount',
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _loadDevices,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Refresh Devices'),
                              style: FilledButton.styleFrom(shape: const StadiumBorder()),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // 1. Device list group
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12, left: 4),
                          child: Text(
                            'Select USB Drive',
                            style: textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        RadioGroup<UsbDeviceInfo>(
                          groupValue: _selected,
                          onChanged: (v) => setState(() => _selected = v),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _devices.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final d = _devices[index];
                              final deviceUri = 'usb:${d.deviceName}';
                              final isAlreadyMounted = widget.mountedUris.contains(deviceUri);
                              final isSelected = _selected?.deviceName == d.deviceName;
                              
                              return GestureDetector(
                                onTap: (busy || isAlreadyMounted) ? null : () => setState(() => _selected = d),
                                child: Card(
                                  elevation: 0,
                                  color: isAlreadyMounted
                                      ? cs.surfaceContainerLow.withValues(alpha: 0.5)
                                      : isSelected
                                          ? cs.primaryContainer.withValues(alpha: 0.15)
                                          : cs.surfaceContainerLow,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: BorderSide(
                                      color: isAlreadyMounted
                                          ? cs.outlineVariant.withValues(alpha: 0.2)
                                          : isSelected
                                              ? cs.primary
                                              : cs.outlineVariant.withValues(alpha: 0.35),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: isAlreadyMounted
                                                ? cs.surfaceContainer
                                                : isSelected
                                                    ? cs.primaryContainer
                                                    : cs.surfaceContainerHigh,
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          child: Icon(
                                            isAlreadyMounted
                                                ? Icons.lock_outline_rounded
                                                : Icons.usb_rounded,
                                            size: 22,
                                            color: isAlreadyMounted
                                                ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                                                : isSelected
                                                    ? cs.onPrimaryContainer
                                                    : cs.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                d.productName,
                                                style: textTheme.bodyLarge?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: isAlreadyMounted
                                                      ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                                                      : cs.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                isAlreadyMounted
                                                    ? 'Already active'
                                                    : d.hasPermission
                                                        ? 'Ready to unlock'
                                                        : 'Permission required',
                                                style: textTheme.bodySmall?.copyWith(
                                                  color: isAlreadyMounted
                                                      ? cs.error
                                                      : d.hasPermission
                                                          ? cs.primary
                                                          : cs.onSurfaceVariant,
                                                  fontWeight: isAlreadyMounted || d.hasPermission
                                                      ? FontWeight.w500
                                                      : null,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isAlreadyMounted) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: cs.surfaceContainerHigh,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              'Active',
                                              style: textTheme.labelSmall?.copyWith(
                                                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ] else ...[
                                          Radio<UsbDeviceInfo>(
                                            value: d,
                                            enabled: !busy,
                                            activeColor: cs.primary,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Auth View Switchers
                    if (_loadingAuth)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else ...[
                      // Read-only mode toggle
                      Material(
                        color: cs.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SwitchListTile(
                          value: _readOnly,
                          onChanged: busy ? null : (val) => setState(() => _readOnly = val),
                          title: Text(
                            'Read-only mode',
                            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Mount without allowing changes to this drive',
                            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          secondary: Icon(Icons.visibility_outlined, color: cs.primary),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Biometric Card
                      if (_unlockMethod == ContainerUnlockMethod.biometrics && !_showPasswordFallback) ...[
                        Card(
                          elevation: 0,
                          color: cs.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.fingerprint_rounded,
                                    size: 56,
                                    color: cs.primary,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Biometric Authentication',
                                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Authenticate to unlock and mount this USB device',
                                  style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 28),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => setState(() => _showPasswordFallback = true),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: const Text('Use Password'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: _tryBiometric,
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: const Text('Authenticate'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ]
                      // Pattern Card
                      else if (_unlockMethod == ContainerUnlockMethod.pattern && !_showPasswordFallback) ...[
                        Card(
                          elevation: 0,
                          color: cs.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Draw Unlock Pattern',
                                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _patternError ? 'Wrong pattern — try again' : 'Connect your pattern sequence to mount',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: _patternError ? cs.error : cs.onSurfaceVariant,
                                    fontWeight: _patternError ? FontWeight.bold : null,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                PatternLockView(
                                  key: ValueKey(_patternResetKey),
                                  onPatternComplete: _onPatternComplete,
                                  showError: _patternError,
                                ),
                                const SizedBox(height: 20),
                                OutlinedButton(
                                  onPressed: () => setState(() => _showPasswordFallback = true),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text('Use Password instead'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ]
                      else ...[
                        // Standard Password Form View
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          enabled: !busy,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: _isBitlocker
                                ? 'Enter password or recovery key'
                                : 'Enter USB partition password',
                            prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: cs.primary),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_passwordPrefilled)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Tooltip(
                                      message: 'Using saved password',
                                      child: Icon(
                                        Icons.bookmark_rounded,
                                        size: 20,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                PasswordVisibilityToggle(
                                  obscured: _obscure,
                                  onToggle: () => setState(() => _obscure = !_obscure),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Keyfiles Component
                        if (!_isBitlocker) ...[
                          KeyfilesPicker(
                            keyfiles: _keyfiles,
                            picking: _pickingKeyfiles,
                            onPick: _pickKeyfiles,
                            onRemove: _removeKeyfile,
                            enabled: !busy,
                          ),
                          if (_isLuks && _keyfiles.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6, left: 4),
                              child: Text(
                                'For LUKS containers the keyfile replaces the password.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                        ],

                        // Collapsible Advanced settings panel
                        if (!_isLuks && !_isBitlocker)
                          AdvancedParamsPanel(
                            pimController: _pimCtrl,
                            cipherId: _cipherId,
                            hashId: _hashId,
                            enabled: !busy,
                            onCipherChanged: (val) => setState(() => _cipherId = val),
                            onHashChanged: (val) => setState(() => _hashId = val),
                          ),
                        const SizedBox(height: 16),

                        // Remember Drive Toggle
                        if (!isReconnect) ...[
                          Material(
                            color: cs.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: SwitchListTile(
                              value: _remember,
                              onChanged: busy ? null : (val) => setState(() => _remember = val),
                              title: Text(
                                'Remember drive',
                                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Pin drive on dashboard for quick access',
                                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              secondary: Icon(Icons.push_pin_outlined, color: cs.primary),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          InlineErrorBanner(_error!),
                        ],
                        const SizedBox(height: 28),

                        // Unlock execution CTA
                        FilledButton(
                          onPressed: busy || _devices.isEmpty || _selected == null ? null : _unlock,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            shape: const StadiumBorder(),
                          ),
                          child: busy
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: cs.onPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        _unlocking ? _unlockProgressLabel : 'Requesting permission...',
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.titleMedium?.copyWith(
                                          color: cs.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  isReconnect ? 'Unlock & Mount' : 'Unlock Drive',
                                  style: textTheme.titleMedium?.copyWith(
                                      color: cs.onPrimary,
                                      fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        if (_unlocking && _activeVolId != null) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton(
                              onPressed: () => vaultExplorerApi.cancelUnlock(_activeVolId!),
                              child: const Text('Cancel Unlock'),
                            ),
                          ),
                        ],
                      ],
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