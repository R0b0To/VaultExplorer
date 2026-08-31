import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/services/keyfile_passphrase_generator_service.dart';

part 'keyfile_passphrase_generator_controller.g.dart';

enum GeneratorTab { passphrase, keyfile }

enum PassphraseMode { diceware, custom }

enum KeyfileType { binary, image }

class KeyfilePassphraseGeneratorState {
  final GeneratorTab selectedTab;
  final PassphraseMode passphraseMode;

  // Diceware controls
  final int dicewareWordCount;
  final String dicewareSeparator;
  final PasswordCasing dicewareCasing;
  final bool dicewareIncludeNumber;
  final bool dicewareIncludeSymbol;

  // Custom password controls
  final int customLength;
  final bool customUseUppercase;
  final bool customUseLowercase;
  final bool customUseNumbers;
  final bool customUseSymbols;
  final bool customExcludeAmbiguous;

  // Generated passphrase output
  final String generatedPassphrase;
  final double passphraseEntropyBits;
  final bool isLoadingPassphrase;
  final int activePassphraseRequestId;

  // Keyfile State
  final KeyfileType keyfileType;
  final KeyfileSizePreset binaryPreset;
  final ImageKeyfileResolution imagePreset;
  final Uint8List? generatedKeyfileBytes;
  final String keyfileFingerprint;
  final String keyfileSuggestedName;
  final bool isExporting;

  const KeyfilePassphraseGeneratorState({
    this.selectedTab = GeneratorTab.passphrase,
    this.passphraseMode = PassphraseMode.diceware,
    this.dicewareWordCount = 5,
    this.dicewareSeparator = '-',
    this.dicewareCasing = PasswordCasing.lowercase,
    this.dicewareIncludeNumber = false,
    this.dicewareIncludeSymbol = false,
    this.customLength = 24,
    this.customUseUppercase = true,
    this.customUseLowercase = true,
    this.customUseNumbers = true,
    this.customUseSymbols = true,
    this.customExcludeAmbiguous = false,
    this.generatedPassphrase = '',
    this.passphraseEntropyBits = 0.0,
    this.isLoadingPassphrase = false,
    this.activePassphraseRequestId = 0,
    this.keyfileType = KeyfileType.binary,
    this.binaryPreset = KeyfileSizePreset.bytes64,
    this.imagePreset = ImageKeyfileResolution.res256,
    this.generatedKeyfileBytes,
    this.keyfileFingerprint = '',
    this.keyfileSuggestedName = '',
    this.isExporting = false,
  });

  KeyfilePassphraseGeneratorState _copy({
    GeneratorTab? selectedTab,
    PassphraseMode? passphraseMode,
    int? dicewareWordCount,
    String? dicewareSeparator,
    PasswordCasing? dicewareCasing,
    bool? dicewareIncludeNumber,
    bool? dicewareIncludeSymbol,
    int? customLength,
    bool? customUseUppercase,
    bool? customUseLowercase,
    bool? customUseNumbers,
    bool? customUseSymbols,
    bool? customExcludeAmbiguous,
    String? generatedPassphrase,
    double? passphraseEntropyBits,
    bool? isLoadingPassphrase,
    int? activePassphraseRequestId,
    KeyfileType? keyfileType,
    KeyfileSizePreset? binaryPreset,
    ImageKeyfileResolution? imagePreset,
    Uint8List? generatedKeyfileBytes,
    bool setGeneratedKeyfileBytes = false,
    String? keyfileFingerprint,
    String? keyfileSuggestedName,
    bool? isExporting,
  }) => KeyfilePassphraseGeneratorState(
    selectedTab: selectedTab ?? this.selectedTab,
    passphraseMode: passphraseMode ?? this.passphraseMode,
    dicewareWordCount: dicewareWordCount ?? this.dicewareWordCount,
    dicewareSeparator: dicewareSeparator ?? this.dicewareSeparator,
    dicewareCasing: dicewareCasing ?? this.dicewareCasing,
    dicewareIncludeNumber: dicewareIncludeNumber ?? this.dicewareIncludeNumber,
    dicewareIncludeSymbol: dicewareIncludeSymbol ?? this.dicewareIncludeSymbol,
    customLength: customLength ?? this.customLength,
    customUseUppercase: customUseUppercase ?? this.customUseUppercase,
    customUseLowercase: customUseLowercase ?? this.customUseLowercase,
    customUseNumbers: customUseNumbers ?? this.customUseNumbers,
    customUseSymbols: customUseSymbols ?? this.customUseSymbols,
    customExcludeAmbiguous: customExcludeAmbiguous ?? this.customExcludeAmbiguous,
    generatedPassphrase: generatedPassphrase ?? this.generatedPassphrase,
    passphraseEntropyBits: passphraseEntropyBits ?? this.passphraseEntropyBits,
    isLoadingPassphrase: isLoadingPassphrase ?? this.isLoadingPassphrase,
    activePassphraseRequestId: activePassphraseRequestId ?? this.activePassphraseRequestId,
    keyfileType: keyfileType ?? this.keyfileType,
    binaryPreset: binaryPreset ?? this.binaryPreset,
    imagePreset: imagePreset ?? this.imagePreset,
    generatedKeyfileBytes: setGeneratedKeyfileBytes ? generatedKeyfileBytes : (generatedKeyfileBytes ?? this.generatedKeyfileBytes),
    keyfileFingerprint: keyfileFingerprint ?? this.keyfileFingerprint,
    keyfileSuggestedName: keyfileSuggestedName ?? this.keyfileSuggestedName,
    isExporting: isExporting ?? this.isExporting,
  );
}

@riverpod
class KeyfilePassphraseGenerator extends _$KeyfilePassphraseGenerator {
  @override
  KeyfilePassphraseGeneratorState build() {
    final initial = const KeyfilePassphraseGeneratorState();
    Future.microtask(() {
      regeneratePassphrase();
      regenerateKeyfile();
    });
    return initial;
  }

  void setSelectedTab(GeneratorTab tab) =>
      state = state._copy(selectedTab: tab);

  void setPassphraseMode(PassphraseMode mode) {
    state = state._copy(passphraseMode: mode);
    regeneratePassphrase();
  }

  void setDicewareWordCount(int count) =>
      state = state._copy(dicewareWordCount: count);

  void setDicewareSeparator(String sep) {
    state = state._copy(dicewareSeparator: sep);
    regeneratePassphrase();
  }

  void setDicewareCasing(PasswordCasing casing) {
    state = state._copy(dicewareCasing: casing);
    regeneratePassphrase();
  }

  void setDicewareIncludeNumber(bool val) {
    state = state._copy(dicewareIncludeNumber: val);
    regeneratePassphrase();
  }

  void setDicewareIncludeSymbol(bool val) {
    state = state._copy(dicewareIncludeSymbol: val);
    regeneratePassphrase();
  }

  void setCustomLength(int length) =>
      state = state._copy(customLength: length);

  void setCustomUseUppercase(bool val) {
    state = state._copy(customUseUppercase: val);
    regeneratePassphrase();
  }

  void setCustomUseLowercase(bool val) {
    state = state._copy(customUseLowercase: val);
    regeneratePassphrase();
  }

  void setCustomUseNumbers(bool val) {
    state = state._copy(customUseNumbers: val);
    regeneratePassphrase();
  }

  void setCustomUseSymbols(bool val) {
    state = state._copy(customUseSymbols: val);
    regeneratePassphrase();
  }

  void setCustomExcludeAmbiguous(bool val) {
    state = state._copy(customExcludeAmbiguous: val);
    regeneratePassphrase();
  }

  void setKeyfileType(KeyfileType type) {
    state = state._copy(keyfileType: type);
    regenerateKeyfile();
  }

  void setBinaryPreset(KeyfileSizePreset preset) {
    state = state._copy(binaryPreset: preset);
    regenerateKeyfile();
  }

  void setImagePreset(ImageKeyfileResolution preset) {
    state = state._copy(imagePreset: preset);
    regenerateKeyfile();
  }

  Future<void> regeneratePassphrase() async {
    final nextRequestId = state.activePassphraseRequestId + 1;
    state = state._copy(
      isLoadingPassphrase: true,
      activePassphraseRequestId: nextRequestId,
    );

    try {
      if (state.passphraseMode == PassphraseMode.diceware) {
        final res = await KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
          wordCount: state.dicewareWordCount,
          separator: state.dicewareSeparator,
          casing: state.dicewareCasing,
          includeNumber: state.dicewareIncludeNumber,
          includeSymbol: state.dicewareIncludeSymbol,
        );

        if (!ref.mounted || nextRequestId != state.activePassphraseRequestId) return;
        state = state._copy(
          generatedPassphrase: res.passphrase,
          passphraseEntropyBits: res.entropyBits,
          isLoadingPassphrase: false,
        );
      } else {
        final res = KeyfilePassphraseGeneratorService.generateCustomPassword(
          length: state.customLength,
          useUppercase: state.customUseUppercase,
          useLowercase: state.customUseLowercase,
          useNumbers: state.customUseNumbers,
          useSymbols: state.customUseSymbols,
          excludeAmbiguous: state.customExcludeAmbiguous,
        );

        if (!ref.mounted || nextRequestId != state.activePassphraseRequestId) return;
        state = state._copy(
          generatedPassphrase: res.password,
          passphraseEntropyBits: res.entropyBits,
          isLoadingPassphrase: false,
        );
      }
    } catch (e, stack) {
      debugPrint('Error generating passphrase: $e\n$stack');
      if (!ref.mounted || nextRequestId != state.activePassphraseRequestId) return;
      state = state._copy(
        isLoadingPassphrase: false,
        generatedPassphrase: '',
        passphraseEntropyBits: 0.0,
      );
    }
  }

  Future<void> regenerateKeyfile() async {
    try {
      final hashApi = ref.read(vaultHashApiProvider);
      final nowStr = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
      if (state.keyfileType == KeyfileType.binary) {
        final bytes = KeyfilePassphraseGeneratorService.generateBinaryKeyfile(
          state.binaryPreset.bytes,
        );
        final fp = await KeyfilePassphraseGeneratorService.calculateKeyfileFingerprint(
          hashApi,
          bytes,
        );
        if (!ref.mounted) return;
        state = state._copy(
          setGeneratedKeyfileBytes: true,
          generatedKeyfileBytes: bytes,
          keyfileFingerprint: fp,
          keyfileSuggestedName: 'vault_keyfile_$nowStr.key',
        );
      } else {
        final bytes = await KeyfilePassphraseGeneratorService.generateImageKeyfile(
          state.imagePreset.dimension,
        );
        final fp = await KeyfilePassphraseGeneratorService.calculateKeyfileFingerprint(
          hashApi,
          bytes,
        );
        if (!ref.mounted) return;
        state = state._copy(
          setGeneratedKeyfileBytes: true,
          generatedKeyfileBytes: bytes,
          keyfileFingerprint: fp,
          keyfileSuggestedName: 'vault_keyfile_${state.imagePreset.dimension}x${state.imagePreset.dimension}_$nowStr.png',
        );
      }
    } catch (e, stack) {
      debugPrint('Error generating keyfile: $e\n$stack');
    }
  }

  Future<String?> exportKeyfileToStorage() async {
    final bytes = state.generatedKeyfileBytes;
    if (bytes == null) return null;

    final folder = await ref.read(vaultLifecycleApiProvider).pickExtractFolder();
    if (folder == null || !ref.mounted) return null;

    state = state._copy(isExporting: true);
    try {
      await ref.read(vaultHashApiProvider).writeExternalFileBytes(
        destinationPath: folder.path,
        destinationTreeUri: folder.treeUri,
        fileName: state.keyfileSuggestedName,
        bytes: bytes,
      );
      return '${folder.displayName}/${state.keyfileSuggestedName}';
    } finally {
      if (ref.mounted) state = state._copy(isExporting: false);
    }
  }

  Future<bool> saveKeyfileToMountedVault(MountedContainer vault) async {
    final bytes = state.generatedKeyfileBytes;
    if (bytes == null) return false;

    state = state._copy(isExporting: true);
    try {
      final vaultPath = '/${state.keyfileSuggestedName}';
      final ok = await ref.read(vaultFileIoApiProvider).writeFileChunk(
        vault,
        vaultPath,
        0,
        bytes,
      );
      return ok;
    } finally {
      if (ref.mounted) state = state._copy(isExporting: false);
    }
  }
}
