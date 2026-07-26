import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import '../lock/widgets/pattern_lock_view.dart';

class UnlockSheet extends StatefulWidget {
  final void Function(MountedContainer container, {ContainerRecord? record}) onMounted;
  final String? initialUri;
  final String? initialName;
  final String? prefillPassword;
  final bool documentProvider;
  final List<String> mountedUris;

  const UnlockSheet({
    super.key,
    required this.onMounted,
    this.initialUri,
    this.initialName,
    this.prefillPassword,
    this.documentProvider = false,
    this.mountedUris = const [],
  });

  @override
  State<UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends State<UnlockSheet>
    with WidgetsBindingObserver, KeyfilePickerMixin {
  late TextEditingController _passwordCtrl;
  final _pimCtrl = TextEditingController();
  
  String? _selectedUri;
  String? _selectedName;
  bool _obscure = true;
  bool _loading = false;
  bool _remember = false;
  bool _readOnly = false;
  bool _hasAllStorageAccess = false;
  String? _error;
  int _cipherId = 255;
  int _hashId = 255;
  String _containerFormat = 'container';

  @override
  void onKeyfilePickError(String message) => setState(() => _error = message);

  bool get _isLuks => ContainerFormat.isLuksWire(_containerFormat);
  bool get _isCryptomator => ContainerFormat.isCryptomatorWire(_containerFormat);
  bool get _isGocryptfs => ContainerFormat.isGocryptfsWire(_containerFormat);
  bool get _isCryfs => ContainerFormat.isCryfsWire(_containerFormat);
  bool get _isBitlocker => ContainerFormat.isBitlockerWire(_containerFormat);
  bool get _isFolderVault => ContainerFormat.isFolderVaultWire(_containerFormat);

  int? _activeVolId;
  UnlockProgress? _progress;
  late final void Function(int) _onUnlockStarted;
  late final void Function(UnlockProgress) _onUnlockProgress;

  ContainerUnlockMethod _unlockMethod = ContainerUnlockMethod.password;
  bool _showPasswordFallback = false;
  bool _patternError = false;
  int _patternResetKey = 0;
  String? _storedPatternHash;
  bool _loadingAuth = true;
  bool _containerMissing = false;

  bool _isAuthenticating = false;

  bool get _passwordPrefilled =>
      widget.prefillPassword != null &&
      _passwordCtrl.text == widget.prefillPassword;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkStoragePermission();
    _passwordCtrl = TextEditingController(text: widget.prefillPassword ?? '');
    
    if (widget.initialUri != null) {
      _selectedUri = widget.initialUri;
      _selectedName = widget.initialName;
      _remember = true;
      vaultExplorerApi.warmContainer(widget.initialUri!);
    }
    _initUnlockMethod();

    _onUnlockStarted = (volId) {
      if (mounted) setState(() => _activeVolId = volId);
    };
    _onUnlockProgress = (progress) {
      if (mounted && progress.volId == _activeVolId) {
        setState(() {
          _progress = progress;
          if (progress.containerFormat.isNotEmpty && progress.containerFormat != 'unknown') {
            _containerFormat = progress.containerFormat;
          }
        });
      }
    };
    VaultExplorerApi.addUnlockStartedListener(_onUnlockStarted);
    VaultExplorerApi.addUnlockProgressListener(_onUnlockProgress);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_loading && _activeVolId != null) {
      vaultExplorerApi.cancelUnlock(_activeVolId!);
    }
    VaultExplorerApi.removeUnlockStartedListener(_onUnlockStarted);
    VaultExplorerApi.removeUnlockProgressListener(_onUnlockProgress);
    _passwordCtrl.dispose();
    _pimCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkStoragePermission();
    }
  }

  Future<void> _checkStoragePermission() async {
    const api = VaultExplorerApi();
    final hasAccess = await api.hasAllFilesAccess();
    if (mounted) {
      setState(() {
        _hasAllStorageAccess = hasAccess;
      });
    }
  }

  Future<void> _requestStoragePermission() async {
    const api = VaultExplorerApi();
    await api.requestAllFilesAccess();
    await _checkStoragePermission();
  }

  Future<void> _initUnlockMethod() async {
    if (widget.initialUri == null) {
      if (mounted) setState(() => _loadingAuth = false);
      return;
    }
    try {
      final records = await ContainerRepository.instance.loadAll();
      final record = records[widget.initialUri];
      if (record == null) {
        if (mounted) setState(() => _loadingAuth = false);
        return;
      }
      
      _containerFormat = record.containerFormat;
      if (record.keyfiles.isNotEmpty) {
        keyfiles.addAll(record.keyfiles.map((k) => (uri: k['uri']!, displayName: k['name']!)));
      }

      var exists = true;
      try {
        exists = await vaultExplorerApi.documentExists(widget.initialUri!);
      } catch (_) {
        exists = true;
      }

      if (!exists) {
        if (mounted) {
          setState(() {
            _containerMissing = true;
            _loadingAuth = false;
          });
        }
        return;
      }

      _unlockMethod = record.unlockMethod;
      _cipherId = record.cipherId;
      _hashId = record.hashId;
      _readOnly = record.readOnly;
      
      if (_unlockMethod == ContainerUnlockMethod.pattern) {
        _storedPatternHash = await ContainerRepository.instance.getPatternHash(
          widget.initialUri!,
        );
      }
      if (mounted) setState(() => _loadingAuth = false);
      if (_unlockMethod == ContainerUnlockMethod.biometrics) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          _tryBiometric();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAuth = false);
    }
  }

  Future<void> _relocateContainer() async {
    final oldUri = widget.initialUri;
    if (oldUri == null) return;
    try {
      String newUri;
      String newDisplayName;
      String detectedFormat = _containerFormat;

      if (_isFolderVault) {
        final picked = await vaultExplorerApi.pickCryptomatorVault();
        if (picked == null || !mounted) return;
        final format = picked.format;
        if (format == null) {
          setState(() => _error = 'No masterkey.cryptomator, gocryptfs.conf, or cryfs.config found in that folder.');
          return;
        }
        detectedFormat = format;
        newUri = picked.uri;
        newDisplayName = picked.displayName;
      } else {
        final picked = await vaultExplorerApi.pickContainer();
        if (picked == null || !mounted) return;
        newUri = picked.uri;
        newDisplayName = picked.displayName;
      }

      setState(() => _loadingAuth = true);
      
      final records = await ContainerRepository.instance.loadAll();
      final existing = records[oldUri];
      if (existing == null) {
        if (mounted) {
          setState(() {
            _loadingAuth = false;
            _error = 'Saved settings for this container could not be found.';
          });
        }
        return;
      }

      final savedPassword = await ContainerRepository.instance.getPassword(oldUri);
      final savedPatternHash = await ContainerRepository.instance.getPatternHash(oldUri);
      await ContainerRepository.instance.remove(oldUri);
      
      final migrated = ContainerRecord(
        uri: newUri,
        label: existing.label,
        rememberPassword: existing.rememberPassword,
        unlockMethod: existing.unlockMethod,
        autoCloseMins: existing.autoCloseMins,
        documentProvider: existing.documentProvider,
        thumbnailCacheMode: existing.thumbnailCacheMode,
        cacheDerivedKey: existing.cacheDerivedKey,
        pendingPassword: savedPassword,
        pendingPatternHash: savedPatternHash,
        cipherId: existing.cipherId,
        hashId: existing.hashId,
        containerFormat: detectedFormat,
        keyfiles: existing.keyfiles,
      );
      
      await ContainerRepository.instance.save(migrated);
      
      if (!mounted) return;
      setState(() {
        _selectedUri = migrated.uri;
        _selectedName = newDisplayName;
        _unlockMethod = migrated.unlockMethod;
        _cipherId = migrated.cipherId;
        _hashId = migrated.hashId;
        _containerFormat = migrated.containerFormat;
        _storedPatternHash = savedPatternHash;
        _containerMissing = false;
        _loadingAuth = false;
      });

      if (_unlockMethod == ContainerUnlockMethod.biometrics) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          _tryBiometric();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingAuth = false;
          _error = 'Could not update the container location: $e';
        });
      }
    }
  }

  Future<void> _tryBiometric() async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;
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
        localizedReason: 'Authenticate to unlock container',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );

      if (ok && mounted) {
        final records = await ContainerRepository.instance.loadAll();
        final record = records[widget.initialUri!];
        
        final appSettings = await AppSettingsService.loadSettings();
        final shouldCacheGoingForward =
            (record?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled;
        final shouldPreloadCachedKey = record?.cacheDerivedKey ?? false;

        final cachedKey = shouldPreloadCachedKey
            ? await vaultExplorerApi.loadDerivedKey(widget.initialUri!)
            : null;

        debugPrint('unlock: biometric cached-key present=${cachedKey != null && cachedKey.isNotEmpty} for ${widget.initialUri}');

        if (cachedKey != null && cachedKey.isNotEmpty) {
          await _unlock(
            preservedKey: cachedKey,
            shouldCacheDerivedKeyOverride: shouldCacheGoingForward,
          );
          return;
        }

        final pw = await ContainerRepository.instance.getPassword(widget.initialUri!);
        if (pw != null || keyfiles.isNotEmpty) {
          _passwordCtrl.text = pw ?? '';
          await _unlock(shouldCacheDerivedKeyOverride: shouldCacheGoingForward, passwordOverride: pw ?? '');
        } else {
          setState(() {
            _error = 'Initializing secure credentials. Please unlock manually once to authorize biometric access.';
            _showPasswordFallback = true;
          });
        }
      }
    } on PlatformException catch (e) {
      if (e.code == 'auth_in_progress' ||
          e.code == 'AuthenticationInProgress' ||
          (e.message?.contains('Authentication in progress') ?? false)) {
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
    if (_storedPatternHash == null) {
      setState(() {
        _error = 'No pattern configured. Please enter password manually.';
        _showPasswordFallback = true;
      });
      return;
    }

    final attempt = hashPattern(pattern);
    if (attempt == _storedPatternHash) {
      final records = await ContainerRepository.instance.loadAll();
      final record = records[widget.initialUri!];
      
      final appSettings = await AppSettingsService.loadSettings();
      final shouldCacheGoingForward =
          (record?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled;
      final shouldPreloadCachedKey = record?.cacheDerivedKey ?? false;

      final cachedKey = shouldPreloadCachedKey
          ? await vaultExplorerApi.loadDerivedKey(widget.initialUri!)
          : null;

      if (cachedKey != null && cachedKey.isNotEmpty) {
        await _unlock(preservedKey: cachedKey, shouldCacheDerivedKeyOverride: shouldCacheGoingForward);
        return;
      }

      final pw = await ContainerRepository.instance.getPassword(widget.initialUri!);
      if (pw != null || keyfiles.isNotEmpty) {
        _passwordCtrl.text = pw ?? '';
        await _unlock(shouldCacheDerivedKeyOverride: shouldCacheGoingForward, passwordOverride: pw ?? '');
      } else {
        setState(() {
          _error = 'Initializing secure credentials. Please unlock manually once to authorize pattern access.';
          _showPasswordFallback = true;
        });
      }
    } else {
      setState(() => _patternError = true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() { _patternError = false; _patternResetKey++; });
      });
    }
  }

  Future<void> _pickFile() async {
    if (widget.initialUri != null) return;
    try {
      if (_isFolderVault) {
        final result = await vaultExplorerApi.pickCryptomatorVault();
        if (result == null) return;

        if (widget.mountedUris.contains(result.uri)) {
          setState(() {
            _error = 'This container is already mounted.';
            _selectedUri = null;
            _selectedName = null;
          });
          return;
        }

        final detectedFormat = result.format;
        if (detectedFormat == null) {
          setState(() {
            _error = 'No masterkey.cryptomator, gocryptfs.conf, or cryfs.config found in that folder.';
            _selectedUri = null;
            _selectedName = null;
          });
          return;
        }

        setState(() {
          _selectedUri = result.uri;
          _selectedName = result.displayName;
          _containerFormat = detectedFormat;
          _error = null;
        });
        return;
      }

      final result = await vaultExplorerApi.pickContainer();
      if (result != null) {
        if (widget.mountedUris.contains(result.uri)) {
          setState(() {
            _error = 'This container is already mounted.';
            _selectedUri = null;
            _selectedName = null;
          });
          return;
        }
        setState(() {
          _selectedUri = result.uri;
          _selectedName = result.displayName;
          _containerFormat = 'container';
          _error = null;
        });
        vaultExplorerApi.warmContainer(result.uri);
      }
    } catch (e) {
      setState(() => _error = 'File picker failed: $e');
    }
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
    if (_selectedUri == null) {
      setState(() => _error = 'Select a container first');
      return;
    }
    
    if (widget.mountedUris.contains(_selectedUri)) {
      setState(() => _error = 'This container is already mounted.');
      return;
    }

    var effectivePassword = (passwordOverride ?? _passwordCtrl.text).trim();
    if (effectivePassword.isEmpty && preservedKey == null && keyfiles.isEmpty) {
      setState(() => _error = 'Password or keyfiles required');
      return;
    }

    if (_isCryfs && !_hasAllStorageAccess) {
      final grant = await showAppConfirmDialog(
        context,
        title: 'Slow Performance Warning',
        message: 'Direct Storage Access is currently disabled.\n\nCryFS stores files across thousands of small blocks. Opening non-empty CryFS vaults via Android SAF will be very slow.\n\nWould you like to open Settings to grant "All Files Access" for fast speed?',
        confirmLabel: 'Open Settings',
        cancelLabel: 'Unlock Anyway',
      );
      if (grant) {
        await _requestStoragePermission();
        return;
      }
    }

    if (_isCryptomator || _isGocryptfs || _isCryfs) {
      setState(() {
        _loading = true;
        _error = null;
      });

      try {
        final name = _selectedName ?? 'Vault';
        ContainerRecord? cryfsRecord;
        var shouldCacheDerivedKey = false;
        Uint8List? resolvedPreservedKey;

        if (_isCryfs) {
          final records = await ContainerRepository.instance.loadAll();
          cryfsRecord = records[_selectedUri!];
          final appSettings = await AppSettingsService.loadSettings();
          final isKnownRecord = cryfsRecord != null;
          
          shouldCacheDerivedKey = shouldCacheDerivedKeyOverride ??
              ((isKnownRecord || _remember) &&
                  ((cryfsRecord?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled));

          final shouldPreloadCachedKey = preservedKey == null &&
              _unlockMethod == ContainerUnlockMethod.rememberPassword &&
              _passwordPrefilled &&
              (cryfsRecord?.cacheDerivedKey ?? false);

          resolvedPreservedKey = preservedKey ??
              (shouldPreloadCachedKey
                  ? await vaultExplorerApi.loadDerivedKey(_selectedUri!)
                  : null);
        }

        var result = _isCryptomator
            ? await vaultExplorerApi.unlockCryptomatorVault(
                _selectedUri!,
                effectivePassword,
                displayName: name,
                documentProvider: widget.documentProvider,
                readOnly: _readOnly,
              )
            : _isGocryptfs
                ? await vaultExplorerApi.unlockGocryptfsVault(
                    _selectedUri!,
                    effectivePassword,
                    displayName: name,
                    documentProvider: widget.documentProvider,
                    readOnly: _readOnly,
                  )
                : resolvedPreservedKey == null
                    ? await vaultExplorerApi.unlockCryfsVault(
                        _selectedUri!,
                        effectivePassword,
                        displayName: name,
                        documentProvider: widget.documentProvider,
                        readOnly: _readOnly,
                        cacheDerivedKey: shouldCacheDerivedKey,
                      )
                    : await _unlockSwallowingStaleAuthFail(() => vaultExplorerApi.unlockCryfsVault(
                          _selectedUri!,
                          effectivePassword,
                          displayName: name,
                          documentProvider: widget.documentProvider,
                          readOnly: _readOnly,
                          preservedKey: resolvedPreservedKey,
                          cacheDerivedKey: shouldCacheDerivedKey,
                        ));

        if (result == null && _isCryfs && resolvedPreservedKey != null) {
          await vaultExplorerApi.clearDerivedKey(_selectedUri!);
          if (effectivePassword.isEmpty) {
            effectivePassword =
                (await ContainerRepository.instance.getPassword(_selectedUri!))?.trim() ?? '';
          }
          if (effectivePassword.isNotEmpty) {
            result = await vaultExplorerApi.unlockCryfsVault(
              _selectedUri!,
              effectivePassword,
              displayName: name,
              documentProvider: widget.documentProvider,
              readOnly: _readOnly,
              cacheDerivedKey: shouldCacheDerivedKey,
            );
          }
        }

        if (result == null) {
          setState(() => _error = 'Incorrect password or invalid vault');
          return;
        }

        ContainerRecord? savedRecord;
        if (_remember && widget.initialUri == null) {
          savedRecord = ContainerRecord(
            uri: _selectedUri!,
            label: name,
            rememberPassword: false,
            cacheDerivedKey: _isCryfs ? shouldCacheDerivedKey : false,
            readOnly: _readOnly,
            containerFormat: result.containerFormat,
            documentProvider: widget.documentProvider,
          );
          await ContainerRepository.instance.save(savedRecord);
        } else if (widget.initialUri != null) {
          final records = await ContainerRepository.instance.loadAll();
          savedRecord = records[widget.initialUri];
          if (_isCryfs &&
              savedRecord != null &&
              savedRecord.cacheDerivedKey != shouldCacheDerivedKey) {
            savedRecord = savedRecord.copyWith(cacheDerivedKey: shouldCacheDerivedKey);
            await ContainerRepository.instance.save(savedRecord);
          }
        }

        widget.onMounted(
          MountedContainer(
            uri: _selectedUri!,
            displayName: name,
            volId: result.volId,
            rootFiles: result.files,
            mountedAt: DateTime.now(),
            totalSpace: -1,
            freeSpace: -1,
            readOnly: _readOnly,
            containerFormat: result.containerFormat,
          ),
          record: savedRecord,
        );

        HapticFeedback.lightImpact();
        TextInput.finishAutofillContext(shouldSave: false);
        if (mounted) Navigator.pop(context);
      } on PlatformException catch (e) {
        if (e.code != 'CANCELLED') {
          setState(() => _error = e.message ?? 'Unknown error');
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    setState(() { _loading = true; _error = null; _activeVolId = null; _progress = null; });

    try {
      final pim = clampPim(_pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0);
      final name = _selectedName ?? 'Container';
      final keyfilePaths = keyfiles.map((k) => k.uri).toList();

      final records = await ContainerRepository.instance.loadAll();
      final record = records[_selectedUri!];
      final appSettings = await AppSettingsService.loadSettings();
      
      final isKnownRecord = record != null;
      final shouldCacheDerivedKey = shouldCacheDerivedKeyOverride ??
          ((isKnownRecord || _remember) &&
              ((record?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled));

      final shouldPreloadCachedKey = preservedKey == null &&
          _unlockMethod == ContainerUnlockMethod.rememberPassword &&
          _passwordPrefilled &&
          (record?.cacheDerivedKey ?? false);

      final resolvedPreservedKey = preservedKey ??
          (shouldPreloadCachedKey
              ? await vaultExplorerApi.loadDerivedKey(_selectedUri!)
              : null);

      debugPrint('unlock: method=$_unlockMethod shouldCacheDerivedKey=$shouldCacheDerivedKey preservedKeyLen=${resolvedPreservedKey?.length ?? 0}');

      var result = resolvedPreservedKey == null
          ? await vaultExplorerApi.unlockContainer(
              _selectedUri!,
              effectivePassword,
              pim,
              displayName: name,
              documentProvider: widget.documentProvider,
              cipherId: _cipherId,
              hashId: _hashId,
              preservedKey: resolvedPreservedKey,
              cacheDerivedKey: shouldCacheDerivedKey,
              keyfilePaths: keyfilePaths,
              readOnly: _readOnly,
            )
          : await _unlockSwallowingStaleAuthFail(() => vaultExplorerApi.unlockContainer(
              _selectedUri!,
              effectivePassword,
              pim,
              displayName: name,
              documentProvider: widget.documentProvider,
              cipherId: _cipherId,
              hashId: _hashId,
              preservedKey: resolvedPreservedKey,
              cacheDerivedKey: shouldCacheDerivedKey,
              keyfilePaths: keyfilePaths,
              readOnly: _readOnly,
            ));

      if (result == null && resolvedPreservedKey != null) {
        await vaultExplorerApi.clearDerivedKey(_selectedUri!);
        if (effectivePassword.isEmpty) {
          effectivePassword =
              (await ContainerRepository.instance.getPassword(_selectedUri!))?.trim() ?? '';
        }
        if (effectivePassword.isNotEmpty || keyfilePaths.isNotEmpty) {
          result = await vaultExplorerApi.unlockContainer(
            _selectedUri!,
            effectivePassword,
            pim,
            displayName: name,
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

      if (result != null) {
        await AppSecureStorage.instance.write(key: 'temp_pw_$_selectedUri', value: effectivePassword);

        ContainerRecord? savedRecord;
        final newKeyfiles = keyfiles.map((k) => {'uri': k.uri, 'name': k.displayName}).toList();

        if (_remember && widget.initialUri == null) {
          final newRecord = ContainerRecord(
            uri: _selectedUri!,
            label: name,
            rememberPassword: false,
            cacheDerivedKey: shouldCacheDerivedKey,
            readOnly: _readOnly,
            cipherId: result.matchedCipherId,
            hashId: result.matchedHashId,
            containerFormat: result.containerFormat,
            documentProvider: widget.documentProvider,
            keyfiles: newKeyfiles,
          );
          await ContainerRepository.instance.save(newRecord);
          savedRecord = newRecord;
        } else if (widget.initialUri != null) {
          final records = await ContainerRepository.instance.loadAll();
          final existing = records[widget.initialUri];
          if (existing != null) {
            final updated = existing.copyWith(
              cacheDerivedKey: shouldCacheDerivedKey,
              cipherId: result.matchedCipherId,
              readOnly: _readOnly,
              hashId: result.matchedHashId,
              containerFormat: result.containerFormat,
              keyfiles: newKeyfiles,
            );
            await ContainerRepository.instance.save(updated);
            savedRecord = updated;
          }
        }

        widget.onMounted(
          MountedContainer(
            uri: _selectedUri!,
            displayName: name,
            volId: result.volId,
            rootFiles: result.files,
            mountedAt: DateTime.now(),
            totalSpace: 0,
            freeSpace: 0,
            readOnly: _readOnly,
            containerFormat: result.containerFormat,
          ),
          record: savedRecord,
        );

        HapticFeedback.lightImpact();
        TextInput.finishAutofillContext(shouldSave: false);
        if (mounted) Navigator.pop(context);
      } else {
        setState(() => _error = 'Incorrect password or invalid container');
      }
    } on PlatformException catch (e) {
      if (e.code != 'CANCELLED') {
        setState(() => _error = e.message ?? 'Unknown error');
      }
    } finally {
      if (mounted) {
        setState(() { _loading = false; _activeVolId = null; _progress = null; });
      }
    }
  }

  bool get _showPasswordUI {
    if (_showPasswordFallback) return true;
    if (widget.initialUri == null) return true;
    return _unlockMethod == ContainerUnlockMethod.password ||
        _unlockMethod == ContainerUnlockMethod.rememberPassword;
  }

  String get _unlockProgressLabel {
    final p = _progress;
    if (p == null || p.total <= 0) return 'Decrypting...';

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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final inputDecorationTheme = InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
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

    return PopScope(
      canPop: !_loading,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _loading && _activeVolId != null) {
          vaultExplorerApi.cancelUnlock(_activeVolId!);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHigh,
          title: Text(
            widget.initialUri != null ? 'Unlock Container' : 'Mount Container',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: _loading
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.initialUri == null) ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'container',
                          label: Text('Container File'),
                          icon: Icon(Icons.folder_zip_rounded),
                        ),
                        ButtonSegment(
                          value: 'directory_vault',
                          label: Text('Folder Vault'),
                          icon: Icon(Icons.folder_shared_rounded),
                        ),
                      ],
                      selected: {
                        _isFolderVault ? 'directory_vault' : 'container',
                      },
                      onSelectionChanged: _loading
                          ? null
                          : (sel) => setState(() {
                                _containerFormat = sel.first;
                                _selectedUri = null;
                                _selectedName = null;
                                _error = null;
                              }),
                    ),
                    const SizedBox(height: 16),
                  ],

                  GestureDetector(
                    onTap: _loading ? null : _pickFile,
                    child: Card(
                      elevation: 0,
                      color: _selectedUri != null
                          ? cs.primaryContainer.withValues(alpha: 0.15)
                          : cs.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: _selectedUri != null
                              ? cs.primary
                              : cs.outlineVariant.withValues(alpha: 0.35),
                          width: _selectedUri != null ? 1.5 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: _selectedUri != null
                                    ? cs.primaryContainer
                                    : cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.center,
                              child: ContainerFormatIcon(
                                format: _selectedUri != null
                                    ? ContainerFormat.fromWire(_containerFormat)
                                    : ContainerFormat.directoryVault,
                                color: _selectedUri != null
                                    ? cs.onPrimaryContainer
                                    : cs.onSurfaceVariant,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedUri != null
                                        ? (_isLuks
                                            ? 'LUKS Container'
                                            : _isCryptomator
                                                ? 'Cryptomator Vault'
                                                : _isGocryptfs
                                                    ? 'Gocryptfs Vault'
                                                    : _isCryfs
                                                        ? 'CryFS Vault'
                                                        : _isBitlocker
                                                            ? 'BitLocker Drive'
                                                            : _containerFormat == 'veracrypt'
                                                                ? 'VeraCrypt Container'
                                                                : 'Encrypted Container')
                                        : (_isFolderVault
                                            ? 'Cryptomator | Gocryptfs | CryFS'
                                            : 'VeraCrypt | LUKS | BitLocker'),
                                    style: textTheme.labelMedium?.copyWith(
                                      color: _selectedUri != null
                                          ? cs.primary
                                          : cs.onSurfaceVariant,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedName ??
                                        (_isFolderVault
                                            ? 'Tap to select vault folder…'
                                            : 'Tap to select container file…'),
                                    style: textTheme.bodyLarge?.copyWith(
                                      color: _selectedUri != null
                                          ? cs.onSurface
                                          : cs.onSurfaceVariant,
                                      fontWeight: _selectedUri != null
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (_selectedUri != null && widget.initialUri == null) ...[
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: _loading
                                    ? null
                                    : () => setState(() {
                                          _selectedUri = null;
                                          _selectedName = null;
                                          _containerFormat = _isFolderVault ? 'directory_vault' : 'container';
                                        }),
                                style: IconButton.styleFrom(
                                  backgroundColor: cs.surfaceContainerHigh,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ] else if (_selectedUri == null) ...[
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHigh,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  color: cs.onSurfaceVariant,
                                  size: 18,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_isFolderVault && !_hasAllStorageAccess) ...[
                    InlineBanner(
                      _isCryfs
                          ? 'CryFS vaults use thousands of small block files. Without Direct Storage Access, performance will be significantly slower.'
                          : 'Direct Storage Access is disabled. Opening and reading files in folder vaults may be slower.',
                      tone: AppBannerTone.warning,
                      icon: Icons.speed_rounded,
                      trailing: TextButton(
                        onPressed: _requestStoragePermission,
                        child: const Text('Enable'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_loadingAuth)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    )
                  else if (_containerMissing) ...[
                    Card(
                      elevation: 0,
                      color: cs.errorContainer.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.errorContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.find_in_page_outlined,
                                    color: cs.error,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Container Missing',
                                        style: textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: cs.onErrorContainer,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'File path could not be resolved',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: cs.onErrorContainer.withValues(alpha: 0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'The container file may have been moved, deleted, or its host storage is currently disconnected.',
                              style: textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonal(
                                    onPressed: () {
                                      setState(() {
                                        _loadingAuth = true;
                                        _containerMissing = false;
                                      });
                                      _initUnlockMethod();
                                    },
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      backgroundColor: cs.surfaceContainerHighest,
                                      foregroundColor: cs.primary,
                                    ),
                                    child: const Text('Retry'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _relocateContainer,
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: const Text('Locate File'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]
                  else if (_unlockMethod == ContainerUnlockMethod.biometrics && !_showPasswordFallback) ...[
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerHigh,
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
                              'Biometric Unlock',
                              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Authenticate to securely mount the container',
                              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 28),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonal(
                                    onPressed: () => setState(() => _showPasswordFallback = true),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      backgroundColor: cs.surfaceContainerHighest,
                                      foregroundColor: cs.primary,
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
                  else if (_unlockMethod == ContainerUnlockMethod.pattern && !_showPasswordFallback) ...[
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerHigh,
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
                              _patternError ? 'Wrong pattern — try again' : 'Connect your pattern sequence',
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
                            FilledButton.tonal(
                              onPressed: () => setState(() => _showPasswordFallback = true),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                backgroundColor: cs.surfaceContainerHighest,
                                foregroundColor: cs.primary,
                              ),
                              child: const Text('Use Password instead'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]
                  else if (_showPasswordUI) ...[
                    AutofillGroup(
                      child: SectionCard(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: TextField(
                              controller: _passwordCtrl,
                              obscureText: _obscure,
                              autofocus: widget.initialUri != null && widget.prefillPassword?.isEmpty != false,
                              onChanged: (_) => setState(() {}),
                              keyboardType: TextInputType.visiblePassword,
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: cs.surfaceContainerHighest,
                                labelText: 'Password',
                                hintText: _isFolderVault
                                    ? 'Enter vault password'
                                    : _isBitlocker
                                        ? 'Enter password or recovery key'
                                        : 'Enter container password',
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
                          ),
                          if (!_isFolderVault && !_isBitlocker)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  KeyfilesPicker(
                                    keyfiles: keyfiles,
                                    picking: pickingKeyfiles,
                                    onPick: pickKeyfiles,
                                    onRemove: removeKeyfile,
                                  ),
                                  if (_isLuks && keyfiles.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'For LUKS containers the keyfile replaces the password.',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (!_isLuks && !_isFolderVault && !_isBitlocker)
                            AdvancedParamsPanel(
                              pimController: _pimCtrl,
                              cipherId: _cipherId,
                              hashId: _hashId,
                              enabled: !_loading,
                              onCipherChanged: (val) => setState(() => _cipherId = val),
                              onHashChanged: (val) => setState(() => _hashId = val),
                            ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: _readOnly,
                            onChanged: _loading ? null : (val) => setState(() => _readOnly = val),
                            title: Text(
                              'Read-only mode',
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Mount without allowing changes to this container',
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.visibility_outlined, color: cs.primary),
                          ),
                          if (widget.initialUri == null)
                            SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              value: _remember,
                              onChanged: (val) => setState(() => _remember = val),
                              title: Text(
                                'Remember container',
                                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'Pin container on dashboard for quick access',
                                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              secondary: Icon(Icons.push_pin_outlined, color: cs.primary),
                            ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      InlineErrorBanner(_error!),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _unlock,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: const StadiumBorder(),
                      ),
                      child: _loading
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
                                    _unlockProgressLabel,
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
                              _isFolderVault ? 'Unlock Vault' : 'Unlock Container',
                              style: textTheme.titleMedium?.copyWith(
                                color: cs.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    if (_loading && _activeVolId != null) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: () => vaultExplorerApi.cancelUnlock(_activeVolId!),
                          child: const Text('Cancel Unlock'),
                        ),
                      ),
                    ],
                  ] else if (_error != null) ...[
                    const SizedBox(height: 16),
                    InlineErrorBanner(_error!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}