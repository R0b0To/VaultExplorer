import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../../services/vaultexplorer_api.dart';
import '../../services/app_settings_service.dart';
import '../../models/mounted_container.dart';
import '../../models/usb_device_info.dart';
import '../../utils/validation_utils.dart';
import '../../widgets/common_widgets.dart';
import '../lock/pattern_lock_view.dart';
import '../../../models/crypto_algorithms.dart';

class UsbUnlockSheet extends StatefulWidget {
  final void Function(MountedContainer container, {ContainerRecord? record}) onMounted;
  final bool documentProvider;
  final ContainerRecord? existingRecord;
  final String? prefillPassword;
  final void Function(MountedContainer container, ContainerRecord migratedRecord, String oldUri)? onReconnected;
  final List<String> mountedUris; // <--- Added validation parameter

  const UsbUnlockSheet({
    Key? key,
    required this.onMounted,
    this.documentProvider = false,
    this.existingRecord,
    this.prefillPassword,
    this.onReconnected,
    this.mountedUris = const [], // <--- Default value
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
  final List<KeyfileRef> _keyfiles = [];
  bool _pickingKeyfiles = false;

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

  String? get _expectedDeviceName {
    final uri = widget.existingRecord?.uri;
    if (uri == null || !uri.startsWith('usb:')) return null;
    return uri.substring(4);
  }

  bool get _passwordPrefilled =>
      widget.prefillPassword?.isNotEmpty == true &&
      _passwordCtrl.text == widget.prefillPassword;

  /// See UnlockSheet._unlockProgressLabel — identical logic, USB wording.
  String get _unlockProgressLabel {
    final p = _progress;
    if (p == null || p.total <= 0) return 'Decrypting drive...';
    final hashName = hashAlgorithmName(p.hashId);
    return p.total > 1
        ? 'Trying $hashName (${p.attempted} of ${p.total})…'
        : 'Trying $hashName…';
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
    }
    _loadDevicesFuture = _loadDevices();
    _initUnlockMethod();

    _onUnlockStarted = (volId) {
      if (mounted) setState(() => _activeVolId = volId);
    };
    _onUnlockProgress = (progress) {
      if (mounted && progress.volId == _activeVolId) {
        setState(() => _progress = progress);
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

      if (_unlockMethod == ContainerUnlockMethod.pattern) {
        _storedPatternHash = await ContainerRepository.instance.getPatternHash(record.uri);
      }

      if (mounted) setState(() => _loadingAuth = false);

      if (_unlockMethod == ContainerUnlockMethod.biometrics) {
        if (_loadDevicesFuture != null) {
          await _loadDevicesFuture;
        }
        if (mounted && _selected != null && !_reconnectTargetMissing) {
          _tryBiometric();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAuth = false);
    }
  }

  Future<void> _tryBiometric() async {
    final record = widget.existingRecord;
    if (record == null) return;
    
    if (_selected == null) {
      setState(() => _error = 'Select a USB drive first');
      return;
    }

    try {
      final localAuth = LocalAuthentication();
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
    // See the matching comment in unlock_sheet.dart's dispose().
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
            _selected = isAlreadyMounted ? null : d; // Guard: Do not autoselect already mounted targets
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
    
    // Guard Check: Block attempts to unlock a device already active in memory
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
        keyfilePaths: keyfilePaths,
      );

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
          pendingPassword: savedPassword,
          pendingPatternHash: savedPatternHash,
          cipherId: result.matchedCipherId,
          hashId: result.matchedHashId,
        );
        await ContainerRepository.instance.save(migrated);

        widget.onReconnected?.call(finalContainer, migrated, existing.uri);
      } else if (existing != null) {
        var effectiveExisting = existing;
        if (existing.cipherId != result.matchedCipherId ||
            existing.hashId != result.matchedHashId) {
          effectiveExisting = existing.copyWith(
            cacheDerivedKey: shouldCacheDerivedKey,
            cipherId: result.matchedCipherId,
            hashId: result.matchedHashId,
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
            cipherId: result.matchedCipherId,
            hashId: result.matchedHashId,
          );
          await ContainerRepository.instance.save(savedRecord);
        }
        widget.onMounted(finalContainer, record: savedRecord);
      }

      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      // A cancellation the user asked for isn't an error — just quietly
      // drop back to the form instead of showing an error banner.
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isReconnect ? 'Reconnect "${widget.existingRecord!.label}"' : 'Unlock USB Drive',
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                    color: cs.tertiaryContainer.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.tertiary.withOpacity(0.2)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
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
                              color: cs.onTertiaryContainer.withOpacity(0.8),
                              height: 1.3,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _loadDevices,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Retry connection'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
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
                            'No USB storage detected',
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
                            label: const Text('Refresh list'),
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
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _devices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                                  ? cs.surfaceContainerLow.withOpacity(0.5)
                                  : isSelected
                                      ? cs.primaryContainer.withOpacity(0.12)
                                      : cs.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: isAlreadyMounted
                                      ? cs.outlineVariant.withOpacity(0.2)
                                      : isSelected
                                          ? cs.primary
                                          : cs.outlineVariant.withOpacity(0.5),
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
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isAlreadyMounted
                                            ? Icons.lock_outline_rounded
                                            : Icons.usb_rounded,
                                        size: 22,
                                        color: isAlreadyMounted
                                            ? cs.onSurfaceVariant.withOpacity(0.5)
                                            : isSelected
                                                ? cs.onPrimaryContainer
                                                : cs.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            d.productName,
                                            style: textTheme.bodyLarge?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: isAlreadyMounted
                                                  ? cs.onSurfaceVariant.withOpacity(0.5)
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
                                            color: cs.onSurfaceVariant.withOpacity(0.7),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      Radio<UsbDeviceInfo>(
                                        value: d,
                                        groupValue: _selected,
                                        onChanged: busy ? null : (v) => setState(() => _selected = v),
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
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Auth View Switchers
                  if (_loadingAuth)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_unlockMethod == ContainerUnlockMethod.biometrics && !_showPasswordFallback) ...[
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(color: cs.outlineVariant.withOpacity(0.3)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer.withOpacity(0.4),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.fingerprint_rounded,
                                size: 64,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Biometric Authentication',
                              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Authenticate to unlock and mount this USB device',
                              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => setState(() => _showPasswordFallback = true),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
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
                                      padding: const EdgeInsets.symmetric(vertical: 16),
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
                  else if (_unlockMethod == ContainerUnlockMethod.pattern && !_showPasswordFallback) ...[
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(color: cs.outlineVariant.withOpacity(0.3)),
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
                            const SizedBox(height: 8),
                            Text(
                              _patternError ? 'Wrong pattern — try again' : 'Connect your pattern sequence to mount',
                              style: textTheme.bodyMedium?.copyWith(
                                color: _patternError ? cs.error : cs.onSurfaceVariant,
                                fontWeight: _patternError ? FontWeight.bold : null,
                              ),
                            ),
                            const SizedBox(height: 24),
                            PatternLockView(
                              key: ValueKey(_patternResetKey),
                              onPatternComplete: _onPatternComplete,
                              showError: _patternError,
                            ),
                            const SizedBox(height: 24),
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
                        hintText: 'Enter USB partition password',
                        prefixIcon: Icon(Icons.lock_outline_rounded, size: 22, color: cs.primary),
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
                        filled: true,
                        fillColor: cs.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: cs.primary, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Keyfiles Card Component
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.insert_drive_file_outlined, size: 20, color: cs.primary),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Keyfiles (optional)',
                                    style: textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              TextButton.icon(
                                onPressed: (busy || _pickingKeyfiles) ? null : _pickKeyfiles,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: _pickingKeyfiles
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Add file'),
                              ),
                            ],
                          ),
                          if (_keyfiles.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _keyfiles
                                  .map(
                                    (k) => InputChip(
                                      avatar: Icon(Icons.description_outlined, size: 16, color: cs.onSurfaceVariant),
                                      label: Text(
                                        k.displayName,
                                        style: textTheme.bodySmall,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onDeleted: busy ? null : () => _removeKeyfile(k),
                                      deleteIconColor: cs.error,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      backgroundColor: cs.surfaceContainerHigh,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            Text(
                              'No keyfiles attached',
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant.withOpacity(0.6),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Collapsible Advanced settings panel
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(
                          'Advanced parameters',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                        leading: Icon(Icons.tune_rounded, color: cs.primary),
                        childrenPadding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
                        ),
                        collapsedShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
                        ),
                        backgroundColor: cs.surfaceContainerLow,
                        collapsedBackgroundColor: cs.surfaceContainerLow,
                        children: [
                          TextField(
                            controller: _pimCtrl,
                            enabled: !busy,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'PIM  (leave blank for default)',
                              prefixIcon: const Icon(Icons.password_outlined, size: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                            initialValue: _cipherId,
                            decoration: InputDecoration(
                              labelText: 'Encryption Algorithm',
                              prefixIcon: const Icon(Icons.security_rounded, size: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                             items: CipherAlgo.dropdownItems(),
                              onChanged: (val) {
                                if (val != null) setState(() => _cipherId = val);
                              },
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                            initialValue: _hashId,
                            decoration: InputDecoration(
                              labelText: 'Hash Algorithm',
                              prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: HashAlgo.dropdownItems(),
                              onChanged: (val) {
                                if (val != null) setState(() => _hashId = val);
                              },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Remember Drive Toggle
                    if (!isReconnect) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                        ),
                        child: SwitchListTile(
                          value: _remember,
                          onChanged: busy ? null : (val) => setState(() => _remember = val),
                          title: Text(
                            'Remember drive',
                            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            'Pin drive on dashboard for quick access',
                            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          secondary: Icon(Icons.push_pin_outlined, color: cs.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _error!,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: cs.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),

                    // Unlock execution CTA
                    FilledButton(
                      onPressed: busy || _devices.isEmpty || _selected == null ? null : _unlock,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
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
                                      color: cs.onPrimary,
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
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}