import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/hash_operation.dart';
import 'package:vaultexplorer/features/tools/models/hash_verifier_models.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/hash_operation_controller.dart';
import 'package:vaultexplorer/features/tools/services/hash_verifier_service.dart';
import 'package:vaultexplorer/features/tools/services/vault_file_scanner.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'hash_verifier_controller.g.dart';

@Riverpod(keepAlive: true)
HashVerifierService hashVerifierService(Ref ref) {
  final fileIoApi = ref.watch(vaultFileIoApiProvider);
  return HashVerifierService(
    hashApi: ref.watch(vaultHashApiProvider),
    fileIoApi: fileIoApi,
    engineEvents: ref.watch(vaultEngineEventsProvider),
    scanner: VaultFileScanner(fileIoApi),
  );
}

enum HashVerifierMode { compute, verify, vault }
enum HashVerifierVaultAction { compute, verify }

class HashVerifierState {
  final HashVerifierMode mode;

  // ── Compute Mode ──
  final List<CryptoSourceItem> computeSources;
  final Set<HashAlgorithm> algorithms;
  final Map<String, HashComputeResult> computeResults;
  final HashAlgorithm exportAlgorithm;
  final bool computeBusy;
  final int computeIndex;
  final int? computeDone;
  final int? computeTotal;
  final String? computeError;

  // ── Verify Mode ──
  final CryptoSourceItem? manifestSource;
  final List<ManifestEntry> manifestEntries;
  final List<CryptoSourceItem> verifyCandidates;
  final List<VerifyRow> rows;
  final bool loadingManifest;
  final bool verifyBusy;
  final int verifyIndex;
  final int? verifyDone;
  final int? verifyTotal;
  final String? verifyError;

  // ── Vault Mode ──
  final HashVerifierVaultAction? vaultAction;
  final MountedContainer? vaultTarget;
  final Set<HashAlgorithm> vaultAlgorithms;
  final HashAlgorithm vaultExportAlgorithm;
  final HashOperationProgress vaultProgress;
  final String? vaultError;

  bool get vaultBusy =>
      vaultProgress.phase == HashOperationPhase.scanning ||
      vaultProgress.phase == HashOperationPhase.hashing;

  bool get isBusy =>
      computeBusy || verifyBusy || loadingManifest || vaultBusy;

  List<CryptoSourceItem> get extraCandidates {
    final matchedIds = rows.map((r) => r.matchedSource?.id).whereType<String>().toSet();
    return verifyCandidates.where((c) => !matchedIds.contains(c.id)).toList();
  }

  const HashVerifierState({
    this.mode = HashVerifierMode.compute,
    this.computeSources = const [],
    this.algorithms = const {HashAlgorithm.sha256},
    this.computeResults = const {},
    this.exportAlgorithm = HashAlgorithm.sha256,
    this.computeBusy = false,
    this.computeIndex = 0,
    this.computeDone,
    this.computeTotal,
    this.computeError,
    this.manifestSource,
    this.manifestEntries = const [],
    this.verifyCandidates = const [],
    this.rows = const [],
    this.loadingManifest = false,
    this.verifyBusy = false,
    this.verifyIndex = 0,
    this.verifyDone,
    this.verifyTotal,
    this.verifyError,
    this.vaultAction,
    this.vaultTarget,
    this.vaultAlgorithms = const {HashAlgorithm.sha256},
    this.vaultExportAlgorithm = HashAlgorithm.sha256,
    this.vaultProgress = const HashOperationProgress(),
    this.vaultError,
  });

  HashVerifierState _copy({
    HashVerifierMode? mode,
    List<CryptoSourceItem>? computeSources,
    Set<HashAlgorithm>? algorithms,
    Map<String, HashComputeResult>? computeResults,
    HashAlgorithm? exportAlgorithm,
    bool? computeBusy,
    int? computeIndex,
    int? computeDone,
    int? computeTotal,
    bool resetComputeProgress = false,
    String? computeError,
    bool clearComputeError = false,
    CryptoSourceItem? manifestSource,
    bool clearManifestSource = false,
    List<ManifestEntry>? manifestEntries,
    List<CryptoSourceItem>? verifyCandidates,
    List<VerifyRow>? rows,
    bool? loadingManifest,
    bool? verifyBusy,
    int? verifyIndex,
    int? verifyDone,
    int? verifyTotal,
    bool resetVerifyProgress = false,
    String? verifyError,
    bool clearVerifyError = false,
    HashVerifierVaultAction? vaultAction,
    bool clearVaultAction = false,
    MountedContainer? vaultTarget,
    bool clearVaultTarget = false,
    Set<HashAlgorithm>? vaultAlgorithms,
    HashAlgorithm? vaultExportAlgorithm,
    HashOperationProgress? vaultProgress,
    String? vaultError,
    bool clearVaultError = false,
  }) => HashVerifierState(
    mode: mode ?? this.mode,
    computeSources: computeSources ?? this.computeSources,
    algorithms: algorithms ?? this.algorithms,
    computeResults: computeResults ?? this.computeResults,
    exportAlgorithm: exportAlgorithm ?? this.exportAlgorithm,
    computeBusy: computeBusy ?? this.computeBusy,
    computeIndex: computeIndex ?? this.computeIndex,
    computeDone: resetComputeProgress ? computeDone : (computeDone ?? this.computeDone),
    computeTotal: resetComputeProgress ? computeTotal : (computeTotal ?? this.computeTotal),
    computeError: clearComputeError ? null : (computeError ?? this.computeError),
    manifestSource: clearManifestSource ? null : (manifestSource ?? this.manifestSource),
    manifestEntries: manifestEntries ?? this.manifestEntries,
    verifyCandidates: verifyCandidates ?? this.verifyCandidates,
    rows: rows ?? this.rows,
    loadingManifest: loadingManifest ?? this.loadingManifest,
    verifyBusy: verifyBusy ?? this.verifyBusy,
    verifyIndex: verifyIndex ?? this.verifyIndex,
    verifyDone: resetVerifyProgress ? verifyDone : (verifyDone ?? this.verifyDone),
    verifyTotal: resetVerifyProgress ? verifyTotal : (verifyTotal ?? this.verifyTotal),
    verifyError: clearVerifyError ? null : (verifyError ?? this.verifyError),
    vaultAction: clearVaultAction ? null : (vaultAction ?? this.vaultAction),
    vaultTarget: clearVaultTarget ? null : (vaultTarget ?? this.vaultTarget),
    vaultAlgorithms: vaultAlgorithms ?? this.vaultAlgorithms,
    vaultExportAlgorithm: vaultExportAlgorithm ?? this.vaultExportAlgorithm,
    vaultProgress: vaultProgress ?? this.vaultProgress,
    vaultError: clearVaultError ? null : (vaultError ?? this.vaultError),
  );
}

@riverpod
class HashVerifier extends _$HashVerifier {
  late final HashVerifierService _service;
  late final HashOperationController _opController;

  HashCancellationToken? _computeToken;
  HashCancellationToken? _verifyToken;
  HashCancellationToken? _vaultToken;
  VaultScanSession? _vaultSession;

  @override
  HashVerifierState build() {
    _service = ref.read(hashVerifierServiceProvider);
    _opController = HashOperationController(
      hashService: _service,
      scanner: VaultFileScanner(ref.read(vaultFileIoApiProvider)),
    );
    ref.onDispose(() {
      _computeToken?.cancel();
      _verifyToken?.cancel();
      _vaultToken?.cancel();
    });
    return const HashVerifierState();
  }

  void setMode(HashVerifierMode mode) => state = state._copy(mode: mode);

  void setVaultAction(HashVerifierVaultAction? action) =>
      state = state._copy(vaultAction: action, clearVaultAction: action == null);

  void setVaultTarget(MountedContainer target) =>
      state = state._copy(vaultTarget: target);

  void setAlgorithms(Set<HashAlgorithm> algos) =>
      state = state._copy(algorithms: algos);

  void setExportAlgorithm(HashAlgorithm algo) =>
      state = state._copy(exportAlgorithm: algo);

  void setVaultAlgorithms(Set<HashAlgorithm> algos) =>
      state = state._copy(vaultAlgorithms: algos);

  void setVaultExportAlgorithm(HashAlgorithm algo) =>
      state = state._copy(vaultExportAlgorithm: algo);

  void addComputeSources(List<CryptoSourceItem> items) {
    final existingIds = state.computeSources.map((s) => s.id).toSet();
    final newSources = List<CryptoSourceItem>.from(state.computeSources);
    for (final item in items) {
      if (existingIds.add(item.id)) newSources.add(item);
    }
    state = state._copy(computeSources: newSources, clearComputeError: true);
  }

  void removeComputeSource(CryptoSourceItem item) {
    final newSources = List<CryptoSourceItem>.from(state.computeSources)..remove(item);
    final newResults = Map<String, HashComputeResult>.from(state.computeResults)..remove(item.id);
    state = state._copy(computeSources: newSources, computeResults: newResults);
  }

  void clearComputeSources() {
    state = state._copy(computeSources: const [], computeResults: const {});
  }

  Future<void> runCompute(AppLocalizations l10n) async {
    if (state.computeSources.isEmpty) {
      state = state._copy(computeError: l10n.noFileSelectedLabel);
      return;
    }
    if (state.algorithms.isEmpty) {
      state = state._copy(computeError: l10n.hashVerifierNoAlgorithmSelected);
      return;
    }

    final token = HashCancellationToken();
    _computeToken = token;
    state = state._copy(
      computeBusy: true,
      clearComputeError: true,
      computeIndex: 0,
      resetComputeProgress: true,
      computeDone: 0,
      computeTotal: null,
      computeResults: const {},
    );

    var succeeded = 0;
    for (var i = 0; i < state.computeSources.length; i++) {
      if (token.isCancelled) break;
      final source = state.computeSources[i];
      if (!ref.mounted) return;
      state = state._copy(
        computeIndex: i + 1,
        resetComputeProgress: true,
        computeDone: 0,
        computeTotal: null,
      );

      try {
        final digests = await _service.computeHashes(
          source: source,
          algorithms: state.algorithms,
          cancelToken: token,
          onProgress: (done, total) {
            if (!ref.mounted) return;
            state = state._copy(computeDone: done, computeTotal: total);
          },
        );
        succeeded++;
        if (!ref.mounted) return;
        final newResults = Map<String, HashComputeResult>.from(state.computeResults);
        newResults[source.id] = HashComputeResult(source: source, digests: digests);
        state = state._copy(computeResults: newResults);
      } on HashOperationCancelledException {
        break;
      } catch (e) {
        if (!ref.mounted) return;
        final newResults = Map<String, HashComputeResult>.from(state.computeResults);
        newResults[source.id] = HashComputeResult(source: source, digests: const {}, error: e.toString());
        state = state._copy(computeResults: newResults);
      }
    }

    if (!ref.mounted) return;
    final cancelled = token.isCancelled;
    _computeToken = null;

    String? error;
    if (cancelled) {
      error = l10n.hashVerifierCancelledMessage;
    } else if (succeeded < state.computeSources.length) {
      error = l10n.hashVerifierComputeErrorsMessage(state.computeSources.length - succeeded);
    }

    var exportAlgo = state.exportAlgorithm;
    if (state.algorithms.isNotEmpty && !state.algorithms.contains(exportAlgo)) {
      exportAlgo = state.algorithms.first;
    }

    state = state._copy(
      computeBusy: false,
      computeError: error,
      clearComputeError: error == null,
      exportAlgorithm: exportAlgo,
    );
  }

  void cancelCompute() => _computeToken?.cancel();

  static String _basenameOf(String path) {
    final idx = path.lastIndexOf('/');
    return idx < 0 ? path : path.substring(idx + 1);
  }

  void _rematch() {
    final byBasename = <String, CryptoSourceItem>{};
    final byRelPath = <String, CryptoSourceItem>{};
    for (final item in state.verifyCandidates) {
      byBasename[item.displayName.toLowerCase()] = item;
      final manifest = state.manifestSource;
      if (manifest != null) {
        final rel = _service.relativeToManifestFolder(item, manifest);
        if (rel != null) byRelPath[rel.toLowerCase()] = item;
      }
    }

    final rows = <VerifyRow>[];
    for (final entry in state.manifestEntries) {
      final matched =
          byRelPath[entry.fileName.toLowerCase()] ?? byBasename[_basenameOf(entry.fileName).toLowerCase()];
      rows.add(VerifyRow(
        entry: entry,
        matchedSource: matched,
        status: matched == null ? VerifyStatus.missing : VerifyStatus.pending,
      ));
    }
    state = state._copy(rows: rows);
  }

  Future<void> loadManifest(CryptoSourceItem source, AppLocalizations l10n) async {
    state = state._copy(loadingManifest: true, clearVerifyError: true);
    try {
      final text = await _service.readManifestText(source);
      final entries = _service.parseManifest(text);
      if (!ref.mounted) return;
      state = state._copy(
        manifestSource: source,
        manifestEntries: entries,
        verifyCandidates: const [],
        rows: const [],
        loadingManifest: false,
        verifyError: entries.isEmpty ? l10n.hashVerifierManifestParseEmptyMessage : null,
        clearVerifyError: entries.isNotEmpty,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state._copy(
        loadingManifest: false,
        verifyError: l10n.hashVerifierLoadManifestFailedMessage(e),
      );
    }
  }

  Future<int?> autoAddFromManifestFolder() async {
    final manifest = state.manifestSource;
    if (manifest == null || !manifest.isFromVault) return null;
    state = state._copy(loadingManifest: true);
    try {
      final siblings = await _service.collectVaultManifestSiblings(manifest);
      if (!ref.mounted) return null;
      var added = 0;
      final existingIds = state.verifyCandidates.map((c) => c.id).toSet();
      final newCandidates = List<CryptoSourceItem>.from(state.verifyCandidates);
      for (final item in siblings) {
        if (existingIds.add(item.id)) {
          newCandidates.add(item);
          added++;
        }
      }
      state = state._copy(verifyCandidates: newCandidates, loadingManifest: false);
      _rematch();
      return added;
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(loadingManifest: false, verifyError: e.toString());
      }
      return null;
    }
  }

  void addVerifyCandidates(List<CryptoSourceItem> items) {
    final existingIds = state.verifyCandidates.map((c) => c.id).toSet();
    final newCandidates = List<CryptoSourceItem>.from(state.verifyCandidates);
    for (final item in items) {
      if (existingIds.add(item.id)) newCandidates.add(item);
    }
    state = state._copy(verifyCandidates: newCandidates);
    _rematch();
  }

  Future<void> verifyEntireVault() async {
    final manifest = state.manifestSource;
    if (manifest == null || !manifest.isFromVault) return;
    state = state._copy(loadingManifest: true, clearVerifyError: true);
    try {
      final files = await _service.collectEntireVaultFiles(manifest);
      if (!ref.mounted) return;
      final existingIds = state.verifyCandidates.map((c) => c.id).toSet();
      final newCandidates = List<CryptoSourceItem>.from(state.verifyCandidates);
      for (final item in files) {
        if (existingIds.add(item.id)) newCandidates.add(item);
      }
      state = state._copy(verifyCandidates: newCandidates, loadingManifest: false);
      _rematch();
      if (!ref.mounted) return;
      await runVerifyAll();
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(loadingManifest: false, verifyError: e.toString());
      }
    }
  }

  Future<void> runVerifyAll() async {
    final pending = state.rows.where((r) => r.matchedSource != null).toList();
    if (pending.isEmpty) return;

    final token = HashCancellationToken();
    _verifyToken = token;
    state = state._copy(
      verifyBusy: true,
      clearVerifyError: true,
      verifyIndex: 0,
      resetVerifyProgress: true,
      verifyDone: 0,
      verifyTotal: null,
    );

    for (var i = 0; i < pending.length; i++) {
      if (token.isCancelled) break;
      final row = pending[i];
      final rowIndex = state.rows.indexOf(row);
      if (!ref.mounted) return;

      final updatedRows = List<VerifyRow>.from(state.rows);
      if (rowIndex >= 0) {
        updatedRows[rowIndex] = row.copyWith(status: VerifyStatus.computing);
      }

      state = state._copy(
        verifyIndex: i + 1,
        resetVerifyProgress: true,
        verifyDone: 0,
        verifyTotal: null,
        rows: updatedRows,
      );

      try {
        final digests = await _service.computeHashes(
          source: row.matchedSource!,
          algorithms: {row.entry.algorithm},
          cancelToken: token,
          onProgress: (done, total) {
            if (!ref.mounted) return;
            state = state._copy(verifyDone: done, verifyTotal: total);
          },
        );
        final computed = digests[row.entry.algorithm];
        final isMatch = computed != null &&
            computed.toLowerCase() == row.entry.expectedHex.toLowerCase();
        if (!ref.mounted) return;

        final finishRows = List<VerifyRow>.from(state.rows);
        if (rowIndex >= 0) {
          finishRows[rowIndex] = row.copyWith(
            status: isMatch ? VerifyStatus.match : VerifyStatus.mismatch,
            computedHex: computed,
          );
        }
        state = state._copy(rows: finishRows);
      } on HashOperationCancelledException {
        if (!ref.mounted) return;
        final cancelRows = List<VerifyRow>.from(state.rows);
        if (rowIndex >= 0) {
          cancelRows[rowIndex] = row.copyWith(status: VerifyStatus.pending);
        }
        state = state._copy(rows: cancelRows);
        break;
      } catch (e) {
        if (!ref.mounted) return;
        final errRows = List<VerifyRow>.from(state.rows);
        if (rowIndex >= 0) {
          errRows[rowIndex] = row.copyWith(status: VerifyStatus.error, errorMessage: e.toString());
        }
        state = state._copy(rows: errRows);
      }
    }

    if (!ref.mounted) return;
    _verifyToken = null;
    state = state._copy(verifyBusy: false);
  }

  void cancelVerify() => _verifyToken?.cancel();

  Future<void> startVaultScan() async {
    final vault = state.vaultTarget;
    if (vault == null) return;
    final token = HashCancellationToken();
    final session = VaultScanSession();
    _vaultToken = token;
    _vaultSession = session;

    state = state._copy(
      clearVaultError: true,
      vaultProgress: const HashOperationProgress(phase: HashOperationPhase.scanning),
    );

    await for (final progress in _opController.scanVault(
      VaultHashOperation(vault),
      cancelToken: token,
      session: session,
    )) {
      if (!ref.mounted) return;
      state = state._copy(vaultProgress: progress);
    }
    if (ref.mounted && state.vaultProgress.phase == HashOperationPhase.failed) {
      _vaultToken = null;
    }
  }

  Future<void> startVaultHashing(AppLocalizations l10n) async {
    final session = _vaultSession;
    final token = _vaultToken;
    if (session == null || token == null) return;
    if (state.vaultAlgorithms.isEmpty) {
      state = state._copy(vaultError: l10n.hashVerifierNoAlgorithmSelected);
      return;
    }
    state = state._copy(clearVaultError: true);

    await for (final progress in _opController.hashVaultFiles(
      session,
      algorithms: state.vaultAlgorithms,
      cancelToken: token,
    )) {
      if (!ref.mounted) return;
      var exportAlgo = state.vaultExportAlgorithm;
      if (state.vaultAlgorithms.isNotEmpty && !state.vaultAlgorithms.contains(exportAlgo)) {
        exportAlgo = state.vaultAlgorithms.first;
      }
      state = state._copy(vaultProgress: progress, vaultExportAlgorithm: exportAlgo);
    }
  }

  void cancelVaultOperation() => _vaultToken?.cancel();

  void resetVaultOperation() {
    _vaultToken = null;
    _vaultSession = null;
    state = state._copy(
      clearVaultError: true,
      vaultProgress: const HashOperationProgress(),
    );
  }
}
