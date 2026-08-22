import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'unlock_biometric_mixin.dart';
import 'unlock_biometric_source.dart';

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
  int _cipherId = 255;
  int _hashId = 255;
  bool _remember = false;

  // "Protect hidden volume against damage caused by writing to the outer
  // volume" (advanced unlock option). Only shown/submitted for VeraCrypt
  // containers -- gated in build() by the same `!_isLuks && !_isBitlocker`
  // condition already used for the outer AdvancedParamsPanel.
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

  String _containerFormat = 'veracrypt';
  bool get _isLuks => ContainerFormat.isLuksWire(_containerFormat);
  bool get _isBitlocker => ContainerFormat.isBitlockerWire(_containerFormat);
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
  String get debugLogTag => 'usb unlock';

  String? get _expectedDeviceName {
    final uri = widget.existingRecord?.uri;
    if (uri == null || !uri.startsWith('usb:')) return null;
    return uri.substring(4);
  }

  bool get _passwordPrefilled =>
      widget.prefillPassword != null &&
      _passwordCtrl.text == widget.prefillPassword;

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
    return p.total > 1
        ? context.l10n.veracryptAlgoProgress(algo, slotName)
        : context.l10n.veracryptAlgoProgress(algo, slotName);
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
      if (record.unlockMethod == ContainerUnlockMethod.rememberPassword &&
          record.keyfiles.isNotEmpty) {
        keyfiles.addAll(record.keyfiles.map((k) => (uri: k['uri']!, displayName: k['name']!)));
      }
      if (_unlockMethod == ContainerUnlockMethod.pattern) {
        _storedPatternHash = await ContainerRepository.instance.getPatternHash(record.uri);
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
    } catch (_) {
      if (mounted) setState(() => _loadingAuth = false);
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
    setState(() { _unlocking = true; _error = null; _activeVolId = null; _progress = null; });
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final busy = _unlocking || _requestingPermission;
    final isReconnect = widget.existingRecord != null;
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          isReconnect
              ? context.l10n.reconnectUsbDriveTitle(widget.existingRecord!.label)
              : context.l10n.unlockUsbDriveTitle,
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: dismissKeyboard,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                context.l10n.couldntFindDevice(widget.existingRecord!.label),
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.onTertiaryContainer,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                context.l10n.plugDriveBackInRetry,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onTertiaryContainer.withValues(alpha: 0.85),
                                  height: 1.35,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton.tonalIcon(
                                onPressed: _loadDevices,
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: Text(context.l10n.retryConnectionButton),
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  backgroundColor: cs.surfaceContainerHighest,
                                  foregroundColor: cs.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_devices.isEmpty) ...[
                      Card(
                        elevation: 0,
                        color: cs.surfaceContainerHigh,
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
                                  color: cs.surfaceContainerHighest,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.usb_off_rounded, size: 36, color: cs.onSurfaceVariant),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.l10n.noUsbStorageDetectedTitle,
                                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                context.l10n.connectOtgDriveToMount,
                                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: _loadDevices,
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: Text(context.l10n.refreshDevicesButton),
                                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12, left: 4),
                            child: Text(
                              context.l10n.selectUsbDriveLabel,
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
                                        ? cs.surfaceContainerHigh.withValues(alpha: 0.5)
                                        : isSelected
                                            ? cs.primaryContainer.withValues(alpha: 0.15)
                                            : cs.surfaceContainerHigh,
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
                                                      : cs.surfaceContainerHighest,
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
                                                color: cs.surfaceContainerHighest,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                context.l10n.active,
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
                      const SizedBox(height: 16),
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
                                  context.l10n.biometricAuthenticationTitle,
                                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  context.l10n.biometricAuthUsbSubtitle,
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
                                  _patternError ? context.l10n.wrongPatternTryAgain : context.l10n.connectPatternSequenceToMount,
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
                      else ...[
                        SectionCard(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: TextField(
                                controller: _passwordCtrl,
                                obscureText: _obscure,
                                enabled: !busy,
                                decoration: InputDecoration(
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
                            if (!_isBitlocker)
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
                                      enabled: !busy,
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
                            if (!_isLuks && !_isBitlocker)
                              AdvancedParamsPanel(
                                pimController: _pimCtrl,
                                cipherId: _cipherId,
                                hashId: _hashId,
                                enabled: !busy,
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
                              onChanged: busy
                                  ? null
                                  : (val) {
                                      dismissKeyboard();
                                      setState(() {
                                        _readOnly = val;
                                        // Protection is meaningless (and its
                                        // fields are hidden) while mounting
                                        // read-only -- clear it so a stale
                                        // "on" from before doesn't silently
                                        // ride along if read-only is turned
                                        // off again later.
                                        if (val) _protectHiddenVolume = false;
                                      });
                                    },
                              title: Text(
                                context.l10n.readOnlyModeLabel,
                                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                context.l10n.readOnlyModeUsbSubtitle,
                                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              secondary: Icon(Icons.visibility_outlined, color: cs.primary),
                            ),
                            if (!_isLuks && !_isBitlocker) ...[
                              SwitchListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                value: _protectHiddenVolume && !_readOnly,
                                onChanged: (busy || _readOnly)
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
                                      ? context.l10n.readOnlyModeUsbSubtitle
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
                                    enabled: !busy,
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
                                    enabled: !busy,
                                  ),
                                ),
                                AdvancedParamsPanel(
                                  pimController: _hiddenPimCtrl,
                                  cipherId: _hiddenCipherId,
                                  hashId: _hiddenHashId,
                                  enabled: !busy,
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
                            if (!isReconnect)
                              SwitchListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                value: _remember,
                                onChanged: busy ? null : (val) => setState(() => _remember = val),
                                title: Text(
                                  context.l10n.rememberDriveLabel,
                                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  context.l10n.rememberDriveSubtitle,
                                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                                secondary: Icon(Icons.push_pin_outlined, color: cs.primary),
                              ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          InlineErrorBanner(_error!),
                        ],
                        const SizedBox(height: 24),
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
                                        _unlocking ? _unlockProgressLabel : context.l10n.requestingPermission,
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
                                  isReconnect ? context.l10n.unlockAndMountButton : context.l10n.unlockDriveButton,
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
                              child: Text(context.l10n.cancelUnlockButtonLabel),
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
          ),
        ),
      );
  }
}