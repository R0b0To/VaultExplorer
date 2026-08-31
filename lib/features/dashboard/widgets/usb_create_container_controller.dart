import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'usb_create_container_controller.g.dart';

class UsbCreateContainerState {
  final int currentStep;
  final List<UsbDeviceInfo> devices;
  final UsbDeviceInfo? selected;
  final bool loadingDevices;
  final bool requestingPermission;
  final bool creating;
  final String? error;
  final String sizeUnit;
  final String fileSystem;
  final int cipherId;
  final int hashId;
  final bool quickFormat;
  final bool enableHiddenVolume;
  final String hiddenSizeUnit;
  final String hiddenFileSystem;
  final int hiddenCipherId;
  final int hiddenHashId;
  final int? usableCapacityBytes;
  final bool fetchingCapacity;
  final CreateFormat format;
  final List<KeyfileRef> outerKeyfiles;
  final bool pickingOuterKeyfiles;
  final List<KeyfileRef> hiddenKeyfiles;
  final bool pickingHiddenKeyfiles;
  final String? suggestedSizeText;

  bool get busy => creating || requestingPermission;

  const UsbCreateContainerState({
    this.currentStep = 0,
    this.devices = const [],
    this.selected,
    this.loadingDevices = true,
    this.requestingPermission = false,
    this.creating = false,
    this.error,
    this.sizeUnit = 'MB',
    this.fileSystem = 'exFAT',
    this.cipherId = 0,
    this.hashId = 0,
    this.quickFormat = true,
    this.enableHiddenVolume = false,
    this.hiddenSizeUnit = 'MB',
    this.hiddenFileSystem = 'FAT',
    this.hiddenCipherId = 0,
    this.hiddenHashId = 0,
    this.usableCapacityBytes,
    this.fetchingCapacity = false,
    this.format = CreateFormat.veracrypt,
    this.outerKeyfiles = const [],
    this.pickingOuterKeyfiles = false,
    this.hiddenKeyfiles = const [],
    this.pickingHiddenKeyfiles = false,
    this.suggestedSizeText,
  });

  UsbCreateContainerState _copy({
    int? currentStep,
    List<UsbDeviceInfo>? devices,
    UsbDeviceInfo? selected,
    bool clearSelected = false,
    bool? loadingDevices,
    bool? requestingPermission,
    bool? creating,
    String? error,
    bool clearError = false,
    String? sizeUnit,
    String? fileSystem,
    int? cipherId,
    int? hashId,
    bool? quickFormat,
    bool? enableHiddenVolume,
    String? hiddenSizeUnit,
    String? hiddenFileSystem,
    int? hiddenCipherId,
    int? hiddenHashId,
    int? usableCapacityBytes,
    bool clearUsableCapacity = false,
    bool? fetchingCapacity,
    CreateFormat? format,
    List<KeyfileRef>? outerKeyfiles,
    bool? pickingOuterKeyfiles,
    List<KeyfileRef>? hiddenKeyfiles,
    bool? pickingHiddenKeyfiles,
    String? suggestedSizeText,
    bool clearSuggestedSizeText = false,
  }) => UsbCreateContainerState(
    currentStep: currentStep ?? this.currentStep,
    devices: devices ?? this.devices,
    selected: clearSelected ? null : (selected ?? this.selected),
    loadingDevices: loadingDevices ?? this.loadingDevices,
    requestingPermission: requestingPermission ?? this.requestingPermission,
    creating: creating ?? this.creating,
    error: clearError ? null : (error ?? this.error),
    sizeUnit: sizeUnit ?? this.sizeUnit,
    fileSystem: fileSystem ?? this.fileSystem,
    cipherId: cipherId ?? this.cipherId,
    hashId: hashId ?? this.hashId,
    quickFormat: quickFormat ?? this.quickFormat,
    enableHiddenVolume: enableHiddenVolume ?? this.enableHiddenVolume,
    hiddenSizeUnit: hiddenSizeUnit ?? this.hiddenSizeUnit,
    hiddenFileSystem: hiddenFileSystem ?? this.hiddenFileSystem,
    hiddenCipherId: hiddenCipherId ?? this.hiddenCipherId,
    hiddenHashId: hiddenHashId ?? this.hiddenHashId,
    usableCapacityBytes: clearUsableCapacity ? null : (usableCapacityBytes ?? this.usableCapacityBytes),
    fetchingCapacity: fetchingCapacity ?? this.fetchingCapacity,
    format: format ?? this.format,
    outerKeyfiles: outerKeyfiles ?? this.outerKeyfiles,
    pickingOuterKeyfiles: pickingOuterKeyfiles ?? this.pickingOuterKeyfiles,
    hiddenKeyfiles: hiddenKeyfiles ?? this.hiddenKeyfiles,
    pickingHiddenKeyfiles: pickingHiddenKeyfiles ?? this.pickingHiddenKeyfiles,
    suggestedSizeText: clearSuggestedSizeText ? null : (suggestedSizeText ?? this.suggestedSizeText),
  );
}

@riverpod
class UsbCreateContainer extends _$UsbCreateContainer {
  @override
  UsbCreateContainerState build() {
    final state = const UsbCreateContainerState();
    Future.microtask(loadDevices);
    return state;
  }

  void setCurrentStep(int step) => state = state._copy(currentStep: step);

  void setFormat(CreateFormat format) {
    final defaultFs = (format == CreateFormat.luks1 || format == CreateFormat.luks2) ? 'ext4' : 'exFAT';
    final cipherChoices = switch (format) {
      CreateFormat.veracrypt => CipherAlgo.concrete,
      CreateFormat.luks1 => CipherAlgo.luks1Choices,
      CreateFormat.luks2 => CipherAlgo.luks2Choices,
    };
    final hashChoices = switch (format) {
      CreateFormat.veracrypt => HashAlgo.concrete,
      CreateFormat.luks1 => HashAlgo.luks1Choices,
      CreateFormat.luks2 => HashAlgo.luks2Choices,
    };

    final newCipherId = cipherChoices.any((c) => c.id == state.cipherId)
        ? state.cipherId
        : cipherChoices.first.id;
    final newHashId = hashChoices.any((h) => h.id == state.hashId)
        ? state.hashId
        : hashChoices.first.id;

    state = state._copy(
      format: format,
      fileSystem: defaultFs,
      cipherId: newCipherId,
      hashId: newHashId,
      enableHiddenVolume: format == CreateFormat.veracrypt ? state.enableHiddenVolume : false,
      hiddenFileSystem: 'FAT',
    );
  }

  void setSizeUnit(String unit) => state = state._copy(sizeUnit: unit);

  void setFileSystem(String fs) => state = state._copy(fileSystem: fs);

  void setCipherId(int cipherId) => state = state._copy(cipherId: cipherId);

  void setHashId(int hashId) => state = state._copy(hashId: hashId);

  void setQuickFormat(bool val) => state = state._copy(quickFormat: val);

  void setEnableHiddenVolume(bool val) => state = state._copy(enableHiddenVolume: val);

  void setHiddenSizeUnit(String unit) => state = state._copy(hiddenSizeUnit: unit);

  void setHiddenFileSystem(String fs) => state = state._copy(hiddenFileSystem: fs);

  void setHiddenCipherId(int cipherId) => state = state._copy(hiddenCipherId: cipherId);

  void setHiddenHashId(int hashId) => state = state._copy(hiddenHashId: hashId);

  Future<void> loadDevices() async {
    state = state._copy(loadingDevices: true, clearError: true);
    try {
      final devices = await ref.read(vaultLifecycleApiProvider).listUsbDevices();
      if (!ref.mounted) return;
      state = state._copy(devices: devices, loadingDevices: false);
      if (devices.length == 1) {
        await selectDevice(devices.first, null);
      }
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(loadingDevices: false, error: '$e');
      }
    }
  }

  Future<void> _ensurePermission(UsbDeviceInfo device) async {
    if (device.hasPermission) return;
    state = state._copy(requestingPermission: true);
    final granted = await ref.read(vaultLifecycleApiProvider).requestUsbPermission(device.deviceName);
    if (ref.mounted) {
      state = state._copy(
        requestingPermission: false,
        error: !granted ? 'USB permission denied' : null,
      );
    }
    if (granted) await loadDevices();
  }

  Future<void> selectDevice(UsbDeviceInfo device, AppLocalizations? l10n) async {
    state = state._copy(selected: device, clearSuggestedSizeText: true);
    if (!device.hasPermission) {
      await _ensurePermission(device);
    }

    final refreshed = state.devices.firstWhere(
      (d) => d.deviceName == device.deviceName,
      orElse: () => device,
    );
    if (!refreshed.hasPermission || !ref.mounted) return;

    state = state._copy(fetchingCapacity: true);
    final usable = await ref.read(vaultLifecycleApiProvider).getUsbDeviceCapacity(device.deviceName);
    if (!ref.mounted) return;

    String sizeUnit = state.sizeUnit;
    String? suggestedSizeText;

    if (usable != null && usable > 0) {
      if (usable >= 1024 * 1024 * 1024) {
        sizeUnit = 'GB';
        suggestedSizeText = (usable / (1024 * 1024 * 1024)).toStringAsFixed(2);
      } else {
        sizeUnit = 'MB';
        suggestedSizeText = (usable / (1024 * 1024)).floor().toString();
      }
    }

    state = state._copy(
      fetchingCapacity: false,
      usableCapacityBytes: usable,
      sizeUnit: sizeUnit,
      suggestedSizeText: suggestedSizeText,
      error: (usable == null || usable <= 0) ? l10n?.couldNotReadDriveCapacity : null,
    );
  }

  Future<void> pickOuterKeyfiles() async {
    state = state._copy(pickingOuterKeyfiles: true, clearError: true);
    try {
      final picked = await ref.read(vaultLifecycleApiProvider).pickKeyfiles();
      if (!ref.mounted) return;
      if (picked.isNotEmpty) {
        final existing = state.outerKeyfiles.map((k) => k.uri).toSet();
        final newKeyfiles = List<KeyfileRef>.from(state.outerKeyfiles);
        for (final k in picked) {
          if (existing.add(k.uri)) newKeyfiles.add(k);
        }
        state = state._copy(outerKeyfiles: newKeyfiles, pickingOuterKeyfiles: false);
      } else {
        state = state._copy(pickingOuterKeyfiles: false);
      }
    } catch (_) {
      if (ref.mounted) state = state._copy(pickingOuterKeyfiles: false);
    }
  }

  void removeOuterKeyfile(KeyfileRef keyfile) {
    final newKeyfiles = state.outerKeyfiles.where((k) => k != keyfile).toList();
    state = state._copy(outerKeyfiles: newKeyfiles);
  }

  Future<void> pickHiddenKeyfiles() async {
    state = state._copy(pickingHiddenKeyfiles: true, clearError: true);
    try {
      final picked = await ref.read(vaultLifecycleApiProvider).pickKeyfiles();
      if (!ref.mounted) return;
      if (picked.isNotEmpty) {
        final existing = state.hiddenKeyfiles.map((k) => k.uri).toSet();
        final newKeyfiles = List<KeyfileRef>.from(state.hiddenKeyfiles);
        for (final k in picked) {
          if (existing.add(k.uri)) newKeyfiles.add(k);
        }
        state = state._copy(hiddenKeyfiles: newKeyfiles, pickingHiddenKeyfiles: false);
      } else {
        state = state._copy(pickingHiddenKeyfiles: false);
      }
    } catch (_) {
      if (ref.mounted) state = state._copy(pickingHiddenKeyfiles: false);
    }
  }

  void removeHiddenKeyfile(KeyfileRef keyfile) {
    final newKeyfiles = state.hiddenKeyfiles.where((k) => k != keyfile).toList();
    state = state._copy(hiddenKeyfiles: newKeyfiles);
  }

  Future<bool> createUsbContainer({
    required String sizeText,
    required String passwordText,
    required String confirmPasswordText,
    required String pimText,
    required String hiddenPasswordText,
    required String hiddenConfirmPasswordText,
    required String hiddenPimText,
    required String hiddenSizeText,
    required AppLocalizations l10n,
  }) async {
    final device = state.selected;
    if (device == null) {
      state = state._copy(error: l10n.selectUsbDriveFirst);
      return false;
    }
    final sizeVal = double.tryParse(sizeText);
    if (sizeVal == null || sizeVal <= 0) {
      state = state._copy(error: l10n.enterValidSizeGreaterThanZero);
      return false;
    }
    if (passwordText.isEmpty && state.outerKeyfiles.isEmpty) {
      state = state._copy(error: l10n.passwordOrKeyfileRequired);
      return false;
    }
    if (passwordText.isNotEmpty && passwordText != confirmPasswordText) {
      state = state._copy(error: l10n.standardVolumePasswordsDoNotMatch);
      return false;
    }
    if (state.enableHiddenVolume && state.format == CreateFormat.veracrypt) {
      if (hiddenPasswordText.isNotEmpty && hiddenPasswordText != hiddenConfirmPasswordText) {
        state = state._copy(error: l10n.hiddenVolumePasswordsDoNotMatch);
        return false;
      }
    }

    state = state._copy(creating: true, clearError: true);

    try {
      if (!device.hasPermission) {
        await _ensurePermission(device);
        final refreshed = state.devices.firstWhere(
          (d) => d.deviceName == device.deviceName,
          orElse: () => device,
        );
        if (!refreshed.hasPermission) {
          state = state._copy(creating: false, error: l10n.usbPermissionRequiredToContinue);
          return false;
        }
      }

      final multiplier = state.sizeUnit == 'GB' ? 1024 * 1024 * 1024 : 1024 * 1024;
      final sizeBytes = (sizeVal * multiplier).round();
      final pim = clampPim(pimText.isEmpty ? 0 : int.tryParse(pimText) ?? 0);
      int hiddenSizeBytes = 0;

      if (state.enableHiddenVolume && state.format == CreateFormat.veracrypt) {
        final hiddenPimClamped =
            clampPim(hiddenPimText.isEmpty ? 0 : int.tryParse(hiddenPimText) ?? 0);
        final validation = validateHiddenVolume(
          hiddenSizeText: hiddenSizeText,
          hiddenSizeUnit: state.hiddenSizeUnit,
          outerSizeBytes: sizeBytes,
          outerPimClamped: pim,
          hiddenPimClamped: hiddenPimClamped,
          outerPassword: passwordText,
          hiddenPassword: hiddenPasswordText,
          hasHiddenKeyfiles: state.hiddenKeyfiles.isNotEmpty,
          outerKeyfileUris: state.outerKeyfiles.map((k) => k.uri).toSet(),
          hiddenKeyfileUris: state.hiddenKeyfiles.map((k) => k.uri).toSet(),
          l10n: l10n,
        );
        if (!validation.isValid) {
          state = state._copy(creating: false, error: validation.error);
          return false;
        }
        hiddenSizeBytes = validation.hiddenSizeBytes!;
      }

      final success = await ref.read(vaultLifecycleApiProvider).createUsbContainer(
        deviceName: device.deviceName,
        sizeBytes: sizeBytes,
        password: passwordText,
        pim: pim,
        fileSystem: state.fileSystem.toLowerCase(),
        containerFormat: state.format.id,
        cipherId: state.cipherId,
        hashId: state.hashId,
        keyfilePaths: state.outerKeyfiles.map((k) => k.uri).toList(),
        quickFormat: state.quickFormat,
        createHiddenVolume: state.enableHiddenVolume && state.format == CreateFormat.veracrypt,
        hiddenPassword: hiddenPasswordText,
        hiddenFileSystem: state.hiddenFileSystem.toLowerCase(),
        hiddenSizeBytes: hiddenSizeBytes,
        hiddenKeyfilePaths: state.hiddenKeyfiles.map((k) => k.uri).toList(),
        hiddenPim: (state.enableHiddenVolume && state.format == CreateFormat.veracrypt)
            ? clampPim(hiddenPimText.isEmpty ? 0 : int.tryParse(hiddenPimText) ?? 0)
            : 0,
        hiddenCipherId:
            (state.enableHiddenVolume && state.format == CreateFormat.veracrypt) ? state.hiddenCipherId : 255,
        hiddenHashId:
            (state.enableHiddenVolume && state.format == CreateFormat.veracrypt) ? state.hiddenHashId : 255,
      );

      if (!ref.mounted) return false;
      if (success) {
        state = state._copy(creating: false);
        return true;
      } else {
        state = state._copy(creating: false, error: l10n.usbContainerCreationFailed);
        return false;
      }
    } on PlatformException catch (e) {
      if (ref.mounted) {
        state = state._copy(creating: false, error: e.message ?? l10n.unknownErrorOccurred);
      }
      return false;
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(creating: false, error: '$e');
      }
      return false;
    }
  }
}