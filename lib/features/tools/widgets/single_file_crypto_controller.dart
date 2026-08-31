import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'single_file_crypto_controller.g.dart';

class SingleFileCryptoResult {
  final int succeeded;
  final int totalFiles;
  final int failedCount;

  bool get isFullSuccess => failedCount == 0;

  const SingleFileCryptoResult({
    required this.succeeded,
    required this.totalFiles,
    required this.failedCount,
  });
}

class SingleFileCryptoState {
  final CryptoDirection direction;
  final StandaloneCipher cipher;
  final List<CryptoSourceItem> sources;
  final CryptoDestination? destination;
  final List<KeyfileRef> keyfiles;
  final bool pickingKeyfiles;
  final bool deleteOriginal;
  final bool busy;
  final String? error;
  final int currentIndex;
  final int? progressDone;
  final int? progressTotal;

  const SingleFileCryptoState({
    this.direction = CryptoDirection.encrypt,
    this.cipher = StandaloneCipher.xChaCha20Poly1305,
    this.sources = const [],
    this.destination,
    this.keyfiles = const [],
    this.pickingKeyfiles = false,
    this.deleteOriginal = false,
    this.busy = false,
    this.error,
    this.currentIndex = 0,
    this.progressDone,
    this.progressTotal,
  });

  SingleFileCryptoState _copy({
    CryptoDirection? direction,
    StandaloneCipher? cipher,
    List<CryptoSourceItem>? sources,
    CryptoDestination? destination,
    bool setDestination = false,
    List<KeyfileRef>? keyfiles,
    bool? pickingKeyfiles,
    bool? deleteOriginal,
    bool? busy,
    String? error,
    bool clearError = false,
    int? currentIndex,
    int? progressDone,
    int? progressTotal,
    bool resetProgress = false,
  }) => SingleFileCryptoState(
    direction: direction ?? this.direction,
    cipher: cipher ?? this.cipher,
    sources: sources ?? this.sources,
    destination: setDestination ? destination : (destination ?? this.destination),
    keyfiles: keyfiles ?? this.keyfiles,
    pickingKeyfiles: pickingKeyfiles ?? this.pickingKeyfiles,
    deleteOriginal: deleteOriginal ?? this.deleteOriginal,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    currentIndex: currentIndex ?? this.currentIndex,
    progressDone: resetProgress ? progressDone : (progressDone ?? this.progressDone),
    progressTotal: resetProgress ? progressTotal : (progressTotal ?? this.progressTotal),
  );
}

@riverpod
class SingleFileCrypto extends _$SingleFileCrypto {
  @override
  SingleFileCryptoState build(
    List<CryptoSourceItem>? initialSources,
    CryptoDestination? initialDestination,
    CryptoDirection? initialDirection,
  ) {
    return SingleFileCryptoState(
      sources: initialSources != null
          ? List<CryptoSourceItem>.unmodifiable(initialSources)
          : const [],
      destination: initialDestination,
      direction: initialDirection ?? CryptoDirection.encrypt,
    );
  }

  void setDirection(CryptoDirection dir) =>
      state = state._copy(direction: dir, clearError: true);

  void setCipher(StandaloneCipher cipher) =>
      state = state._copy(cipher: cipher);

  void setDeleteOriginal(bool val) =>
      state = state._copy(deleteOriginal: val);

  Future<void> addExternalSources() async {
    final picked = await ref.read(vaultLifecycleApiProvider).pickCryptoFiles();
    if (picked.isEmpty || !ref.mounted) return;
    final existingIds = state.sources.map((f) => f.id).toSet();
    final newSources = List<CryptoSourceItem>.from(state.sources);
    for (final file in picked) {
      final item = CryptoSourceItem.external(
        displayName: file.displayName,
        externalUri: file.uri,
      );
      if (existingIds.add(item.id)) {
        newSources.add(item);
      }
    }
    state = state._copy(sources: newSources, clearError: true);
  }

  void addSources(List<CryptoSourceItem> items) {
    final existingIds = state.sources.map((f) => f.id).toSet();
    final newSources = List<CryptoSourceItem>.from(state.sources);
    for (final item in items) {
      if (existingIds.add(item.id)) {
        newSources.add(item);
      }
    }
    state = state._copy(sources: newSources, clearError: true);
  }

  void removeSource(CryptoSourceItem file) {
    final newSources = state.sources.where((s) => s != file).toList();
    state = state._copy(sources: newSources);
  }

  void clearSources() {
    state = state._copy(sources: const []);
  }

  Future<void> pickExternalDestination() async {
    final picked = await ref.read(vaultLifecycleApiProvider).pickExtractFolder();
    if (picked == null || !ref.mounted) return;
    state = state._copy(
      setDestination: true,
      destination: CryptoDestination.external(
        displayName: picked.displayName,
        externalPath: picked.path,
        externalTreeUri: picked.treeUri,
      ),
      clearError: true,
    );
  }

  void setDestination(CryptoDestination dest) {
    state = state._copy(setDestination: true, destination: dest, clearError: true);
  }

  Future<void> pickKeyfiles() async {
    state = state._copy(pickingKeyfiles: true, clearError: true);
    try {
      final picked = await ref.read(vaultLifecycleApiProvider).pickKeyfiles();
      if (!ref.mounted) return;
      if (picked.isNotEmpty) {
        final existingUris = state.keyfiles.map((k) => k.uri).toSet();
        final newKeyfiles = List<KeyfileRef>.from(state.keyfiles);
        for (final k in picked) {
          if (existingUris.add(k.uri)) {
            newKeyfiles.add(k);
          }
        }
        state = state._copy(keyfiles: newKeyfiles, pickingKeyfiles: false);
      } else {
        state = state._copy(pickingKeyfiles: false);
      }
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(pickingKeyfiles: false, error: '$e');
      }
    }
  }

  void removeKeyfile(KeyfileRef keyfile) {
    final newKeyfiles = state.keyfiles.where((k) => k != keyfile).toList();
    state = state._copy(keyfiles: newKeyfiles);
  }

  Future<SingleFileCryptoResult?> runCrypto({
    required String passphrase,
    required AppLocalizations l10n,
  }) async {
    if (state.sources.isEmpty) {
      state = state._copy(error: l10n.noFileSelectedLabel);
      return null;
    }
    final dest = state.destination;
    if (dest == null) {
      state = state._copy(error: l10n.noFolderSelectedLabel);
      return null;
    }
    if (passphrase.isEmpty && state.keyfiles.isEmpty) {
      state = state._copy(error: l10n.passwordOrKeyfilesRequired);
      return null;
    }

    state = state._copy(
      busy: true,
      clearError: true,
      currentIndex: 0,
      resetProgress: true,
      progressDone: 0,
      progressTotal: null,
    );

    final keyfilePaths = state.keyfiles.map((k) => k.uri).toList();
    final result = await ref.read(containerToolServiceProvider).runBatchFileCrypto(
      direction: state.direction,
      sources: state.sources,
      destination: dest,
      cipher: state.cipher,
      passphrase: passphrase,
      keyfilePaths: keyfilePaths,
      deleteOriginal: state.deleteOriginal,
      onFileStart: (currentIndex, totalFiles) {
        if (!ref.mounted) return;
        state = state._copy(
          currentIndex: currentIndex,
          resetProgress: true,
          progressDone: 0,
          progressTotal: null,
        );
      },
      onFileProgress: (done, total) {
        if (!ref.mounted) return;
        state = state._copy(
          progressDone: done,
          progressTotal: total,
        );
      },
    );

    if (!ref.mounted) return null;

    if (result.abortReason == BatchCryptoAbortReason.notImplemented) {
      state = state._copy(
        busy: false,
        error: l10n.toolNotImplementedYetMessage,
      );
      return null;
    }
    if (result.abortReason == BatchCryptoAbortReason.authFailure) {
      state = state._copy(
        busy: false,
        error: l10n.incorrectPasswordError,
      );
      return null;
    }

    if (result.failedNames.isNotEmpty && result.succeeded == 0) {
      state = state._copy(
        busy: false,
        error: l10n.singleFileCryptoPartialFailureMessage(
          result.succeeded,
          result.totalFiles,
          result.failedNames.length,
        ),
      );
      return null;
    }

    state = state._copy(busy: false);
    return SingleFileCryptoResult(
      succeeded: result.succeeded,
      totalFiles: result.totalFiles,
      failedCount: result.failedNames.length,
    );
  }
}
