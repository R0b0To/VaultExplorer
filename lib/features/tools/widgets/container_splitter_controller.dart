// ContainerSplitterSheet was a plain StatefulWidget holding both the
// split-mode and join-mode form state directly as State fields. No family
// key needed -- only one instance of this modal sheet is ever open at a
// time, same shape as QuickPasswordGeneratorSheet/StorageAnalyzerScreen.
//
// The two TextEditingControllers (`_customSizeCtrl`, `_outputNameCtrl`)
// stay local in the widget -- genuinely ephemeral text input. The output
// name field does get programmatically seeded after a pick, so
// [pickFirstPart] returns the derived name directly for the widget to
// apply, rather than routing it through state + ref.listen (simpler for a
// single button-driven action, same shape as LockGateScreen's
// `checkPassword()` returning a value the widget acts on immediately).
//
// `SplitJoinMode` moved here (was a private top-level enum in the screen
// file) since both the controller's state and the widget's UI need it --
// Dart's `_`-privacy doesn't cross files, same reason VaultInfoLoadState
// lives in its controller file instead of the screen.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/container_tool_service.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'container_splitter_controller.g.dart';

enum SplitJoinMode { split, join }

class ContainerSplitterState {
  final SplitJoinMode mode;
  final bool busy;
  final String? error;
  final int? progressDone;
  final int? progressTotal;

  final String? sourceUri;
  final String? sourceName;
  final String? destPath;
  final String? destName;
  final String? destTreeUri;
  final ChunkSizePreset preset;

  final String? firstPartUri;
  final String? firstPartName;
  final String? joinDestPath;
  final String? joinDestName;
  final String? joinDestTreeUri;

  const ContainerSplitterState({
    this.mode = SplitJoinMode.split,
    this.busy = false,
    this.error,
    this.progressDone,
    this.progressTotal,
    this.sourceUri,
    this.sourceName,
    this.destPath,
    this.destName,
    this.destTreeUri,
    this.preset = ChunkSizePreset.cloud8mb,
    this.firstPartUri,
    this.firstPartName,
    this.joinDestPath,
    this.joinDestName,
    this.joinDestTreeUri,
  });

  ContainerSplitterState _copy({
    SplitJoinMode? mode,
    bool? busy,
    String? error,
    bool clearError = false,
    int? progressDone,
    int? progressTotal,
    bool resetProgress = false,
    String? sourceUri,
    String? sourceName,
    String? destPath,
    String? destName,
    String? destTreeUri,
    bool setSplitDestination = false,
    ChunkSizePreset? preset,
    String? firstPartUri,
    String? firstPartName,
    String? joinDestPath,
    String? joinDestName,
    String? joinDestTreeUri,
    bool setJoinDestination = false,
  }) => ContainerSplitterState(
    mode: mode ?? this.mode,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    progressDone: resetProgress ? progressDone : (progressDone ?? this.progressDone),
    progressTotal: resetProgress ? progressTotal : (progressTotal ?? this.progressTotal),
    sourceUri: sourceUri ?? this.sourceUri,
    sourceName: sourceName ?? this.sourceName,
    destPath: setSplitDestination ? destPath : (destPath ?? this.destPath),
    destName: setSplitDestination ? destName : (destName ?? this.destName),
    destTreeUri: setSplitDestination ? destTreeUri : (destTreeUri ?? this.destTreeUri),
    preset: preset ?? this.preset,
    firstPartUri: firstPartUri ?? this.firstPartUri,
    firstPartName: firstPartName ?? this.firstPartName,
    joinDestPath: setJoinDestination ? joinDestPath : (joinDestPath ?? this.joinDestPath),
    joinDestName: setJoinDestination ? joinDestName : (joinDestName ?? this.joinDestName),
    joinDestTreeUri: setJoinDestination ? joinDestTreeUri : (joinDestTreeUri ?? this.joinDestTreeUri),
  );
}

@riverpod
class ContainerSplitter extends _$ContainerSplitter {
  @override
  ContainerSplitterState build() => const ContainerSplitterState();

  void setMode(SplitJoinMode mode) =>
      state = state._copy(mode: mode, clearError: true);

  void setPreset(ChunkSizePreset preset) =>
      state = state._copy(preset: preset);

  Future<void> pickSplitSource() async {
    final picked = await ref.read(vaultLifecycleApiProvider).pickContainer();
    if (picked == null || !ref.mounted) return;
    state = state._copy(
      sourceUri: picked.uri,
      sourceName: picked.displayName,
      clearError: true,
    );
  }

  Future<void> pickSplitDestination() async {
    final picked = await ref.read(vaultLifecycleApiProvider).pickExtractFolder();
    if (picked == null || !ref.mounted) return;
    state = state._copy(
      setSplitDestination: true,
      destPath: picked.path,
      destName: picked.displayName,
      destTreeUri: picked.treeUri,
      clearError: true,
    );
  }

  /// Returns the auto-derived output name (part-suffix stripped) so the
  /// widget can seed its `_outputNameCtrl`, or null if cancelled.
  Future<String?> pickFirstPart() async {
    final picked = await ref.read(vaultLifecycleApiProvider).pickContainer();
    if (picked == null || !ref.mounted) return null;
    state = state._copy(
      firstPartUri: picked.uri,
      firstPartName: picked.displayName,
      clearError: true,
    );
    return _stripPartSuffix(picked.displayName);
  }

  Future<void> pickJoinDestination() async {
    final picked = await ref.read(vaultLifecycleApiProvider).pickExtractFolder();
    if (picked == null || !ref.mounted) return;
    state = state._copy(
      setJoinDestination: true,
      joinDestPath: picked.path,
      joinDestName: picked.displayName,
      joinDestTreeUri: picked.treeUri,
      clearError: true,
    );
  }

  static String _stripPartSuffix(String name) {
    final dotMatch = RegExp(r'\.(\d{3}|part\d+)$', caseSensitive: false);
    return name.replaceFirst(dotMatch, '');
  }

  static int? _resolvedChunkSizeBytes(ChunkSizePreset preset, String customSizeText) {
    if (preset != ChunkSizePreset.custom) {
      return preset.megabytes! * 1000 * 1000;
    }
    final mb = int.tryParse(customSizeText.trim());
    if (mb == null || mb <= 0) return null;
    return mb * 1000 * 1000;
  }

  /// Returns true on success (widget pops the sheet and shows a success
  /// snackbar); false on validation failure or error (message is left in
  /// [ContainerSplitterState.error] for the inline banner).
  Future<bool> runSplit({
    required String customSizeText,
    required AppLocalizations l10n,
  }) async {
    final source = state.sourceUri;
    final treeUri = state.destTreeUri;
    final dest = state.destPath ?? treeUri;
    final chunkBytes = _resolvedChunkSizeBytes(state.preset, customSizeText);

    if (source == null) {
      state = state._copy(error: l10n.noFileSelectedLabel);
      return false;
    }
    if (dest == null) {
      state = state._copy(error: l10n.noFolderSelectedLabel);
      return false;
    }
    if (chunkBytes == null) {
      state = state._copy(error: l10n.splitChunkSizeCustomLabel);
      return false;
    }

    state = state._copy(
      busy: true,
      clearError: true,
      resetProgress: true,
      progressDone: 0,
      progressTotal: null,
    );

    try {
      await ref.read(containerToolServiceProvider).splitContainer(
        sourceUri: source,
        destinationPath: dest,
        destinationTreeUri: treeUri,
        chunkSizeBytes: chunkBytes,
        onProgress: (done, total) {
          if (!ref.mounted) return;
          state = state._copy(progressDone: done, progressTotal: total);
        },
      );
      if (!ref.mounted) return false;
      state = state._copy(busy: false);
      return true;
    } on UnimplementedError {
      if (ref.mounted) {
        state = state._copy(busy: false, error: l10n.toolNotImplementedYetMessage);
      }
      return false;
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(busy: false, error: '$e');
      }
      return false;
    }
  }

  /// Same contract as [runSplit].
  Future<bool> runJoin({
    required String outputNameText,
    required AppLocalizations l10n,
  }) async {
    final firstPart = state.firstPartUri;
    final treeUri = state.joinDestTreeUri;
    final destFolder = state.joinDestPath ?? treeUri;
    final outputName = outputNameText.trim();

    if (firstPart == null) {
      state = state._copy(error: l10n.noFileSelectedLabel);
      return false;
    }
    if (destFolder == null) {
      state = state._copy(error: l10n.noFolderSelectedLabel);
      return false;
    }
    if (outputName.isEmpty) {
      state = state._copy(error: l10n.joinOutputFileNameLabel);
      return false;
    }

    state = state._copy(
      busy: true,
      clearError: true,
      resetProgress: true,
      progressDone: 0,
      progressTotal: null,
    );

    try {
      await ref.read(containerToolServiceProvider).joinContainer(
        firstPartUri: firstPart,
        destinationPath: '$destFolder/$outputName',
        destinationTreeUri: treeUri,
        onProgress: (done, total) {
          if (!ref.mounted) return;
          state = state._copy(progressDone: done, progressTotal: total);
        },
      );
      if (!ref.mounted) return false;
      state = state._copy(busy: false);
      return true;
    } on UnimplementedError {
      if (ref.mounted) {
        state = state._copy(busy: false, error: l10n.toolNotImplementedYetMessage);
      }
      return false;
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(busy: false, error: '$e');
      }
      return false;
    }
  }
}
