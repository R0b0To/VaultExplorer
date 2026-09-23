// Manual (non-codegen) Riverpod Notifier -- see
// password_interchange_providers.dart's doc comment for why this feature
// doesn't use `@riverpod` like most of this app's other controllers.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/password_exchange/exchange_record.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_registry.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_interchange_providers.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_interchange_service.dart';

enum PasswordInterchangeMode { export, import }

class PasswordInterchangeState {
  final PasswordInterchangeMode mode;
  final bool busy;
  final String? error;

  // ── Export ──
  final MountedContainer? exportContainer;
  final String exportFolderPath;
  final bool exportRecursive;
  final PasswordFormatCodec exportFormat;
  final List<ExchangeRecord>? exportCollected;
  final Uint8List? exportedBytes;
  final bool exportSaved;

  // ── Import ──
  final String? importFileName;
  final Uint8List? importBytes;
  final PasswordFormatCodec importFormat;
  final List<ExchangeRecord>? decoded;
  final Set<int> selected;
  final List<String> decodeWarnings;
  final MountedContainer? importContainer;
  final String importFolderPath;
  final bool importMirrorFolders;
  final PasswordImportOutcome? importResult;

  PasswordInterchangeState({
    this.mode = PasswordInterchangeMode.export,
    this.busy = false,
    this.error,
    this.exportContainer,
    this.exportFolderPath = '',
    this.exportRecursive = true,
    PasswordFormatCodec? exportFormat,
    this.exportCollected,
    this.exportedBytes,
    this.exportSaved = false,
    this.importFileName,
    this.importBytes,
    PasswordFormatCodec? importFormat,
    this.decoded,
    this.selected = const {},
    this.decodeWarnings = const [],
    this.importContainer,
    this.importFolderPath = '',
    this.importMirrorFolders = true,
    this.importResult,
  })  : exportFormat = exportFormat ?? kExportablePasswordFormats.first,
        importFormat = importFormat ?? kImportablePasswordFormats.first;

  int get selectedCount => selected.length;

  PasswordInterchangeState copyWith({
    PasswordInterchangeMode? mode,
    bool? busy,
    String? error,
    bool clearError = false,
    MountedContainer? exportContainer,
    String? exportFolderPath,
    bool? exportRecursive,
    PasswordFormatCodec? exportFormat,
    List<ExchangeRecord>? exportCollected,
    bool clearExportCollected = false,
    Uint8List? exportedBytes,
    bool clearExportedBytes = false,
    bool? exportSaved,
    String? importFileName,
    Uint8List? importBytes,
    PasswordFormatCodec? importFormat,
    List<ExchangeRecord>? decoded,
    bool clearDecoded = false,
    Set<int>? selected,
    List<String>? decodeWarnings,
    MountedContainer? importContainer,
    String? importFolderPath,
    bool? importMirrorFolders,
    PasswordImportOutcome? importResult,
    bool clearImportResult = false,
  }) =>
      PasswordInterchangeState(
        mode: mode ?? this.mode,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        exportContainer: exportContainer ?? this.exportContainer,
        exportFolderPath: exportFolderPath ?? this.exportFolderPath,
        exportRecursive: exportRecursive ?? this.exportRecursive,
        exportFormat: exportFormat ?? this.exportFormat,
        exportCollected: clearExportCollected ? null : (exportCollected ?? this.exportCollected),
        exportedBytes: clearExportedBytes ? null : (exportedBytes ?? this.exportedBytes),
        exportSaved: exportSaved ?? this.exportSaved,
        importFileName: importFileName ?? this.importFileName,
        importBytes: importBytes ?? this.importBytes,
        importFormat: importFormat ?? this.importFormat,
        decoded: clearDecoded ? null : (decoded ?? this.decoded),
        selected: selected ?? this.selected,
        decodeWarnings: decodeWarnings ?? this.decodeWarnings,
        importContainer: importContainer ?? this.importContainer,
        importFolderPath: importFolderPath ?? this.importFolderPath,
        importMirrorFolders: importMirrorFolders ?? this.importMirrorFolders,
        importResult: clearImportResult ? null : (importResult ?? this.importResult),
      );
}

class PasswordInterchange extends Notifier<PasswordInterchangeState> {
  @override
  PasswordInterchangeState build() => PasswordInterchangeState();

  void setMode(PasswordInterchangeMode mode) => state = PasswordInterchangeState(mode: mode);

  // ── Export flow ──────────────────────────────────────────────────────────

  void setExportSource({required MountedContainer container, required String folderPath}) {
    state = state.copyWith(
      exportContainer: container,
      exportFolderPath: folderPath,
      clearExportCollected: true,
      clearExportedBytes: true,
      exportSaved: false,
      clearError: true,
    );
  }

  void setExportRecursive(bool value) => state = state.copyWith(exportRecursive: value);

  void setExportFormat(PasswordFormatCodec format) => state = state.copyWith(
        exportFormat: format,
        clearExportedBytes: true,
        exportSaved: false,
      );

  Future<void> runExport({String? password}) async {
    final container = state.exportContainer;
    if (container == null) return;
    final format = state.exportFormat;
    if (format.isEncrypted && (password == null || password.isEmpty)) {
      state = state.copyWith(error: 'A master password is required for this format.');
      return;
    }
    state = state.copyWith(busy: true, clearError: true, clearExportedBytes: true, exportSaved: false);
    try {
      final service = ref.read(passwordInterchangeServiceProvider);
      final records = await service.collectFromVault(
        container: container,
        folderPath: state.exportFolderPath,
        recursive: state.exportRecursive,
      );
      if (records.isEmpty) {
        state = state.copyWith(busy: false, error: 'No password-manager items were found in this folder.');
        return;
      }
      final bytes = await format.encode(records, password: password);
      if (!ref.mounted) return;
      state = state.copyWith(busy: false, exportCollected: records, exportedBytes: bytes);
    } catch (e) {
      if (ref.mounted) state = state.copyWith(busy: false, error: '$e');
    }
  }

  Future<void> saveExportedFile({
    required String? destinationPath,
    required String? destinationTreeUri,
    required String fileName,
  }) async {
    final bytes = state.exportedBytes;
    if (bytes == null) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await ref.read(vaultHashApiProvider).writeExternalFileBytes(
            destinationPath: destinationPath,
            destinationTreeUri: destinationTreeUri,
            fileName: fileName,
            bytes: bytes,
          );
      if (!ref.mounted) return;
      state = state.copyWith(busy: false, exportSaved: true);
    } catch (e) {
      if (ref.mounted) state = state.copyWith(busy: false, error: '$e');
    }
  }

  // ── Import flow ──────────────────────────────────────────────────────────

  Future<void> pickImportFile() async {
    final picked = await ref.read(vaultLifecycleApiProvider).pickCryptoFiles();
    if (picked.isEmpty || !ref.mounted) return;
    final file = picked.first;
    state = PasswordInterchangeState(
      mode: PasswordInterchangeMode.import,
      busy: true,
    );
    try {
      final bytes = await ref.read(vaultHashApiProvider).readExternalFileBytes(file.uri);
      if (bytes == null) {
        if (ref.mounted) {
          state = state.copyWith(busy: false, error: 'Could not read this file.');
        }
        return;
      }
      final guessed = guessPasswordFormat(fileName: file.displayName, bytes: bytes);
      if (!ref.mounted) return;
      state = state.copyWith(
        busy: false,
        importFileName: file.displayName,
        importBytes: bytes,
        importFormat: guessed,
      );
      if (!guessed.isEncrypted) {
        await decodeImportFile();
      }
    } catch (e) {
      if (ref.mounted) state = state.copyWith(busy: false, error: '$e');
    }
  }

  void setImportFormat(PasswordFormatCodec format) => state = state.copyWith(
        importFormat: format,
        clearDecoded: true,
        selected: const {},
      );

  Future<void> decodeImportFile({String? password}) async {
    final bytes = state.importBytes;
    if (bytes == null) return;
    final format = state.importFormat;
    if (format.isEncrypted && (password == null || password.isEmpty)) {
      state = state.copyWith(error: 'A master password is required to open this file.');
      return;
    }
    state = state.copyWith(busy: true, clearError: true, clearDecoded: true);
    try {
      final result = await format.decode(bytes, password: password);
      if (!ref.mounted) return;
      state = state.copyWith(
        busy: false,
        decoded: result.records,
        decodeWarnings: result.warnings,
        selected: {for (var i = 0; i < result.records.length; i++) i},
      );
    } on PasswordFileIncorrectPasswordException {
      if (ref.mounted) {
        state = state.copyWith(busy: false, error: 'Incorrect password, or this file needs a keyfile VaultExplorer doesn\'t support.');
      }
    } catch (e) {
      if (ref.mounted) state = state.copyWith(busy: false, error: '$e');
    }
  }

  void toggleSelected(int index) {
    final next = Set<int>.from(state.selected);
    if (!next.add(index)) next.remove(index);
    state = state.copyWith(selected: next);
  }

  void selectAll() {
    final total = state.decoded?.length ?? 0;
    state = state.copyWith(selected: {for (var i = 0; i < total; i++) i});
  }

  void selectNone() => state = state.copyWith(selected: const {});

  void setImportDestination({required MountedContainer container, required String folderPath}) {
    state = state.copyWith(importContainer: container, importFolderPath: folderPath, clearError: true);
  }

  void setImportMirrorFolders(bool value) => state = state.copyWith(importMirrorFolders: value);

  Future<void> runImport() async {
    final container = state.importContainer;
    final decoded = state.decoded;
    if (container == null || decoded == null || state.selected.isEmpty) return;
    final chosen = [for (var i = 0; i < decoded.length; i++) if (state.selected.contains(i)) decoded[i]];

    state = state.copyWith(busy: true, clearError: true, clearImportResult: true);
    try {
      final outcome = await ref.read(passwordInterchangeServiceProvider).importIntoVault(
            container: container,
            destFolderPath: state.importFolderPath,
            records: chosen,
            mirrorFolders: state.importMirrorFolders,
          );
      if (!ref.mounted) return;
      state = state.copyWith(busy: false, importResult: outcome);
    } on VaultReadOnlyException {
      if (ref.mounted) state = state.copyWith(busy: false, error: 'This container is open read-only.');
    } catch (e) {
      if (ref.mounted) state = state.copyWith(busy: false, error: '$e');
    }
  }

  void reset() => state = PasswordInterchangeState(mode: state.mode);
}

final passwordInterchangeProvider = NotifierProvider<PasswordInterchange, PasswordInterchangeState>(
  PasswordInterchange.new,
);
