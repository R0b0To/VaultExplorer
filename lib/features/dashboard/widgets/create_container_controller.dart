import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'create_container_controller.g.dart';

class CreateContainerState {
  final int currentStep;
  final bool isFolderVault;
  final CreateFormat format;
  final String folderVaultFormat;
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
  final String gocryptfsCipher;
  final String cryfsCipher;
  final int cryfsBlockSize;
  final String? folderVaultUri;
  final String? folderVaultDisplayName;
  final bool pickingFolderVault;
  final List<KeyfileRef> outerKeyfiles;
  final bool pickingOuterKeyfiles;
  final List<KeyfileRef> hiddenKeyfiles;
  final bool pickingHiddenKeyfiles;
  final bool loading;
  final String? error;

  const CreateContainerState({
    this.currentStep = 0,
    this.isFolderVault = false,
    this.format = CreateFormat.veracrypt,
    this.folderVaultFormat = 'cryptomator',
    this.sizeUnit = 'MB',
    this.fileSystem = 'FAT',
    this.cipherId = 0,
    this.hashId = 0,
    this.quickFormat = true,
    this.enableHiddenVolume = false,
    this.hiddenSizeUnit = 'MB',
    this.hiddenFileSystem = 'FAT',
    this.hiddenCipherId = 0,
    this.hiddenHashId = 0,
    this.gocryptfsCipher = 'aes-256-gcm',
    this.cryfsCipher = 'xchacha20-poly1305',
    this.cryfsBlockSize = 32 * 1024,
    this.folderVaultUri,
    this.folderVaultDisplayName,
    this.pickingFolderVault = false,
    this.outerKeyfiles = const [],
    this.pickingOuterKeyfiles = false,
    this.hiddenKeyfiles = const [],
    this.pickingHiddenKeyfiles = false,
    this.loading = false,
    this.error,
  });

  CreateContainerState _copy({
    int? currentStep,
    bool? isFolderVault,
    CreateFormat? format,
    String? folderVaultFormat,
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
    String? gocryptfsCipher,
    String? cryfsCipher,
    int? cryfsBlockSize,
    String? folderVaultUri,
    bool clearFolderVaultUri = false,
    String? folderVaultDisplayName,
    bool clearFolderVaultDisplayName = false,
    bool? pickingFolderVault,
    List<KeyfileRef>? outerKeyfiles,
    bool? pickingOuterKeyfiles,
    List<KeyfileRef>? hiddenKeyfiles,
    bool? pickingHiddenKeyfiles,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => CreateContainerState(
    currentStep: currentStep ?? this.currentStep,
    isFolderVault: isFolderVault ?? this.isFolderVault,
    format: format ?? this.format,
    folderVaultFormat: folderVaultFormat ?? this.folderVaultFormat,
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
    gocryptfsCipher: gocryptfsCipher ?? this.gocryptfsCipher,
    cryfsCipher: cryfsCipher ?? this.cryfsCipher,
    cryfsBlockSize: cryfsBlockSize ?? this.cryfsBlockSize,
    folderVaultUri: clearFolderVaultUri ? null : (folderVaultUri ?? this.folderVaultUri),
    folderVaultDisplayName: clearFolderVaultDisplayName ? null : (folderVaultDisplayName ?? this.folderVaultDisplayName),
    pickingFolderVault: pickingFolderVault ?? this.pickingFolderVault,
    outerKeyfiles: outerKeyfiles ?? this.outerKeyfiles,
    pickingOuterKeyfiles: pickingOuterKeyfiles ?? this.pickingOuterKeyfiles,
    hiddenKeyfiles: hiddenKeyfiles ?? this.hiddenKeyfiles,
    pickingHiddenKeyfiles: pickingHiddenKeyfiles ?? this.pickingHiddenKeyfiles,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

@riverpod
class CreateContainer extends _$CreateContainer {
  @override
  CreateContainerState build() => const CreateContainerState();

  void setCurrentStep(int step) => state = state._copy(currentStep: step);

  void setVaultKind(bool folderVault) =>
      state = state._copy(isFolderVault: folderVault, clearError: true);

  void setFormat(CreateFormat format) {
    final defaultFs = (format == CreateFormat.luks1 || format == CreateFormat.luks2) ? 'ext4' : 'FAT';
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
      hiddenFileSystem: 'FAT',
    );
  }

  void setFolderVaultFormat(String format) {
    state = state._copy(
      folderVaultFormat: format,
      clearFolderVaultUri: true,
      clearFolderVaultDisplayName: true,
      clearError: true,
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

  void setGocryptfsCipher(String cipher) => state = state._copy(gocryptfsCipher: cipher);

  void setCryfsCipher(String cipher) => state = state._copy(cryfsCipher: cipher);

  void setCryfsBlockSize(int blockSize) => state = state._copy(cryfsBlockSize: blockSize);

  void clearFolderVaultLocation() {
    state = state._copy(
      clearFolderVaultUri: true,
      clearFolderVaultDisplayName: true,
    );
  }

  Future<void> pickFolderVaultLocation(AppLocalizations l10n) async {
    state = state._copy(pickingFolderVault: true, clearError: true);
    final lifecycle = ref.read(vaultLifecycleApiProvider);
    try {
      final result = state.folderVaultFormat == 'cryptomator'
          ? await lifecycle.pickCryptomatorVault()
          : state.folderVaultFormat == 'gocryptfs'
              ? await lifecycle.pickGocryptfsVault()
              : await lifecycle.pickCryfsVault();
      if (result != null && ref.mounted) {
        state = state._copy(
          folderVaultUri: result.uri,
          folderVaultDisplayName: result.displayName,
        );
      }
    } catch (e) {
      if (ref.mounted) state = state._copy(error: l10n.folderPickerFailed('$e'));
    } finally {
      if (ref.mounted) state = state._copy(pickingFolderVault: false);
    }
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

  Future<bool> createFolderVault({
    required String password,
    required String confirmPassword,
    required AppLocalizations l10n,
  }) async {
    if (state.folderVaultUri == null) {
      state = state._copy(error: l10n.selectEmptyDestinationFolderFirst);
      return false;
    }
    if (password.isEmpty) {
      state = state._copy(error: l10n.passwordRequired);
      return false;
    }
    if (password != confirmPassword) {
      state = state._copy(error: l10n.passwordsDoNotMatch);
      return false;
    }

    state = state._copy(loading: true, clearError: true);
    final lifecycle = ref.read(vaultLifecycleApiProvider);

    try {
      final success = state.folderVaultFormat == 'cryptomator'
          ? await lifecycle.createCryptomatorVault(state.folderVaultUri!, password)
          : state.folderVaultFormat == 'gocryptfs'
              ? await lifecycle.createGocryptfsVault(
                  state.folderVaultUri!,
                  password,
                  cipher: state.gocryptfsCipher,
                )
              : await lifecycle.createCryfsVault(
                  state.folderVaultUri!,
                  password,
                  cipher: state.cryfsCipher,
                  blockSize: state.cryfsBlockSize,
                );

      if (!ref.mounted) return false;
      if (success) {
        state = state._copy(loading: false);
        return true;
      } else {
        state = state._copy(loading: false, error: l10n.vaultCreationFailedEmptyFolder);
        return false;
      }
    } on PlatformException catch (e) {
      if (ref.mounted) {
        state = state._copy(loading: false, error: e.message ?? l10n.unknownErrorOccurred);
      }
      return false;
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(loading: false, error: '$e');
      }
      return false;
    }
  }

  Future<bool> createContainerFile({
    required String nameText,
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
    if (nameText.isEmpty) {
      state = state._copy(error: l10n.containerNameRequired);
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

    state = state._copy(loading: true, clearError: true);

    try {
      final multiplier = state.sizeUnit == 'GB' ? 1024 * 1024 * 1024 : 1024 * 1024;
      final sizeBytes = (sizeVal * multiplier).round();
      int hiddenSizeBytes = 0;

      if (state.enableHiddenVolume && state.format == CreateFormat.veracrypt) {
        final outerPimClamped = clampPim(pimText.isEmpty ? 0 : int.tryParse(pimText) ?? 0);
        final hiddenPimClamped =
            clampPim(hiddenPimText.isEmpty ? 0 : int.tryParse(hiddenPimText) ?? 0);

        final validation = validateHiddenVolume(
          hiddenSizeText: hiddenSizeText,
          hiddenSizeUnit: state.hiddenSizeUnit,
          outerSizeBytes: sizeBytes,
          outerPimClamped: outerPimClamped,
          hiddenPimClamped: hiddenPimClamped,
          outerPassword: passwordText,
          hiddenPassword: hiddenPasswordText,
          hasHiddenKeyfiles: state.hiddenKeyfiles.isNotEmpty,
          outerKeyfileUris: state.outerKeyfiles.map((k) => k.uri).toSet(),
          hiddenKeyfileUris: state.hiddenKeyfiles.map((k) => k.uri).toSet(),
          l10n: l10n,
        );

        if (!validation.isValid) {
          state = state._copy(loading: false, error: validation.error);
          return false;
        }
        hiddenSizeBytes = validation.hiddenSizeBytes!;
      }

      final pim = clampPim(pimText.isEmpty ? 0 : int.tryParse(pimText) ?? 0);
      final success = await ref.read(vaultLifecycleApiProvider).createContainer(
        displayName: nameText,
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
        hiddenPim: state.enableHiddenVolume
            ? clampPim(hiddenPimText.isEmpty ? 0 : int.tryParse(hiddenPimText) ?? 0)
            : 0,
        hiddenCipherId: state.enableHiddenVolume ? state.hiddenCipherId : 255,
        hiddenHashId: state.enableHiddenVolume ? state.hiddenHashId : 255,
      );

      if (!ref.mounted) return false;
      if (success) {
        state = state._copy(loading: false);
        return true;
      } else {
        state = state._copy(loading: false, error: l10n.containerCreationCancelledOrFailed);
        return false;
      }
    } on PlatformException catch (e) {
      if (ref.mounted) {
        if (e.code == 'INSUFFICIENT_SPACE') {
          final details = e.details;
          final needed = details is Map ? details['neededBytes'] as int? : null;
          final available = details is Map ? details['availableBytes'] as int? : null;
          state = state._copy(
            loading: false,
            error: (needed != null && available != null)
                ? l10n.insufficientSpaceForContainer(formatBytes(needed), formatBytes(available))
                : e.message ?? l10n.unknownErrorOccurred,
          );
        } else {
          state = state._copy(loading: false, error: e.message ?? l10n.unknownErrorOccurred);
        }
      }
      return false;
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(loading: false, error: '$e');
      }
      return false;
    }
  }
}