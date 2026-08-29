// File: lib/features/unlock/usb_unlock_sheet.dart

import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import '../lock/widgets/pattern_lock_view.dart';
import '../lock/widgets/pin_lock_view.dart';
import 'unlock_biometric_mixin.dart';
import 'unlock_biometric_source.dart';

enum _UsbCredentialState {
  loading,
  missing,
  biometric,
  pattern,
  pin,
  password,
  fallbackError,
  none,
}

class UsbUnlockSheet extends StatefulWidget {
  final void Function(MountedContainer container, {ContainerRecord? record}) onMounted;
  final bool documentProvider;
  final List<String> autoMountFolders;
  final ContainerRecord? existingRecord;
  final String? prefillPassword;
  final void Function(MountedContainer container, ContainerRecord migratedRecord, String oldUri)? onReconnected;
  final List<String> mountedUris;

  const UsbUnlockSheet({
    super.key,
    required this.onMounted,
    this.documentProvider = false,
    this.autoMountFolders = const [],
    this.existingRecord,
    this.prefillPassword,
    this.onReconnected,
    this.mountedUris = const [],
  });

  @override
  State<UsbUnlockSheet> createState() => _UsbUnlockSheetState();
}

class _UsbUnlockSheetState extends State<UsbUnlockSheet>
    with KeyfilePickerMixin, UnlockBiometricMixin<UsbUnlockSheet>
    implements UnlockBiometricSource {
  late TextEditingController _passwordCtrl;
  final _pimCtrl = TextEditingController();
  List<UsbDeviceInfo> _devices = [];
  UsbDeviceInfo? _selected;
  bool _obscure = true;
  bool _loadingDevices = true;
  bool _requestingPermission = false;
  bool _loading = false;
  bool _readOnly = false;
  bool _remember = false;
  String? _error;
  int _cipherId = 255;
  int _hashId = 255;
  String _containerFormat = 'veracrypt';

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
  bool get _isBitlocker => ContainerFormat.isBitlockerWire(_containerFormat);
  bool get _isVeraCrypt => !_isLuks && !_isBitlocker;
  bool get _hasAdvancedSettings => _isVeraCrypt || _isLuks;

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
  bool _pinError = false;
  int _pinResetKey = 0;
  String? _storedPinHash;
  bool _loadingAuth = true;
  bool _reconnectTargetMissing = false;
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
  ({bool ready, String? blockMessage}) get preAuthReadiness {
    if (widget.existingRecord == null) return (ready: false, blockMessage: null);
    if (_selected == null) return (ready: false, blockMessage: context.l10n.selectUsbDriveFirst);
    return (ready: true, blockMessage: null);
  }

  @override
  bool get isReadyForPattern => widget.existingRecord != null;

  @override
  bool get isReadyForPin => widget.existingRecord != null;

  @override
  Future<ContainerRecord?> resolveRecord() async => widget.existingRecord;

  @override
  String? get derivedKeyIdentifier => _expectedDeviceName;

  @override
  String get containerUri => widget.existingRecord!.uri;

  @override
  String get biometricPromptSubject => context.l10n.biometricSubjectUsbDrive;

  @override
  String get noSavedCredentialsForBiometricMessage => context.l10n.usbNoSavedCredentialsMessage;

  @override
  String get noSavedCredentialsForPatternMessage => context.l10n.usbNoSavedCredentialsMessage;

  @override
  String get noSavedCredentialsForPinMessage => context.l10n.usbNoSavedCredentialsMessage;

  @override
  String get debugLogTag => 'usb unlock';

  String? get _expectedDeviceName {
    final uri = widget.existingRecord?.uri;
    if (uri == null || !uri.startsWith('usb:')) return null;
    return uri.substring(4);
  }

  bool get _passwordPrefilled =>
      widget.prefillPassword != null && _passwordCtrl.text == widget.prefillPassword;

  String get _unlockProgressLabel {
    final p = _progress;
    if (p == null || p.total <= 0) return context.l10n.decryptingDriveLabel;
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
  void initState() {
    super.initState();
    _passwordCtrl = TextEditingController(text: widget.prefillPassword ?? '');
    if (widget.existingRecord != null) {
      _cipherId = widget.existingRecord!.cipherId;
      _hashId = widget.existingRecord!.hashId;
      _containerFormat = widget.existingRecord!.containerFormat;
      _remember = true;
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
          if (progress.containerFormat.isNotEmpty && progress.containerFormat != 'unknown') {
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
      if (record.unlockMethod == ContainerUnlockMethod.rememberPassword &&
          record.keyfiles.isNotEmpty) {
        keyfiles.addAll(record.keyfiles.map((k) => (uri: k['uri']!, displayName: k['name']!)));
      }
      if (_unlockMethod == ContainerUnlockMethod.pattern) {
        _storedPatternHash = await ContainerRepository.instance.getPatternHash(record.uri);
      }
      if (_unlockMethod == ContainerUnlockMethod.pin) {
        _storedPinHash = await ContainerRepository.instance.getPinHash(record.uri);
      }
      if (mounted) setState(() => _loadingAuth = false);
      if (_unlockMethod == ContainerUnlockMethod.biometrics) {
        if (_loadDevicesFuture != null) {
          await _loadDevicesFuture;
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (mounted && _selected != null && !_reconnectTargetMissing) {
          tryBiometric();
        }
      }
    } catch (e) {
      VeLog.e('UsbUnlockSheet', '_initUnlockMethod failed with error', e);
      if (mounted) setState(() => _loadingAuth = false);
    }
  }

  @override
  void dispose() {
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
          _error = context.l10n.failedToListUsbDevices('$e');
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
        if (!granted) _error = context.l10n.usbPermissionDenied;
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
    List<String>? keyfilePathsOverride,
  }) async {
    final device = _selected;
    if (device == null) {
      setState(() => _error = context.l10n.selectUsbDriveFirst);
      return;
    }
    final newUri = 'usb:${device.deviceName}';
    if (widget.mountedUris.contains(newUri)) {
      setState(() => _error = context.l10n.usbDeviceAlreadyActiveMounted);
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

    setState(() {
      _loading = true;
      _error = null;
      _activeVolId = null;
      _progress = null;
    });

    try {
      if (!device.hasPermission) {
        await _ensurePermission(device);
        final refreshed = _devices.firstWhere((d) => d.deviceName == device.deviceName, orElse: () => device);
        if (!refreshed.hasPermission) {
          setState(() => _error = context.l10n.usbPermissionRequiredToContinue);
          return;
        }
      }
      final pim = clampPim(_pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0);
      final hiddenPim = clampPim(_hiddenPimCtrl.text.isEmpty ? 0 : int.tryParse(_hiddenPimCtrl.text) ?? 0);
      final hiddenKeyfilePaths =
          _hiddenKeyfilesController.keyfiles.map((k) => k.uri).toList();
      final displayName = widget.existingRecord?.label ?? device.productName;
      final appSettings = await AppSettingsService.instance.loadSettings();
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

      var result = resolvedPreservedKey == null
          ? await vaultExplorerApi.unlockUsbContainer(
              device.deviceName,
              effectivePassword,
              pim,
              displayName: displayName,
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
          : await _unlockSwallowingStaleAuthFail(() => vaultExplorerApi.unlockUsbContainer(
              device.deviceName,
              effectivePassword,
              pim,
              displayName: displayName,
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
        await vaultExplorerApi.clearDerivedKey(device.deviceName);
        if (effectivePassword.isEmpty && widget.existingRecord != null) {
          effectivePassword =
              (await ContainerRepository.instance.getPassword(widget.existingRecord!.uri))?.trim() ?? '';
        }
        if (effectivePassword.isNotEmpty || effectiveKeyfilePaths.isNotEmpty) {
          result = await vaultExplorerApi.unlockUsbContainer(
            device.deviceName,
            effectivePassword,
            pim,
            displayName: displayName,
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

      if (result == null) {
        setState(() => _error = context.l10n.incorrectPasswordOrKeyfilesDriveError);
        return;
      }

      await AppSecureStorage.instance.write(key: 'temp_pw_$newUri', value: effectivePassword);
      final tempContainer = MountedContainer(
        uri: newUri,
        displayName: displayName,
        volId: result.volId,
        rootFiles: result.files,
        mountedAt: DateTime.now(),
        totalSpace: 0,
        freeSpace: 0,
        readOnly: _readOnly,
        containerFormat: result.containerFormat,
      );
      final space = await vaultExplorerApi.getSpaceInfo(tempContainer);
      final total = (space != null && space.isNotEmpty) ? space[0] : 0;
      final free = (space != null && space.length > 1) ? space[1] : 0;
      final finalContainer = tempContainer.copyWith(
        totalSpace: total,
        freeSpace: free,
      );
      final existing = widget.existingRecord;
      final newKeyfiles = keyfiles.map((k) => {'uri': k.uri, 'name': k.displayName}).toList();
      if (existing != null && existing.uri != newUri) {
        final savedPassword = await ContainerRepository.instance.getPassword(existing.uri);
        final savedPatternHash = await ContainerRepository.instance.getPatternHash(existing.uri);
        final savedPinHash = await ContainerRepository.instance.getPinHash(existing.uri);
        await ContainerRepository.instance.remove(existing.uri);
        final shouldSaveKeyfiles = existing.unlockMethod == ContainerUnlockMethod.rememberPassword;
        final migratedKeyfiles = shouldSaveKeyfiles ? newKeyfiles : existing.keyfiles;
        final migrated = ContainerRecord(
          uri: newUri,
          label: existing.label,
          rememberPassword: existing.rememberPassword,
          unlockMethod: existing.unlockMethod,
          autoCloseMins: existing.autoCloseMins,
          documentProvider: existing.documentProvider,
          documentProviderFolders: existing.documentProviderFolders,
          thumbnailCacheMode: existing.thumbnailCacheMode,
          cacheDerivedKey: shouldCacheDerivedKey,
          readOnly: _readOnly,
          pendingPassword: savedPassword,
          pendingPatternHash: savedPatternHash,
          pendingPinHash: savedPinHash,
          cipherId: result.matchedCipherId,
          hashId: result.matchedHashId,
          containerFormat: result.containerFormat,
          keyfiles: migratedKeyfiles,
        );
        await ContainerRepository.instance.save(migrated);
        widget.onReconnected?.call(finalContainer, migrated, existing.uri);
      } else if (existing != null) {
        final shouldSaveKeyfiles = existing.unlockMethod == ContainerUnlockMethod.rememberPassword;
        final effectiveKeyfiles = shouldSaveKeyfiles ? newKeyfiles : existing.keyfiles;
        var effectiveExisting = existing;
        if (existing.cipherId != result.matchedCipherId ||
            existing.hashId != result.matchedHashId ||
            existing.containerFormat != result.containerFormat ||
            existing.readOnly != _readOnly ||
            existing.keyfiles != effectiveKeyfiles) {
          effectiveExisting = existing.copyWith(
            cacheDerivedKey: shouldCacheDerivedKey,
            readOnly: _readOnly,
            cipherId: result.matchedCipherId,
            hashId: result.matchedHashId,
            containerFormat: result.containerFormat,
            keyfiles: effectiveKeyfiles,
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
            keyfiles: const [],
          );
          await ContainerRepository.instance.save(savedRecord);
        }
        widget.onMounted(finalContainer, record: savedRecord);
      }
      HapticFeedback.lightImpact();
      TextInput.finishAutofillContext(shouldSave: false);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      final isCancelled = e is PlatformException && e.code == 'CANCELLED';
      if (!isCancelled) {
        setState(() => _error = e is PlatformException ? (e.message ?? e.toString()) : e.toString());
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
    if (widget.existingRecord == null) return true;
    return _unlockMethod == ContainerUnlockMethod.password ||
        _unlockMethod == ContainerUnlockMethod.rememberPassword;
  }

  _UsbCredentialState get _credentialState {
    if (_loadingDevices || _loadingAuth) return _UsbCredentialState.loading;
    if ((widget.existingRecord != null && _reconnectTargetMissing) || _devices.isEmpty) {
      return _UsbCredentialState.missing;
    }
    if (_unlockMethod == ContainerUnlockMethod.biometrics && !_showPasswordFallback) {
      return _UsbCredentialState.biometric;
    }
    if (_unlockMethod == ContainerUnlockMethod.pattern && !_showPasswordFallback) {
      return _UsbCredentialState.pattern;
    }
    if (_unlockMethod == ContainerUnlockMethod.pin && !_showPasswordFallback) {
      return _UsbCredentialState.pin;
    }
    if (_showPasswordUI) return _UsbCredentialState.password;
    if (_error != null) return _UsbCredentialState.fallbackError;
    return _UsbCredentialState.none;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final wideLayout = context.screen.useWideLayout;
    final isReconnect = widget.existingRecord != null;

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
            isReconnect
                ? context.l10n.reconnectUsbDriveTitle(widget.existingRecord!.label)
                : context.l10n.unlockUsbDriveTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (!_loading && !_requestingPermission)
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: context.l10n.refreshDevicesButton,
                onPressed: _loadDevices,
              ),
            const SizedBox(width: 8),
          ],
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
            child: _buildLayout(context, cs, textTheme, wideLayout, isReconnect),
          ),
        ),
      ),
    );
  }

  Widget _buildLayout(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    bool wideLayout,
    bool isReconnect,
  ) {
    final isPatternOrPin = _credentialState == _UsbCredentialState.pattern ||
        _credentialState == _UsbCredentialState.pin;

    // Landscape / Wide 2-column layout
    if (wideLayout) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: USB Picker Card + Prompt/Fallback Card + Primary Action
            Expanded(
              flex: 5,
              child: SingleChildScrollView(
                physics: isPatternOrPin ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDevicePickerCard(context, cs, textTheme, isReconnect),
                    const SizedBox(height: 10),
                    ..._buildLeftPaneCredentialSection(context, cs, textTheme),
                    ..._buildPrimaryActionSection(context, cs, textTheme, isReconnect),
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
              child: _buildRightPane(context, cs, textTheme, isReconnect),
            ),
          ],
        ),
      );
    }

    // Portrait / Standard vertical column layout
    return SingleChildScrollView(
      physics: isPatternOrPin ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDevicePickerCard(context, cs, textTheme, isReconnect),
          const SizedBox(height: 10),
          ..._buildCredentialSection(context, cs, textTheme, isReconnect),
          if (_credentialState == _UsbCredentialState.password && _hasAdvancedSettings) ...[
            const SizedBox(height: 10),
            _buildCollapsibleAdvancedCard(context, cs, textTheme, isReconnect),
          ],
          ..._buildPrimaryActionSection(context, cs, textTheme, isReconnect),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── DEVICE IDENTITY / PICKER CARD ──────────────────────────────────────────

  Widget _buildDevicePickerCard(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    bool isReconnect,
  ) {
    if (_loadingDevices) {
      return const SectionCard(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          ),
        ],
      );
    }

    if (isReconnect && _reconnectTargetMissing) {
      return SectionCard(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.usb_off_rounded, color: cs.error, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.couldntFindDevice(widget.existingRecord!.label),
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
                  context.l10n.plugDriveBackInRetry,
                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: _loadDevices,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    child: Text(
                      context.l10n.retryConnectionButton,
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
      );
    }

    if (_devices.isEmpty) {
      return SectionCard(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            child: Column(
              children: [
                Icon(Icons.usb_off_rounded, size: 36, color: cs.onSurfaceVariant),
                const SizedBox(height: 10),
                Text(
                  context.l10n.noUsbStorageDetectedTitle,
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.connectOtgDriveToMount,
                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _loadDevices,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    context.l10n.refreshDevicesButton,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Text(
            context.l10n.selectUsbDriveLabel,
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _devices.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
          itemBuilder: (context, index) {
            final d = _devices[index];
            final deviceUri = 'usb:${d.deviceName}';
            final isAlreadyMounted = widget.mountedUris.contains(deviceUri);
            final isSelected = _selected?.deviceName == d.deviceName;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              enabled: !_loading && !isAlreadyMounted,
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isSelected
                      ? cs.primaryContainer.withValues(alpha: 0.7)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  isAlreadyMounted ? Icons.lock_outline_rounded : Icons.usb_rounded,
                  size: 22,
                  color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
              ),
              title: Text(
                d.productName,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                isAlreadyMounted
                    ? context.l10n.alreadyActive
                    : d.hasPermission
                        ? context.l10n.readyToUnlock
                        : context.l10n.permissionRequired,
                style: textTheme.bodySmall?.copyWith(
                  color: isAlreadyMounted
                      ? cs.error
                      : d.hasPermission
                          ? cs.primary
                          : cs.onSurfaceVariant,
                  fontWeight: isAlreadyMounted || d.hasPermission ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: isAlreadyMounted
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        context.l10n.active,
                        style: textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                      ),
                    )
                  : Radio<UsbDeviceInfo>(
                      value: d,
                      groupValue: _selected,
                      onChanged: _loading ? null : (v) => setState(() => _selected = v),
                      activeColor: cs.primary,
                    ),
              onTap: (_loading || isAlreadyMounted) ? null : () => setState(() => _selected = d),
            );
          },
        ),
      ],
    );
  }

  // ── CREDENTIALS SECTION (PORTRAIT) ─────────────────────────────────────────

  List<Widget> _buildCredentialSection(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    bool isReconnect,
  ) {
    switch (_credentialState) {
      case _UsbCredentialState.loading:
      case _UsbCredentialState.missing:
        return const [];

      case _UsbCredentialState.biometric:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
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
                      context.l10n.biometricAuthUsbSubtitle,
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

      case _UsbCredentialState.pattern:
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
                          : context.l10n.connectPatternSequenceToMount,
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

      case _UsbCredentialState.pin:
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
                          : context.l10n.enterPinToMount,
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

      case _UsbCredentialState.password:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  autofocus: widget.existingRecord != null && widget.prefillPassword?.isEmpty != false,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _unlock(),
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.visiblePassword,
                  autofillHints: null,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    labelText: context.l10n.passwordFieldLabel,
                    hintText: _isBitlocker
                        ? context.l10n.passwordHintBitlocker
                        : context.l10n.enterUsbPartitionPassword,
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
                    context.l10n.readOnlyModeUsbSubtitle,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  secondary: Icon(Icons.visibility_outlined, color: cs.primary, size: 22),
                ),
              ],
              if (!isReconnect) ...[
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
                    context.l10n.rememberDriveLabel,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    context.l10n.rememberDriveSubtitle,
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

  List<Widget> _buildLeftPaneCredentialSection(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    switch (_credentialState) {
      case _UsbCredentialState.loading:
      case _UsbCredentialState.missing:
        return const [];

      case _UsbCredentialState.biometric:
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
                      context.l10n.biometricAuthUsbSubtitle,
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

      case _UsbCredentialState.pattern:
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
                          : context.l10n.connectPatternSequenceToMount,
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

      case _UsbCredentialState.pin:
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
                          : context.l10n.enterPinToMount,
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

      case _UsbCredentialState.password:
        return [
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  autofocus: widget.existingRecord != null && widget.prefillPassword?.isEmpty != false,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _unlock(),
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.visiblePassword,
                  autofillHints: null,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    labelText: context.l10n.passwordFieldLabel,
                    hintText: _isBitlocker
                        ? context.l10n.passwordHintBitlocker
                        : context.l10n.enterUsbPartitionPassword,
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
                    context.l10n.readOnlyModeUsbSubtitle,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  secondary: Icon(Icons.visibility_outlined, color: cs.primary, size: 22),
                ),
              ],
              if (widget.existingRecord == null) ...[
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
                    context.l10n.rememberDriveLabel,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    context.l10n.rememberDriveSubtitle,
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

  // ── ADVANCED OPTIONS ───────────────────────────────────────────────────────

  Widget _buildCollapsibleAdvancedCard(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    bool isReconnect,
  ) {
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
            children: _buildAdvancedOptionsSection(context, cs, textTheme, isReconnect),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAdvancedOptionsSection(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    bool isReconnect,
  ) {
    return [
      if (!_isBitlocker) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: KeyfilesPicker(
            keyfiles: keyfiles,
            picking: pickingKeyfiles,
            onPick: pickKeyfiles,
            onRemove: removeKeyfile,
            enabled: !_loading,
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
          context.l10n.readOnlyModeUsbSubtitle,
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
                ? context.l10n.readOnlyModeUsbSubtitle
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
      if (!isReconnect) ...[
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          value: _remember,
          onChanged: _loading ? null : (val) => setState(() => _remember = val),
          title: Text(
            context.l10n.rememberDriveLabel,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            context.l10n.rememberDriveSubtitle,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          secondary: Icon(Icons.push_pin_outlined, color: cs.primary, size: 22),
        ),
      ],
    ];
  }

  // ── RIGHT PANE (WIDE/LANDSCAPE) ───────────────────────────────────────────

  Widget _buildRightPane(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    bool isReconnect,
  ) {
    switch (_credentialState) {
      case _UsbCredentialState.loading:
        return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));

      case _UsbCredentialState.pattern:
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

      case _UsbCredentialState.pin:
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

      case _UsbCredentialState.biometric:
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

      case _UsbCredentialState.password:
      default:
        if (!_hasAdvancedSettings) return const SizedBox.shrink();
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                children: _buildAdvancedOptionsSection(context, cs, textTheme, isReconnect),
              ),
            ],
          ),
        );
    }
  }

  // ── PRIMARY ACTION SECTION ─────────────────────────────────────────────────

  List<Widget> _buildPrimaryActionSection(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    bool isReconnect,
  ) {
    if (_credentialState != _UsbCredentialState.password &&
        _credentialState != _UsbCredentialState.fallbackError) {
      return const [];
    }

    final isButtonEnabled = _selected != null && _devices.isNotEmpty;

    return [
      if (_error != null) ...[
        const SizedBox(height: 10),
        InlineErrorBanner(_error!),
      ],
      if (_credentialState == _UsbCredentialState.password) ...[
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _loading
              ? () {} // Active no-op callback while loading so button stays primary styled
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
                  isReconnect ? context.l10n.unlockAndMountButton : context.l10n.unlockDriveButton,
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