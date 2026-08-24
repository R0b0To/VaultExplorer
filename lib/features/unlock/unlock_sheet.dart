import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'unlock_biometric_mixin.dart';
import 'unlock_biometric_source.dart';
import '../lock/widgets/pattern_lock_view.dart';
import '../lock/widgets/pin_lock_view.dart';

/// Which credential-entry UI is currently active. Computed once via
/// [_UnlockSheetState._credentialState] and reused everywhere the layout
/// needs to know "are we in the password-entry state" -- so the
/// credential card, the advanced-settings pane, and the unlock button
/// can never disagree about which state they're rendering for.
enum _UnlockCredentialState {
  loading,
  missing,
  biometric,
  pattern,
  pin,
  password,
  fallbackError,
  none,
}

class UnlockSheet extends StatefulWidget {
  final void Function(MountedContainer container, {ContainerRecord? record}) onMounted;
  final String? initialUri;
  final String? initialName;
  final String? prefillPassword;
  final bool documentProvider;
  final List<String> autoMountFolders;
  final List<String> mountedUris;

  const UnlockSheet({
    super.key,
    required this.onMounted,
    this.initialUri,
    this.initialName,
    this.prefillPassword,
    this.documentProvider = false,
    this.autoMountFolders = const [],
    this.mountedUris = const [],
  });

  @override
  State<UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends State<UnlockSheet>
    with WidgetsBindingObserver, KeyfilePickerMixin, UnlockBiometricMixin<UnlockSheet>
    implements UnlockBiometricSource {
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
  bool _protectHiddenVolume = false;
  final _hiddenPasswordCtrl = TextEditingController();
  final _hiddenPimCtrl = TextEditingController();
  bool _hiddenObscure = true;
  int _hiddenCipherId = 255;
  int _hiddenHashId = 255;
  late final _hiddenKeyfilesController = KeyfilePickerController(
    notify: () { if (mounted) setState(() {}); },
    onError: (msg) { if (mounted) setState(() => _error = msg ?? context.l10n.couldNotPickKeyfiles); },
  );

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
  bool _pinError = false;
  int _pinResetKey = 0;
  String? _storedPinHash;
  bool _loadingAuth = true;
  bool _containerMissing = false;
  bool _isAuthenticating = false;

  @override
  UnlockBiometricSource get unlockSource => this;

  @override
  bool get isAuthenticating => _isAuthenticating;

  @override
  set isAuthenticating(bool value) => _isAuthenticating = value;

  @override
  String? get unlockError => _error;

  @override
  set unlockError(String? value) => _error = value;

  @override
  bool get showPasswordFallback => _showPasswordFallback;

  @override
  set showPasswordFallback(bool value) => _showPasswordFallback = value;

  @override
  bool get patternError => _patternError;

  @override
  set patternError(bool value) => _patternError = value;

  @override
  int get patternResetKey => _patternResetKey;

  @override
  set patternResetKey(int value) => _patternResetKey = value;

  @override
  String? get storedPatternHash => _storedPatternHash;

  @override
  bool get pinError => _pinError;

  @override
  set pinError(bool value) => _pinError = value;

  @override
  int get pinResetKey => _pinResetKey;

  @override
  set pinResetKey(int value) => _pinResetKey = value;

  @override
  String? get storedPinHash => _storedPinHash;

  @override
  TextEditingController get passwordCtrl => _passwordCtrl;

  @override
  Future<void> performUnlock({
    Uint8List? preservedKey,
    bool? shouldCacheDerivedKeyOverride,
    String? passwordOverride,
    List<String>? keyfilePathsOverride,
  }) =>
      _unlock(
        preservedKey: preservedKey,
        shouldCacheDerivedKeyOverride: shouldCacheDerivedKeyOverride,
        passwordOverride: passwordOverride,
        keyfilePathsOverride: keyfilePathsOverride,
      );

  @override
  ({bool ready, String? blockMessage}) get preAuthReadiness => (ready: true, blockMessage: null);

  @override
  bool get isReadyForPattern => true;

  @override
  bool get isReadyForPin => true;

  @override
  Future<ContainerRecord?> resolveRecord() async {
    final records = await ContainerRepository.instance.loadAll();
    return records[widget.initialUri!];
  }

  @override
  String? get derivedKeyIdentifier => widget.initialUri;

  @override
  String get containerUri => widget.initialUri!;

  @override
  String get biometricPromptSubject => context.l10n.biometricSubjectContainer;

  @override
  String get noSavedCredentialsForBiometricMessage =>
      context.l10n.initSecureCredsBiometricMessage;

  @override
  String get noSavedCredentialsForPatternMessage =>
      context.l10n.initSecureCredsPatternMessage;

  @override
  String get noSavedCredentialsForPinMessage =>
      context.l10n.initSecureCredsPinMessage;

  @override
  String get debugLogTag => 'unlock';

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
    _hiddenPasswordCtrl.dispose();
    _hiddenPimCtrl.dispose();
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
      VeLog.d('UnlockSheet', '_initUnlockMethod: No initialUri (fresh container selection mode)');
      if (mounted) setState(() => _loadingAuth = false);
      return;
    }
    VeLog.d('UnlockSheet', '_initUnlockMethod for saved container: uri=${VeLog.censorUri(widget.initialUri)}');
    try {
      final records = await ContainerRepository.instance.loadAll();
      final record = records[widget.initialUri];
      if (record == null) {
        VeLog.w('UnlockSheet', '_initUnlockMethod: No record found in ContainerRepository for uri=${VeLog.censorUri(widget.initialUri)}');
        if (mounted) setState(() => _loadingAuth = false);
        return;
      }
      _containerFormat = record.containerFormat;
      VeLog.d('UnlockSheet', '_initUnlockMethod: record loaded: format=${record.containerFormat}, method=${record.unlockMethod}, keyfiles=${record.keyfiles.length}');
      if (record.unlockMethod == ContainerUnlockMethod.rememberPassword &&
          record.keyfiles.isNotEmpty) {
        keyfiles.addAll(record.keyfiles.map((k) => (uri: k['uri']!, displayName: k['name']!)));
      }
      var exists = true;
      try {
        exists = await vaultExplorerApi.documentExists(widget.initialUri!);
        VeLog.d('UnlockSheet', '_initUnlockMethod: documentExists(${VeLog.censorUri(widget.initialUri)}) => $exists');
      } catch (e) {
        VeLog.w('UnlockSheet', '_initUnlockMethod: documentExists check threw error: $e');
        exists = true;
      }
      if (!exists) {
        VeLog.w('UnlockSheet', '_initUnlockMethod: container missing at URI: ${VeLog.censorUri(widget.initialUri)}');
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
      if (_unlockMethod == ContainerUnlockMethod.pin) {
        _storedPinHash = await ContainerRepository.instance.getPinHash(
          widget.initialUri!,
        );
      }
      if (mounted) setState(() => _loadingAuth = false);
      if (_unlockMethod == ContainerUnlockMethod.biometrics) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          tryBiometric();
        }
      }
    } catch (e) {
      VeLog.e('UnlockSheet', '_initUnlockMethod failed with error', e);
      if (mounted) setState(() => _loadingAuth = false);
    }
  }

  Future<void> _relocateContainer() async {
    final oldUri = widget.initialUri;
    if (oldUri == null) return;
    VeLog.d('UnlockSheet', '_relocateContainer from oldUri=${VeLog.censorUri(oldUri)}');
    try {
      String newUri;
      String newDisplayName;
      String detectedFormat = _containerFormat;
      if (_isFolderVault) {
        final picked = await vaultExplorerApi.pickCryptomatorVault();
        if (picked == null || !mounted) {
          VeLog.d('UnlockSheet', '_relocateContainer: folder vault picker returned null');
          return;
        }
        final format = picked.format;
        if (format == null) {
          VeLog.w('UnlockSheet', '_relocateContainer: no vault folder format detected for uri=${VeLog.censorUri(picked.uri)}');
          setState(() => _error = context.l10n.noVaultFolderFormatDetected);
          return;
        }
        detectedFormat = format;
        newUri = picked.uri;
        newDisplayName = picked.displayName;
        VeLog.d('UnlockSheet', '_relocateContainer: folder vault picked: newUri=${VeLog.censorUri(newUri)} format=$detectedFormat');
      } else {
        final picked = await vaultExplorerApi.pickContainer();
        if (picked == null || !mounted) {
          VeLog.d('UnlockSheet', '_relocateContainer: container picker returned null');
          return;
        }
        newUri = picked.uri;
        newDisplayName = picked.displayName;
        VeLog.d('UnlockSheet', '_relocateContainer: container picked: newUri=${VeLog.censorUri(newUri)} name=${VeLog.censorName(newDisplayName)}');
      }
      setState(() => _loadingAuth = true);
      final records = await ContainerRepository.instance.loadAll();
      final existing = records[oldUri];
      if (existing == null) {
        VeLog.w('UnlockSheet', '_relocateContainer: existing record not found for oldUri=${VeLog.censorUri(oldUri)}');
        if (mounted) {
          setState(() {
            _loadingAuth = false;
            _error = context.l10n.savedContainerSettingsNotFound;
          });
        }
        return;
      }
      final savedPassword = await ContainerRepository.instance.getPassword(oldUri);
      final savedPatternHash = await ContainerRepository.instance.getPatternHash(oldUri);
      final savedPinHash = await ContainerRepository.instance.getPinHash(oldUri);
      await ContainerRepository.instance.remove(oldUri);
      final migrated = ContainerRecord(
        uri: newUri,
        label: existing.label,
        rememberPassword: existing.rememberPassword,
        unlockMethod: existing.unlockMethod,
        autoCloseMins: existing.autoCloseMins,
        documentProvider: existing.documentProvider,
        documentProviderFolders: existing.documentProviderFolders,
        thumbnailCacheMode: existing.thumbnailCacheMode,
        cacheDerivedKey: existing.cacheDerivedKey,
        pendingPassword: savedPassword,
        pendingPatternHash: savedPatternHash,
        pendingPinHash: savedPinHash,
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
        _storedPinHash = savedPinHash;
        _containerMissing = false;
        _loadingAuth = false;
      });
      if (_unlockMethod == ContainerUnlockMethod.biometrics) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          tryBiometric();
        }
      }
    } catch (e) {
      VeLog.e('UnlockSheet', '_relocateContainer error', e);
      if (mounted) {
        setState(() {
          _loadingAuth = false;
          _error = context.l10n.couldNotUpdateContainerLocation(e.toString());
        });
      }
    }
  }

  Future<void> _pickFile() async {
    if (widget.initialUri != null) return;
    try {
      if (_isFolderVault) {
        VeLog.d('UnlockSheet', 'Picking folder vault (current format=$_containerFormat)...');
        final result = await vaultExplorerApi.pickCryptomatorVault();
        if (result == null) {
          VeLog.d('UnlockSheet', 'pickCryptomatorVault returned null (cancelled or picker dismissed)');
          return;
        }
        VeLog.d('UnlockSheet', 'Folder vault picked: uri=${VeLog.censorUri(result.uri)}, name=${VeLog.censorName(result.displayName)}, detectedFormat=${result.format}');
        if (widget.mountedUris.contains(result.uri)) {
          VeLog.w('UnlockSheet', 'Folder vault already mounted: uri=${VeLog.censorUri(result.uri)}');
          setState(() {
            _error = context.l10n.containerAlreadyMounted;
            _selectedUri = null;
            _selectedName = null;
          });
          return;
        }
        final detectedFormat = result.format;
        if (detectedFormat == null) {
          VeLog.w('UnlockSheet', 'No vault folder format detected for uri=${VeLog.censorUri(result.uri)}');
          setState(() {
            _error = context.l10n.noVaultFolderFormatDetected;
            _selectedUri = null;
            _selectedName = null;
          });
          return;
        }
        try {
          final exists = await vaultExplorerApi.documentExists(result.uri);
          VeLog.d('UnlockSheet', 'Folder vault documentExists check: uri=${VeLog.censorUri(result.uri)} => $exists');
        } catch (e) {
          VeLog.w('UnlockSheet', 'Folder vault documentExists check threw error: $e');
        }
        setState(() {
          _selectedUri = result.uri;
          _selectedName = result.displayName;
          _containerFormat = detectedFormat;
          _error = null;
        });
        return;
      }
      VeLog.d('UnlockSheet', 'Picking file container...');
      final result = await vaultExplorerApi.pickContainer();
      if (result != null) {
        VeLog.d('UnlockSheet', 'Container picked: uri=${VeLog.censorUri(result.uri)}, name=${VeLog.censorName(result.displayName)}');
        if (widget.mountedUris.contains(result.uri)) {
          VeLog.w('UnlockSheet', 'Container already mounted: uri=${VeLog.censorUri(result.uri)}');
          setState(() {
            _error = context.l10n.containerAlreadyMounted;
            _selectedUri = null;
            _selectedName = null;
          });
          return;
        }
        try {
          final exists = await vaultExplorerApi.documentExists(result.uri);
          VeLog.d('UnlockSheet', 'Container documentExists check: uri=${VeLog.censorUri(result.uri)} => $exists');
        } catch (e) {
          VeLog.w('UnlockSheet', 'Container documentExists check threw error: $e');
        }
        setState(() {
          _selectedUri = result.uri;
          _selectedName = result.displayName;
          _containerFormat = 'container';
          _error = null;
        });
        vaultExplorerApi.warmContainer(result.uri);
      } else {
        VeLog.d('UnlockSheet', 'pickContainer returned null (cancelled or picker dismissed)');
      }
    } catch (e) {
      VeLog.e('UnlockSheet', 'pickFile threw exception', e);
      setState(() => _error = context.l10n.filePickerFailed(e.toString()));
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
    List<String>? keyfilePathsOverride,
  }) async {
    VeLog.i('UnlockSheet', '_unlock() initiated for uri=${VeLog.censorUri(_selectedUri)}, name=${VeLog.censorName(_selectedName)}, format=$_containerFormat');
    if (_selectedUri == null) {
      VeLog.w('UnlockSheet', '_unlock: _selectedUri is null');
      setState(() => _error = context.l10n.selectContainerFirst);
      return;
    }
    if (widget.mountedUris.contains(_selectedUri)) {
      VeLog.w('UnlockSheet', '_unlock: uri=${VeLog.censorUri(_selectedUri)} is already mounted');
      setState(() => _error = context.l10n.containerAlreadyMounted);
      return;
    }
    var effectivePassword = (passwordOverride ?? _passwordCtrl.text).trim();
    final effectiveKeyfilePaths =
        keyfilePathsOverride ?? keyfiles.map((k) => k.uri).toList();
    VeLog.d('UnlockSheet', '_unlock: credentials summary: hasPassword=${effectivePassword.isNotEmpty}, keyfilesCount=${effectiveKeyfilePaths.length}, hasPreservedKey=${preservedKey != null}, readOnly=$_readOnly');

    if (effectivePassword.isEmpty && preservedKey == null && effectiveKeyfilePaths.isEmpty) {
      VeLog.w('UnlockSheet', '_unlock: no password, keyfiles, or preserved key provided');
      setState(() => _error = context.l10n.passwordOrKeyfilesRequired);
      return;
    }
    if (_protectHiddenVolume &&
        _hiddenPasswordCtrl.text.isEmpty &&
        _hiddenKeyfilesController.keyfiles.isEmpty) {
      VeLog.w('UnlockSheet', '_unlock: hidden volume protection enabled but no hidden credentials provided');
      setState(() => _error = context.l10n.protectHiddenVolumeCredentialsRequired);
      return;
    }
    if (_isCryfs && !_hasAllStorageAccess) {
      VeLog.d('UnlockSheet', '_unlock: Cryfs vault requested without all-files storage access');
      final grant = await showAppConfirmDialog(
        context,
        title: context.l10n.slowPerformanceWarningTitle,
        message: context.l10n.slowPerformanceWarningMessage,
        confirmLabel: context.l10n.openSettings,
        cancelLabel: context.l10n.unlockAnyway,
      );
      if (grant) {
        await _requestStoragePermission();
        return;
      }
    }
    if (_isCryptomator || _isGocryptfs || _isCryfs) {
      VeLog.i('UnlockSheet', '_unlock: processing folder vault ($_containerFormat) at uri=${VeLog.censorUri(_selectedUri)}');
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final name = _selectedName ?? context.l10n.defaultVaultName;
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
          VeLog.d('UnlockSheet', 'Cryfs: shouldCacheDerivedKey=$shouldCacheDerivedKey, resolvedPreservedKey=${resolvedPreservedKey != null}');
        }
        VeLog.d('UnlockSheet', 'Calling native folder vault unlock for format=$_containerFormat, uri=${VeLog.censorUri(_selectedUri)}, docProvider=${widget.documentProvider}');
        var result = _isCryptomator
            ? await vaultExplorerApi.unlockCryptomatorVault(
                _selectedUri!,
                effectivePassword,
                displayName: name,
                documentProvider: widget.documentProvider,
                autoMountFolders: widget.autoMountFolders,
                readOnly: _readOnly,
              )
            : _isGocryptfs
                ? await vaultExplorerApi.unlockGocryptfsVault(
                    _selectedUri!,
                    effectivePassword,
                    displayName: name,
                    documentProvider: widget.documentProvider,
                    autoMountFolders: widget.autoMountFolders,
                    readOnly: _readOnly,
                  )
                : resolvedPreservedKey == null
                    ? await vaultExplorerApi.unlockCryfsVault(
                        _selectedUri!,
                        effectivePassword,
                        displayName: name,
                        documentProvider: widget.documentProvider,
                        autoMountFolders: widget.autoMountFolders,
                        readOnly: _readOnly,
                        cacheDerivedKey: shouldCacheDerivedKey,
                      )
                    : await _unlockSwallowingStaleAuthFail(() => vaultExplorerApi.unlockCryfsVault(
                          _selectedUri!,
                          effectivePassword,
                          displayName: name,
                          documentProvider: widget.documentProvider,
                          autoMountFolders: widget.autoMountFolders,
                          readOnly: _readOnly,
                          preservedKey: resolvedPreservedKey,
                          cacheDerivedKey: shouldCacheDerivedKey,
                        ));
        if (result == null && _isCryfs && resolvedPreservedKey != null) {
          VeLog.w('UnlockSheet', 'Cryfs preserved key failed; retrying with plain password');
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
              autoMountFolders: widget.autoMountFolders,
              readOnly: _readOnly,
              cacheDerivedKey: shouldCacheDerivedKey,
            );
          }
        }
        if (result == null) {
          VeLog.w('UnlockSheet', 'Folder vault unlock failed: native engine returned null (invalid password or vault corrupt)');
          setState(() => _error = context.l10n.incorrectPasswordOrInvalidVault);
          return;
        }
        VeLog.i('UnlockSheet', 'Folder vault unlocked successfully: volId=${result.volId}, filesCount=${result.files.length}, format=${result.containerFormat}');
        await AppSecureStorage.instance.write(key: 'temp_pw_$_selectedUri', value: effectivePassword);
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
          if (savedRecord != null) {
            var updated = savedRecord;
            if (_isCryfs && savedRecord.cacheDerivedKey != shouldCacheDerivedKey) {
              updated = updated.copyWith(cacheDerivedKey: shouldCacheDerivedKey);
            }
            if (savedRecord.readOnly != _readOnly || savedRecord.containerFormat != result.containerFormat) {
              updated = updated.copyWith(
                readOnly: _readOnly,
                containerFormat: result.containerFormat,
              );
            }
            if (updated != savedRecord) {
              await ContainerRepository.instance.save(updated);
              savedRecord = updated;
            }
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
      } on PlatformException catch (e) {
        VeLog.e('UnlockSheet', 'Folder vault PlatformException: code=${e.code}, message=${e.message}', e);
        if (e.code != 'CANCELLED') {
          setState(() => _error = e.message ?? context.l10n.genericUnknownError);
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    VeLog.i('UnlockSheet', '_unlock: starting file container unlock for uri=${VeLog.censorUri(_selectedUri)}');
    setState(() { _loading = true; _error = null; _activeVolId = null; _progress = null; });
    try {
      final pim = clampPim(_pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0);
      final hiddenPim = clampPim(_hiddenPimCtrl.text.isEmpty ? 0 : int.tryParse(_hiddenPimCtrl.text) ?? 0);
      final hiddenKeyfilePaths =
          _hiddenKeyfilesController.keyfiles.map((k) => k.uri).toList();
      final name = _selectedName ?? context.l10n.defaultContainerName;
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

      VeLog.d('UnlockSheet', 'Calling vaultExplorerApi.unlockContainer(uri=${VeLog.censorUri(_selectedUri)}, hasCustomPim=${pim > 0}, cipherId=$_cipherId, hashId=$_hashId, keyfilesCount=${effectiveKeyfilePaths.length}, protectHidden=$_protectHiddenVolume, docProvider=${widget.documentProvider})');
      var result = resolvedPreservedKey == null
          ? await vaultExplorerApi.unlockContainer(
              _selectedUri!,
              effectivePassword,
              pim,
              displayName: name,
              documentProvider: widget.documentProvider,
              autoMountFolders: widget.autoMountFolders,
              cipherId: _cipherId,
              hashId: _hashId,
              preservedKey: resolvedPreservedKey,
              cacheDerivedKey: shouldCacheDerivedKey,
              keyfilePaths: effectiveKeyfilePaths,
              readOnly: _readOnly,
              protectHiddenVolume: _protectHiddenVolume,
              hiddenVolumePassword: _hiddenPasswordCtrl.text,
              hiddenVolumePim: hiddenPim,
              hiddenVolumeCipherId: _hiddenCipherId,
              hiddenVolumeHashId: _hiddenHashId,
              hiddenVolumeKeyfilePaths: hiddenKeyfilePaths,
            )
          : await _unlockSwallowingStaleAuthFail(() => vaultExplorerApi.unlockContainer(
              _selectedUri!,
              effectivePassword,
              pim,
              displayName: name,
              documentProvider: widget.documentProvider,
              autoMountFolders: widget.autoMountFolders,
              cipherId: _cipherId,
              hashId: _hashId,
              preservedKey: resolvedPreservedKey,
              cacheDerivedKey: shouldCacheDerivedKey,
              keyfilePaths: effectiveKeyfilePaths,
              readOnly: _readOnly,
              protectHiddenVolume: _protectHiddenVolume,
              hiddenVolumePassword: _hiddenPasswordCtrl.text,
              hiddenVolumePim: hiddenPim,
              hiddenVolumeCipherId: _hiddenCipherId,
              hiddenVolumeHashId: _hiddenHashId,
              hiddenVolumeKeyfilePaths: hiddenKeyfilePaths,
            ));
      if (result == null && resolvedPreservedKey != null) {
        VeLog.w('UnlockSheet', 'Preserved derived key failed; clearing and retrying with plain credentials');
        await vaultExplorerApi.clearDerivedKey(_selectedUri!);
        if (effectivePassword.isEmpty) {
          effectivePassword =
              (await ContainerRepository.instance.getPassword(_selectedUri!))?.trim() ?? '';
        }
        if (effectivePassword.isNotEmpty || effectiveKeyfilePaths.isNotEmpty) {
          result = await vaultExplorerApi.unlockContainer(
            _selectedUri!,
            effectivePassword,
            pim,
            displayName: name,
            documentProvider: widget.documentProvider,
            autoMountFolders: widget.autoMountFolders,
            cipherId: _cipherId,
            hashId: _hashId,
            preservedKey: null,
            cacheDerivedKey: shouldCacheDerivedKey,
            keyfilePaths: effectiveKeyfilePaths,
            readOnly: _readOnly,
            protectHiddenVolume: _protectHiddenVolume,
            hiddenVolumePassword: _hiddenPasswordCtrl.text,
            hiddenVolumePim: hiddenPim,
            hiddenVolumeCipherId: _hiddenCipherId,
            hiddenVolumeHashId: _hiddenHashId,
            hiddenVolumeKeyfilePaths: hiddenKeyfilePaths,
          );
        }
      }
      if (result != null) {
        VeLog.i('UnlockSheet', 'Container unlocked successfully: volId=${result.volId}, format=${result.containerFormat}, filesCount=${result.files.length}, cipher=${result.matchedCipherId}, hash=${result.matchedHashId}');
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
            keyfiles: const [],
          );
          await ContainerRepository.instance.save(newRecord);
          savedRecord = newRecord;
        } else if (widget.initialUri != null) {
          final records = await ContainerRepository.instance.loadAll();
          final existing = records[widget.initialUri];
          if (existing != null) {
            final shouldSaveKeyfiles =
                existing.unlockMethod == ContainerUnlockMethod.rememberPassword;
            final updatedKeyfiles = shouldSaveKeyfiles ? newKeyfiles : existing.keyfiles;
            final updated = existing.copyWith(
              cacheDerivedKey: shouldCacheDerivedKey,
              cipherId: result.matchedCipherId,
              readOnly: _readOnly,
              hashId: result.matchedHashId,
              containerFormat: result.containerFormat,
              keyfiles: updatedKeyfiles,
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
        VeLog.w('UnlockSheet', 'Container unlock failed: unlockContainer returned null (incorrect password/keyfiles, corrupt header, or unreadable SAF file descriptor)');
        setState(() => _error = context.l10n.incorrectPasswordOrInvalidContainer);
      }
    } on PlatformException catch (e) {
      VeLog.e('UnlockSheet', 'unlockContainer PlatformException: code=${e.code}, message=${e.message}', e);
      if (e.code != 'CANCELLED') {
        setState(() => _error = e.message ?? context.l10n.genericUnknownError);
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

  /// Mirrors the exact priority the credential card used to pick its
  /// branch with (loading > missing > biometric > pattern > pin >
  /// password > a bare leftover error), just exposed as a value instead
  /// of implicit control flow, so other widgets can key off "which state
  /// are we in" without re-deriving the same five-way condition.
  _UnlockCredentialState get _credentialState {
    if (_loadingAuth) return _UnlockCredentialState.loading;
    if (_containerMissing) return _UnlockCredentialState.missing;
    if (_unlockMethod == ContainerUnlockMethod.biometrics && !_showPasswordFallback) {
      return _UnlockCredentialState.biometric;
    }
    if (_unlockMethod == ContainerUnlockMethod.pattern && !_showPasswordFallback) {
      return _UnlockCredentialState.pattern;
    }
    if (_unlockMethod == ContainerUnlockMethod.pin && !_showPasswordFallback) {
      return _UnlockCredentialState.pin;
    }
    if (_showPasswordUI) return _UnlockCredentialState.password;
    if (_error != null) return _UnlockCredentialState.fallbackError;
    return _UnlockCredentialState.none;
  }

  String get _unlockProgressLabel {
    final p = _progress;
    if (p == null || p.total <= 0) return context.l10n.decryptingLabel;

    if (_isLuks) {
      return p.total > 1
          ? context.l10n.luksKeyslotProgress(p.attempted, p.total)
          : context.l10n.luksKeyslotProgressUnknown;
    }
    
    if (_isBitlocker) {
      return p.total > 1
          ? context.l10n.bitlockerCredentialProgress(p.attempted, p.total)
          : context.l10n.bitlockerCredentialProgressUnknown;
    }

    final hashName = hashAlgorithmName(p.hashId);
    final cipherName = p.cipherId != 255 ? cipherAlgorithmName(p.cipherId) : '';
    final slotName = p.slot == 1 ? context.l10n.hiddenVolumeSlotName : context.l10n.standardVolumeSlotName;

    final algo = cipherName.isNotEmpty ? '$hashName + $cipherName' : hashName;
    return p.total > 1
        ? context.l10n.veracryptAlgoProgress(algo, slotName)
        : context.l10n.veracryptAlgoProgress(algo, slotName);
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
            widget.initialUri != null ? context.l10n.unlockContainerTitle : context.l10n.mountContainerTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: widget.initialUri == null && context.screen.useWideLayout
              ? [
                  _buildVaultKindSegmentedButton(context),
                  const SizedBox(width: 16),
                ]
              : null,
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
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: dismissKeyboard,
            child: SafeArea(
              child: _buildBody(context, cs, textTheme),
            ),
          ),
        ),
      ),
    );
  }


  /// Builds the screen's main content. Below the wide-layout threshold this
  /// is the exact same single stacked column as before: vault picker,
  /// credential entry, advanced settings, then the unlock button. Once
  /// there's real width to work with, the vault name / credential entry /
  /// unlock button move into a compact left pane, and the advanced
  /// settings (keyfiles, cipher overrides, hidden volume, remember-me)
  /// become their own independently-scrolling pane on the right -- so the
  /// primary action isn't sharing a column with settings most unlocks
  /// never touch.
  Widget _buildBody(BuildContext context, ColorScheme cs, TextTheme textTheme) {
    final pickerChildren = _buildPickerSectionChildren(context, cs, textTheme);
    final credentialChildren = _buildCredentialChildren(context, cs, textTheme);
    final settingsChildren = _buildSettingsChildren(context, cs, textTheme);
    final tailChildren = _buildTailChildren(context, cs, textTheme);

    if (context.screen.useWideLayout) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: context.screen.secondaryPaneWidth(),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...pickerChildren, ...credentialChildren, ...tailChildren],
              ),
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: settingsChildren,
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...pickerChildren,
          ...credentialChildren,
          ...settingsChildren,
          ...tailChildren,
        ],
      ),
    );
  }

  /// Vault-type selector, file/folder picker card, and the folder-vault
  /// storage-access warning -- "which container am I unlocking". This is
  /// the compact left pane in the wide layout.
  /// Container-file vs folder-vault picker. Sits inline above the file
  /// card when there's only one column to work with; relocates to the
  /// AppBar's actions in the wide layout instead, where it doesn't cost
  /// any of the (now more valuable) space in the left pane.
  Widget _buildVaultKindSegmentedButton(BuildContext context) {
    return SegmentedButton<String>(
      segments: [
        ButtonSegment(
          value: 'container',
          label: Text(
            context.l10n.vaultKindContainerFile,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
          icon: const Icon(Icons.folder_zip_rounded),
        ),
        ButtonSegment(
          value: 'directory_vault',
          label: Text(
            context.l10n.vaultKindFolderVault,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
          icon: const Icon(Icons.folder_shared_rounded),
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
    );
  }

  List<Widget> _buildPickerSectionChildren(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return [
                    if (widget.initialUri == null && !context.screen.useWideLayout) ...[
                      _buildVaultKindSegmentedButton(context),
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
                                              ? context.l10n.formatContainerLabel('LUKS')
                                              : _isCryptomator
                                                  ? context.l10n.formatVaultLabel('Cryptomator')
                                                  : _isGocryptfs
                                                      ? context.l10n.formatVaultLabel('Gocryptfs')
                                                      : _isCryfs
                                                          ? context.l10n.formatVaultLabel('CryFS')
                                                          : _isBitlocker
                                                              ? context.l10n.formatContainerLabel('BitLocker')
                                                              : _containerFormat == 'veracrypt'
                                                                  ? context.l10n.formatContainerLabel('VeraCrypt')
                                                                  : context.l10n.encryptedContainerLabel)
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
                                              ? context.l10n.tapToSelectVaultFolder
                                              : context.l10n.tapToSelectContainerFile),
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
                            ? context.l10n.cryfsStorageAccessWarning
                            : context.l10n.folderVaultStorageAccessWarning,
                        tone: AppBannerTone.warning,
                        icon: Icons.speed_rounded,
                        trailing: TextButton(
                          onPressed: _requestStoragePermission,
                          child: Text(
                            context.l10n.enableButtonLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

    ];
  }

  /// The active credential control -- loading spinner, "container
  /// missing" card, biometric/pattern/PIN card, or (falling back to)
  /// just the password field on its own. Sits alongside
  /// [_buildTailChildren] on the same side; [_buildSettingsChildren]
  /// (keyfiles, cipher overrides, hidden volume, remember-me) moves to
  /// its own pane in wide layouts instead of sharing this column.
  List<Widget> _buildCredentialChildren(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return [
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
                                          context.l10n.containerMissingTitle,
                                          style: textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: cs.onErrorContainer,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          context.l10n.containerMissingSubtitle,
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
                                context.l10n.containerMissingExplanation,
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
                                      child: Text(context.l10n.retryButtonLabel),
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
                                      child: Text(context.l10n.locateFileButtonLabel),
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
                                context.l10n.biometricUnlockTitle,
                                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                context.l10n.biometricUnlockSubtitle,
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
                                      child: Text(context.l10n.usePasswordButtonLabel),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: tryBiometric,
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: Text(context.l10n.authenticateButtonLabel),
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
                                context.l10n.drawUnlockPatternTitle,
                                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _patternError
                                    ? context.l10n.wrongPatternTryAgain
                                    : context.l10n.connectYourPatternSequence,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: _patternError ? cs.error : cs.onSurfaceVariant,
                                  fontWeight: _patternError ? FontWeight.bold : null,
                                ),
                              ),
                              const SizedBox(height: 20),
                              PatternLockView(
                                key: ValueKey(_patternResetKey),
                                onPatternComplete: onPatternComplete,
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
                                child: Text(context.l10n.usePasswordInsteadButtonLabel),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ]
                    else if (_unlockMethod == ContainerUnlockMethod.pin && !_showPasswordFallback) ...[
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
                                context.l10n.enterUnlockPinTitle,
                                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _pinError
                                    ? context.l10n.wrongPinTryAgain
                                    : context.l10n.enterYourPinSequence,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: _pinError ? cs.error : cs.onSurfaceVariant,
                                  fontWeight: _pinError ? FontWeight.bold : null,
                                ),
                              ),
                              const SizedBox(height: 20),
                              PinLockView(
                                key: ValueKey(_pinResetKey),
                                onPinComplete: onPinComplete,
                                showError: _pinError,
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
                                child: Text(context.l10n.usePasswordInsteadButtonLabel),
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
                                autofillHints: null,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: cs.surfaceContainerHighest,
                                  labelText: context.l10n.passwordFieldLabel,
                                  hintText: _isFolderVault
                                      ? context.l10n.passwordHintFolderVault
                                      : _isBitlocker
                                          ? context.l10n.passwordHintBitlocker
                                          : context.l10n.passwordHintContainer,
                                  prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: cs.primary),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_passwordPrefilled)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: Tooltip(
                                            message: context.l10n.usingSavedPasswordTooltip,
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

            ],
          ),
        ),
      ],
    ];
  }

  /// Keyfiles, cipher/hash/PIM overrides, read-only mode, hidden-volume
  /// protection, and the remember-this-container toggle -- only relevant
  /// once the password field is the active credential control, so this
  /// is empty for every other [_UnlockCredentialState].
  List<Widget> _buildSettingsChildren(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    if (_credentialState != _UnlockCredentialState.password) return const [];
    return [
                            if (!_isFolderVault && !_isBitlocker)
                              Padding(
                                padding: const EdgeInsets.all(1),
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
                                        context.l10n.luksKeyfileReplacesPasswordNote,
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
                                onExpansionChanged: (_) => dismissKeyboard(),
                                onLongPress: () => setState(() {
                                  _cipherId = 255;
                                  _hashId = 255;
                                  _pimCtrl.clear();
                                }),
                              ),
                            SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              value: _readOnly,
                              onChanged: _loading
                                  ? null
                                  : (val) {
                                      dismissKeyboard();
                                      setState(() {
                                        _readOnly = val;
                                        if (val) _protectHiddenVolume = false;
                                      });
                                    },
                              title: Text(
                                context.l10n.readOnlyModeLabel,
                                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                context.l10n.readOnlyModeContainerSubtitle,
                                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              secondary: Icon(Icons.visibility_outlined, color: cs.primary),
                            ),
                            if (!_isLuks && !_isFolderVault && !_isBitlocker) ...[
                              SwitchListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                value: _protectHiddenVolume && !_readOnly,
                                onChanged: (_loading || _readOnly)
                                    ? null
                                    : (val) {
                                        dismissKeyboard();
                                        setState(() => _protectHiddenVolume = val);
                                      },
                                title: Text(
                                  context.l10n.protectHiddenVolumeToggleTitle,
                                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  _readOnly
                                      ? context.l10n.readOnlyModeContainerSubtitle
                                      : context.l10n.protectHiddenVolumeToggleSubtitle,
                                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                                secondary: Icon(Icons.shield_outlined, color: cs.primary),
                              ),
                              if (_protectHiddenVolume && !_readOnly) ...[
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: TextField(
                                    controller: _hiddenPasswordCtrl,
                                    obscureText: _hiddenObscure,
                                    enabled: !_loading,
                                    // Autofill disabled: prevents password manager popups
                                    // from stealing focus and dismissing the keyboard
                                    // mid-typing.
                                    autofillHints: null,
                                    decoration: InputDecoration(
                                      labelText: context.l10n.hiddenPasswordLabel,
                                      prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
                                      suffixIcon: PasswordVisibilityToggle(
                                        obscured: _hiddenObscure,
                                        onToggle: () => setState(() => _hiddenObscure = !_hiddenObscure),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 1),
                                  child: KeyfilesPicker(
                                    keyfiles: _hiddenKeyfilesController.keyfiles,
                                    picking: _hiddenKeyfilesController.picking,
                                    onPick: _hiddenKeyfilesController.pick,
                                    onRemove: _hiddenKeyfilesController.remove,
                                    enabled: !_loading,
                                  ),
                                ),
                                AdvancedParamsPanel(
                                  pimController: _hiddenPimCtrl,
                                  cipherId: _hiddenCipherId,
                                  hashId: _hiddenHashId,
                                  enabled: !_loading,
                                  onCipherChanged: (val) => setState(() => _hiddenCipherId = val),
                                  onHashChanged: (val) => setState(() => _hiddenHashId = val),
                                  onExpansionChanged: (_) => dismissKeyboard(),
                                  onLongPress: () => setState(() {
                                    _hiddenCipherId = 255;
                                    _hiddenHashId = 255;
                                    _hiddenPimCtrl.clear();
                                  }),
                                ),
                              ],
                            ],
                            if (widget.initialUri == null)
                              SwitchListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                value: _remember,
                                onChanged: (val) {
                                  dismissKeyboard();
                                  setState(() => _remember = val);
                                },
                                title: Text(
                                  context.l10n.rememberContainerLabel,
                                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  context.l10n.rememberContainerSubtitle,
                                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                                secondary: Icon(Icons.push_pin_outlined, color: cs.primary),
                              ),

    ];
  }

  /// The error banner, unlock button, and cancel-unlock link -- the tail
  /// of the password state, or a bare error banner for the rare state
  /// where nothing else matched but an error is still around to show.
  List<Widget> _buildTailChildren(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    switch (_credentialState) {
      case _UnlockCredentialState.password:
        return [
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
                                _isFolderVault
                                    ? context.l10n.unlockVaultButtonLabel
                                    : context.l10n.unlockContainerLabel,
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
                            child: Text(context.l10n.cancelUnlockButtonLabel),
                          ),
                        ),
                      ],

        ];
      case _UnlockCredentialState.fallbackError:
        return [
                      const SizedBox(height: 16),
                      InlineErrorBanner(_error!),

        ];
      default:
        return const [];
    }
  }
}
