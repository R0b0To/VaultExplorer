// File: lib/features/unlock/unlock_sheet.dart

import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import '../lock/widgets/pattern_lock_view.dart';
import '../lock/widgets/pin_lock_view.dart';
import 'unlock_biometric_mixin.dart';
import 'unlock_biometric_source.dart';

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
    notify: () {
      if (mounted) setState(() {});
    },
    onError: (msg) {
      if (mounted) setState(() => _error = msg ?? context.l10n.couldNotPickKeyfiles);
    },
  );

  @override
  void onKeyfilePickError(String message) => setState(() => _error = message);

  bool get _isLuks => ContainerFormat.isLuksWire(_containerFormat);
  bool get _isCryptomator => ContainerFormat.isCryptomatorWire(_containerFormat);
  bool get _isGocryptfs => ContainerFormat.isGocryptfsWire(_containerFormat);
  bool get _isCryfs => ContainerFormat.isCryfsWire(_containerFormat);
  bool get _isBitlocker => ContainerFormat.isBitlockerWire(_containerFormat);
  bool get _isFolderVault => ContainerFormat.isFolderVaultWire(_containerFormat);
  bool get _isVeraCrypt => !_isLuks && !_isFolderVault && !_isBitlocker;
  bool get _hasAdvancedSettings => _isVeraCrypt || _isLuks;

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
  String get noSavedCredentialsForBiometricMessage => context.l10n.initSecureCredsBiometricMessage;

  @override
  String get noSavedCredentialsForPatternMessage => context.l10n.initSecureCredsPatternMessage;

  @override
  String get noSavedCredentialsForPinMessage => context.l10n.initSecureCredsPinMessage;

  @override
  String get debugLogTag => 'unlock';

  bool get _passwordPrefilled =>
      widget.prefillPassword != null && _passwordCtrl.text == widget.prefillPassword;

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
      setState(() => _hasAllStorageAccess = hasAccess);
    }
  }

  Future<void> _requestStoragePermission() async {
    const api = VaultExplorerApi();
    await api.requestAllFilesAccess();
    await _checkStoragePermission();
  }

  Future<void> _initUnlockMethod() async {
    if (widget.initialUri == null) {
      VeLog.d('UnlockSheet', '_initUnlockMethod: No initialUri');
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
      if (record.unlockMethod == ContainerUnlockMethod.rememberPassword &&
          record.keyfiles.isNotEmpty) {
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
        _storedPatternHash = await ContainerRepository.instance.getPatternHash(widget.initialUri!);
      }
      if (_unlockMethod == ContainerUnlockMethod.pin) {
        _storedPinHash = await ContainerRepository.instance.getPinHash(widget.initialUri!);
      }
      if (mounted) setState(() => _loadingAuth = false);
      if (_unlockMethod == ContainerUnlockMethod.biometrics) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (mounted) tryBiometric();
      }
    } catch (e) {
      VeLog.e('UnlockSheet', '_initUnlockMethod failed with error', e);
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
          setState(() => _error = context.l10n.noVaultFolderFormatDetected);
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
        if (mounted) tryBiometric();
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
        final result = await vaultExplorerApi.pickCryptomatorVault();
        if (result == null) return;
        if (widget.mountedUris.contains(result.uri)) {
          setState(() {
            _error = context.l10n.containerAlreadyMounted;
            _selectedUri = null;
            _selectedName = null;
          });
          return;
        }
        final detectedFormat = result.format;
        if (detectedFormat == null) {
          setState(() {
            _error = context.l10n.noVaultFolderFormatDetected;
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
            _error = context.l10n.containerAlreadyMounted;
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
    if (_selectedUri == null) {
      setState(() => _error = context.l10n.selectContainerFirst);
      return;
    }
    if (widget.mountedUris.contains(_selectedUri)) {
      setState(() => _error = context.l10n.containerAlreadyMounted);
      return;
    }
    var effectivePassword = (passwordOverride ?? _passwordCtrl.text).trim();
    final effectiveKeyfilePaths =
        keyfilePathsOverride ?? keyfiles.map((k) => k.uri).toList();

    if (effectivePassword.isEmpty && preservedKey == null && effectiveKeyfilePaths.isEmpty) {
      setState(() => _error = context.l10n.passwordOrKeyfilesRequired);
      return;
    }
    if (_protectHiddenVolume &&
        _hiddenPasswordCtrl.text.isEmpty &&
        _hiddenKeyfilesController.keyfiles.isEmpty) {
      setState(() => _error = context.l10n.protectHiddenVolumeCredentialsRequired);
      return;
    }
    if (_isCryfs && !_hasAllStorageAccess) {
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
        }

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
          setState(() => _error = context.l10n.incorrectPasswordOrInvalidVault);
          return;
        }

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
        if (e.code != 'CANCELLED') {
          setState(() => _error = e.message ?? context.l10n.genericUnknownError);
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _activeVolId = null;
      _progress = null;
    });

    try {
      final pim = clampPim(_pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0);
      final hiddenPim = clampPim(_hiddenPimCtrl.text.isEmpty ? 0 : int.tryParse(_hiddenPimCtrl.text) ?? 0);
      final hiddenKeyfilePaths = _hiddenKeyfilesController.keyfiles.map((k) => k.uri).toList();
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
        setState(() => _error = context.l10n.incorrectPasswordOrInvalidContainer);
      }
    } on PlatformException catch (e) {
      if (e.code != 'CANCELLED') {
        setState(() => _error = e.message ?? context.l10n.genericUnknownError);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _activeVolId = null;
          _progress = null;
        });
      }
    }
  }

  bool get _showPasswordUI {
    if (_showPasswordFallback) return true;
    if (widget.initialUri == null) return true;
    return _unlockMethod == ContainerUnlockMethod.password ||
        _unlockMethod == ContainerUnlockMethod.rememberPassword;
  }

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
    return context.l10n.veracryptAlgoProgress(algo, slotName);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final wideLayout = context.screen.useWideLayout;

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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          actions: widget.initialUri == null && wideLayout
              ? [
                  _buildVaultKindSegmentedButton(context),
                  const SizedBox(width: 12),
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
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: dismissKeyboard,
          child: SafeArea(
            child: _buildLayout(context, cs, textTheme, wideLayout),
          ),
        ),
      ),
    );
  }

  Widget _buildLayout(BuildContext context, ColorScheme cs, TextTheme textTheme, bool wideLayout) {
    final isPatternOrPin = _credentialState == _UnlockCredentialState.pattern ||
        _credentialState == _UnlockCredentialState.pin;

    // Landscape / Wide 2-column layout
    if (wideLayout) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Container Card + Prompt/Fallback Card + Primary Action
            Expanded(
              flex: 5,
              child: SingleChildScrollView(
                physics: isPatternOrPin ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPickerCard(context, cs, textTheme),
                    const SizedBox(height: 10),
                    ..._buildLeftPaneCredentialSection(context, cs, textTheme),
                    ..._buildPrimaryActionSection(context, cs, textTheme),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            const VerticalDivider(width: 1),
            const SizedBox(width: 14),
            // Right Column: Advanced Options (Password mode) OR Lock Keypad/Grid (Pattern / PIN / Biometric)
            Expanded(
              flex: 6,
              child: _buildRightPane(context, cs, textTheme),
            ),
          ],
        ),
      );
    }

    // Portrait / Standard vertical column
    return SingleChildScrollView(
      physics: isPatternOrPin ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPickerCard(context, cs, textTheme),
          const SizedBox(height: 10),
          ..._buildCredentialSection(context, cs, textTheme),
          if (_credentialState == _UnlockCredentialState.password && _hasAdvancedSettings) ...[
            const SizedBox(height: 10),
            _buildCollapsibleAdvancedCard(context, cs, textTheme),
          ],
          ..._buildPrimaryActionSection(context, cs, textTheme),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── CONTAINER IDENTITY CARD ────────────────────────────────────────────────

  Widget _buildPickerCard(BuildContext context, ColorScheme cs, TextTheme textTheme) {
    final hasSelection = _selectedUri != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          children: [
            if (widget.initialUri == null && !context.screen.useWideLayout) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: _buildVaultKindSegmentedButton(context),
              ),
            ],
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: hasSelection ? cs.primaryContainer.withValues(alpha: 0.7) : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: ContainerFormatIcon(
                  format: hasSelection
                      ? ContainerFormat.fromWire(_containerFormat)
                      : ContainerFormat.directoryVault,
                  color: hasSelection ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  size: 22,
                ),
              ),
              title: Text(
                _selectedName ??
                    (_isFolderVault
                        ? context.l10n.tapToSelectVaultFolder
                        : context.l10n.tapToSelectContainerFile),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: hasSelection ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                hasSelection
                    ? _formatBadgeLabel(context)
                    : (_isFolderVault
                        ? 'Cryptomator | Gocryptfs | CryFS'
                        : 'VeraCrypt | LUKS | BitLocker'),
                style: textTheme.bodySmall?.copyWith(
                  color: hasSelection ? cs.primary : cs.onSurfaceVariant,
                  fontWeight: hasSelection ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: (hasSelection && widget.initialUri == null)
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: context.l10n.clearAllButton,
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                                _selectedUri = null;
                                _selectedName = null;
                                _containerFormat = _isFolderVault ? 'directory_vault' : 'container';
                              }),
                    )
                  : (widget.initialUri == null ? Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant) : null),
              onTap: _loading || widget.initialUri != null ? null : _pickFile,
            ),
          ],
        ),
        if (_isFolderVault && !_hasAllStorageAccess) ...[
          const SizedBox(height: 8),
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
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── CREDENTIALS SECTION (PORTRAIT) ─────────────────────────────────────────

  List<Widget> _buildCredentialSection(BuildContext context, ColorScheme cs, TextTheme textTheme) {
    switch (_credentialState) {
      case _UnlockCredentialState.loading:
        return [
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ];

      case _UnlockCredentialState.missing:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.find_in_page_outlined, color: cs.error, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.containerMissingTitle,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.error,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.containerMissingExplanation,
                      style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _loadingAuth = true;
                                _containerMissing = false;
                              });
                              _initUnlockMethod();
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                            child: Text(
                              context.l10n.retryButtonLabel,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: _relocateContainer,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                            child: Text(
                              context.l10n.locateFileButtonLabel,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UnlockCredentialState.biometric:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.fingerprint_rounded, size: 44, color: cs.primary),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.biometricUnlockTitle,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.biometricUnlockSubtitle,
                      style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() => _showPasswordFallback = true),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                            child: Text(
                              context.l10n.usePasswordButtonLabel,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: tryBiometric,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                            child: Text(
                              context.l10n.authenticateButtonLabel,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UnlockCredentialState.pattern:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      context.l10n.drawUnlockPatternTitle,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _patternError
                          ? context.l10n.wrongPatternTryAgain
                          : context.l10n.connectYourPatternSequence,
                      style: textTheme.bodySmall?.copyWith(
                        color: _patternError ? cs.error : cs.onSurfaceVariant,
                        fontWeight: _patternError ? FontWeight.bold : null,
                      ),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    PatternLockView(
                      key: ValueKey(_patternResetKey),
                      onPatternComplete: onPatternComplete,
                      showError: _patternError,
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => setState(() => _showPasswordFallback = true),
                      child: Text(
                        context.l10n.usePasswordInsteadButtonLabel,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UnlockCredentialState.pin:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      context.l10n.enterUnlockPinTitle,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _pinError
                          ? context.l10n.wrongPinTryAgain
                          : context.l10n.enterYourPinSequence,
                      style: textTheme.bodySmall?.copyWith(
                        color: _pinError ? cs.error : cs.onSurfaceVariant,
                        fontWeight: _pinError ? FontWeight.bold : null,
                      ),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    PinLockView(
                      key: ValueKey(_pinResetKey),
                      onPinComplete: onPinComplete,
                      showError: _pinError,
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => setState(() => _showPasswordFallback = true),
                      child: Text(
                        context.l10n.usePasswordInsteadButtonLabel,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UnlockCredentialState.password:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  autofocus: widget.initialUri != null && widget.prefillPassword?.isEmpty != false,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _unlock(),
                  textInputAction: TextInputAction.done,
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
                              child: Icon(Icons.bookmark_rounded, size: 20, color: cs.primary),
                            ),
                          ),
                        PasswordVisibilityToggle(
                          obscured: _obscure,
                          onToggle: () => setState(() => _obscure = !_obscure),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (!_hasAdvancedSettings) ...[
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  value: _readOnly,
                  onChanged: _loading
                      ? null
                      : (val) {
                          dismissKeyboard();
                          setState(() => _readOnly = val);
                        },
                  title: Text(
                    context.l10n.readOnlyModeLabel,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    context.l10n.readOnlyModeContainerSubtitle,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  secondary: Icon(Icons.visibility_outlined, color: cs.primary, size: 22),
                ),
              ],
              if (widget.initialUri == null) ...[
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  value: _remember,
                  onChanged: _loading
                      ? null
                      : (val) {
                          dismissKeyboard();
                          setState(() => _remember = val);
                        },
                  title: Text(
                    context.l10n.rememberContainerLabel,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    context.l10n.rememberContainerSubtitle,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  secondary: Icon(Icons.push_pin_outlined, color: cs.primary, size: 22),
                ),
              ],
            ],
          ),
        ];

      default:
        return const [];
    }
  }

  // ── LEFT PANE CREDENTIAL SECTION (WIDE/LANDSCAPE) ──────────────────────────

  List<Widget> _buildLeftPaneCredentialSection(BuildContext context, ColorScheme cs, TextTheme textTheme) {
    switch (_credentialState) {
      case _UnlockCredentialState.loading:
        return const [];

      case _UnlockCredentialState.missing:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.find_in_page_outlined, color: cs.error, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.containerMissingTitle,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.error,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.containerMissingExplanation,
                      style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _loadingAuth = true;
                                _containerMissing = false;
                              });
                              _initUnlockMethod();
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                            child: Text(
                              context.l10n.retryButtonLabel,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: _relocateContainer,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                            child: Text(
                              context.l10n.locateFileButtonLabel,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UnlockCredentialState.biometric:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.biometricUnlockTitle,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.biometricUnlockSubtitle,
                      style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() => _showPasswordFallback = true),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                            child: Text(
                              context.l10n.usePasswordButtonLabel,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: tryBiometric,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                            child: Text(
                              context.l10n.authenticateButtonLabel,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UnlockCredentialState.pattern:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.drawUnlockPatternTitle,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _patternError
                          ? context.l10n.wrongPatternTryAgain
                          : context.l10n.connectYourPatternSequence,
                      style: textTheme.bodySmall?.copyWith(
                        color: _patternError ? cs.error : cs.onSurfaceVariant,
                        fontWeight: _patternError ? FontWeight.bold : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: () => setState(() => _showPasswordFallback = true),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        child: Text(
                          context.l10n.usePasswordInsteadButtonLabel,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UnlockCredentialState.pin:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.enterUnlockPinTitle,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _pinError
                          ? context.l10n.wrongPinTryAgain
                          : context.l10n.enterYourPinSequence,
                      style: textTheme.bodySmall?.copyWith(
                        color: _pinError ? cs.error : cs.onSurfaceVariant,
                        fontWeight: _pinError ? FontWeight.bold : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: () => setState(() => _showPasswordFallback = true),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        child: Text(
                          context.l10n.usePasswordInsteadButtonLabel,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];

      case _UnlockCredentialState.password:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  autofocus: widget.initialUri != null && widget.prefillPassword?.isEmpty != false,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _unlock(),
                  textInputAction: TextInputAction.done,
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
                              child: Icon(Icons.bookmark_rounded, size: 20, color: cs.primary),
                            ),
                          ),
                        PasswordVisibilityToggle(
                          obscured: _obscure,
                          onToggle: () => setState(() => _obscure = !_obscure),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (!_hasAdvancedSettings) ...[
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  value: _readOnly,
                  onChanged: _loading
                      ? null
                      : (val) {
                          dismissKeyboard();
                          setState(() => _readOnly = val);
                        },
                  title: Text(
                    context.l10n.readOnlyModeLabel,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    context.l10n.readOnlyModeContainerSubtitle,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  secondary: Icon(Icons.visibility_outlined, color: cs.primary, size: 22),
                ),
              ],
              if (widget.initialUri == null) ...[
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  value: _remember,
                  onChanged: _loading
                      ? null
                      : (val) {
                          dismissKeyboard();
                          setState(() => _remember = val);
                        },
                  title: Text(
                    context.l10n.rememberContainerLabel,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    context.l10n.rememberContainerSubtitle,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  secondary: Icon(Icons.push_pin_outlined, color: cs.primary, size: 22),
                ),
              ],
            ],
          ),
        ];

      default:
        return const [];
    }
  }

  // ── ADVANCED OPTIONS (VERACRYPT & LUKS) ────────────────────────────────────

  Widget _buildCollapsibleAdvancedCard(BuildContext context, ColorScheme cs, TextTheme textTheme) {
    return SectionCard(
      children: [
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            leading: Icon(Icons.tune_rounded, size: 20, color: cs.primary),
            title: Text(
              context.l10n.advancedOptionsTitle,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            children: _buildAdvancedOptionsSection(context, cs, textTheme),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAdvancedOptionsSection(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: KeyfilesPicker(
          keyfiles: keyfiles,
          picking: pickingKeyfiles,
          onPick: pickKeyfiles,
          onRemove: removeKeyfile,
        ),
      ),
      if (_isLuks && keyfiles.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Text(
            context.l10n.luksKeyfileReplacesPasswordNote,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      if (_isVeraCrypt) ...[
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
      ],
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          context.l10n.readOnlyModeContainerSubtitle,
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        secondary: Icon(Icons.visibility_outlined, color: cs.primary, size: 22),
      ),
      if (_isVeraCrypt) ...[
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _readOnly
                ? context.l10n.readOnlyModeContainerSubtitle
                : context.l10n.protectHiddenVolumeToggleSubtitle,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          secondary: Icon(Icons.shield_outlined, color: cs.primary, size: 22),
        ),
        if (_protectHiddenVolume && !_readOnly) ...[
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _hiddenPasswordCtrl,
              obscureText: _hiddenObscure,
              enabled: !_loading,
              autofillHints: null,
              decoration: InputDecoration(
                filled: true,
                fillColor: cs.surfaceContainerHighest,
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
    ];
  }

  // ── RIGHT PANE (WIDE/LANDSCAPE) ───────────────────────────────────────────

  Widget _buildRightPane(BuildContext context, ColorScheme cs, TextTheme textTheme) {
    switch (_credentialState) {
      case _UnlockCredentialState.loading:
        return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));

      case _UnlockCredentialState.pattern:
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: PatternLockView(
              key: ValueKey(_patternResetKey),
              onPatternComplete: onPatternComplete,
              showError: _patternError,
            ),
          ),
        );

      case _UnlockCredentialState.pin:
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: PinLockView(
              key: ValueKey(_pinResetKey),
              onPinComplete: onPinComplete,
              showError: _pinError,
            ),
          ),
        );

      case _UnlockCredentialState.biometric:
        return Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.fingerprint_rounded, size: 56, color: cs.primary),
          ),
        );

      case _UnlockCredentialState.password:
      default:
        if (!_hasAdvancedSettings) return const SizedBox.shrink();
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                children: _buildAdvancedOptionsSection(context, cs, textTheme),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildVaultKindSegmentedButton(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      segments: [
        ButtonSegment(
          value: 'container',
          label: Text(
            context.l10n.vaultKindContainerFile,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
          ),
          icon: const Icon(Icons.folder_zip_rounded, size: 16),
        ),
        ButtonSegment(
          value: 'directory_vault',
          label: Text(
            context.l10n.vaultKindFolderVault,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
          ),
          icon: const Icon(Icons.folder_shared_rounded, size: 16),
        ),
      ],
      selected: {_isFolderVault ? 'directory_vault' : 'container'},
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

  String _formatBadgeLabel(BuildContext context) {
    if (_isLuks) return context.l10n.formatContainerLabel('LUKS');
    if (_isCryptomator) return context.l10n.formatVaultLabel('Cryptomator');
    if (_isGocryptfs) return context.l10n.formatVaultLabel('Gocryptfs');
    if (_isCryfs) return context.l10n.formatVaultLabel('CryFS');
    if (_isBitlocker) return context.l10n.formatContainerLabel('BitLocker');
    if (_containerFormat == 'veracrypt') return context.l10n.formatContainerLabel('VeraCrypt');
    return context.l10n.encryptedContainerLabel;
  }

  // ── PRIMARY ACTION SECTION ─────────────────────────────────────────────────

  List<Widget> _buildPrimaryActionSection(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    if (_credentialState != _UnlockCredentialState.password &&
        _credentialState != _UnlockCredentialState.fallbackError) {
      return const [];
    }

    final isButtonEnabled = _selectedUri != null;

    return [
      if (_error != null) ...[
        const SizedBox(height: 10),
        InlineErrorBanner(_error!),
      ],
      if (_credentialState == _UnlockCredentialState.password) ...[
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _loading
              ? () {} // Active no-op callback while loading so button stays primary blue with white text/spinner
              : (isButtonEnabled ? () => _unlock() : null),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: const StadiumBorder(),
            disabledForegroundColor: cs.onSurface.withValues(alpha: 0.55),
            disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
          ),
          child: _loading
              ? Text(
                  _unlockProgressLabel,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: textTheme.titleSmall?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Text(
                  _isFolderVault
                      ? context.l10n.unlockVaultButtonLabel
                      : context.l10n.unlockContainerLabel,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isButtonEnabled
                        ? cs.onPrimary
                        : cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
        ),
        if (_loading && _activeVolId != null) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => vaultExplorerApi.cancelUnlock(_activeVolId!),
              child: Text(
                context.l10n.cancelUnlockButtonLabel,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
          ),
        ],
      ],
    ];
  }
}