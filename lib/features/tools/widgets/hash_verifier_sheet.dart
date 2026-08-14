import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/hash_operation.dart';
import 'package:vaultexplorer/features/tools/models/hash_verifier_models.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/hash_operation_controller.dart';
import 'package:vaultexplorer/features/tools/services/hash_verifier_service.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_file_picker_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_folder_picker_sheet.dart';

enum _HashMode { compute, verify, vault }

/// Which whole-vault workflow the Vault tab is running: hash every file
/// ("Compute Entire Vault", via [HashOperationController]) or check every
/// file against an already-loaded manifest ("Verify Entire Vault", which
/// reuses the Verify tab's manifest/candidate/row machinery with vault-wide
/// scanning standing in for manual candidate picking). `null` means neither
/// has been chosen yet -- the tab shows the two-option chooser.
enum _VaultAction { compute, verify }

/// Tools tab -> File Checksum & Hash Verifier. Two tabs sharing one screen:
/// Compute (hash one or more files, optionally export a manifest) and
/// Verify (load a `.sha256sum`/`.md5`/BSD-style manifest, match its
/// entries against candidate files, and compare digests). All hashing
/// goes through [HashVerifierService.computeHashes], which streams
/// vault-resident files entirely in Dart and hands external/on-device
/// files to the native side -- see that file's doc comment for why.
class HashVerifierSheet extends StatefulWidget {
  final ValueListenable<List<MountedContainer>>? mountedContainers;

  const HashVerifierSheet({super.key, this.mountedContainers});

  @override
  State<HashVerifierSheet> createState() => _HashVerifierSheetState();
}

class _HashVerifierSheetState extends State<HashVerifierSheet> {
  final _service = HashVerifierService();
  _HashMode _mode = _HashMode.compute;

  // ---- Compute tab state ----
  final List<CryptoSourceItem> _computeSources = [];
  Set<HashAlgorithm> _algorithms = {HashAlgorithm.sha256};
  final Map<String, HashComputeResult> _computeResults = {};
  HashAlgorithm _exportAlgorithm = HashAlgorithm.sha256;
  bool _computeBusy = false;
  int _computeIndex = 0;
  int? _computeDone;
  int? _computeTotal;
  HashCancellationToken? _computeToken;
  String? _computeError;

  // ---- Verify tab state (also reused by Vault > Verify Entire Vault,
  // which populates _verifyCandidates by scanning a whole vault instead of
  // manual/folder picking, then runs the same _rematch/_runVerifyAll) ----
  CryptoSourceItem? _manifestSource;
  List<ManifestEntry> _manifestEntries = [];
  final List<CryptoSourceItem> _verifyCandidates = [];
  List<VerifyRow> _rows = [];
  bool _loadingManifest = false;
  bool _verifyBusy = false;
  int _verifyIndex = 0;
  int? _verifyDone;
  int? _verifyTotal;
  HashCancellationToken? _verifyToken;
  String? _verifyError;

  // ---- Vault tab state ----
  _VaultAction? _vaultAction;

  // ---- Vault > Compute Entire Vault state ----
  final _opController = HashOperationController();
  MountedContainer? _vaultTarget;
  Set<HashAlgorithm> _vaultAlgorithms = {HashAlgorithm.sha256};
  HashAlgorithm _vaultExportAlgorithm = HashAlgorithm.sha256;
  HashOperationProgress _vaultProgress = const HashOperationProgress();
  VaultScanSession? _vaultSession;
  HashCancellationToken? _vaultToken;
  String? _vaultError;

  bool get _vaultBusy =>
      _vaultProgress.phase == HashOperationPhase.scanning ||
      _vaultProgress.phase == HashOperationPhase.hashing;

  bool get _busy => _computeBusy || _verifyBusy || _loadingManifest || _vaultBusy;

  @override
  void dispose() {
    _computeToken?.cancel();
    _verifyToken?.cancel();
    _vaultToken?.cancel();
    super.dispose();
  }

  // ======================= shared source picking =======================

  Future<List<CryptoSourceItem>> _pickExternalSources() async {
    final picked = await vaultExplorerApi.pickCryptoFiles();
    return picked
        .map((f) => CryptoSourceItem.external(displayName: f.displayName, externalUri: f.uri))
        .toList();
  }

  Future<List<CryptoSourceItem>> _pickVaultSources(List<MountedContainer> vaults) async {
    final result = await Navigator.push<List<CryptoSourceItem>>(
      context,
      MaterialPageRoute(builder: (_) => VaultFilePickerSheet(mountedContainers: vaults)),
    );
    return result ?? [];
  }

  Future<List<CryptoSourceItem>> _pickSources() async {
    final mountedVaults = widget.mountedContainers?.value ?? [];
    if (mountedVaults.isEmpty) return _pickExternalSources();

    final useDevice = await showDeviceOrVaultChooserSheet(
      context: context,
      sheetTitle: context.l10n.hashVerifierSelectSourceTitle,
      deviceTitle: context.l10n.singleFileCryptoFromDeviceTitle,
      deviceSubtitle: context.l10n.singleFileCryptoFromDeviceSubtitle,
      vaultTitle: context.l10n.singleFileCryptoFromVaultTitle,
      vaultSubtitle: context.l10n.singleFileCryptoFromVaultSubtitle,
    );
    if (useDevice == true) return _pickExternalSources();
    if (useDevice == false) return _pickVaultSources(mountedVaults);
    return [];
  }

  Future<void> _copyDigest(String hex) async {
    await Clipboard.setData(ClipboardData(text: hex));
    if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.hashVerifierCopiedMessage,
        tone: AppBannerTone.success,
      );
    }
  }

  // ============================ Compute tab ============================

  Future<void> _addComputeSources() async {
    final picked = await _pickSources();
    if (picked.isEmpty || !mounted) return;
    setState(() {
      final existingIds = _computeSources.map((s) => s.id).toSet();
      for (final item in picked) {
        if (existingIds.add(item.id)) _computeSources.add(item);
      }
      _computeError = null;
    });
  }

  void _removeComputeSource(CryptoSourceItem item) {
    setState(() {
      _computeSources.remove(item);
      _computeResults.remove(item.id);
    });
  }

  void _clearComputeSources() {
    setState(() {
      _computeSources.clear();
      _computeResults.clear();
    });
  }

  Future<void> _runCompute() async {
    if (_computeSources.isEmpty) {
      setState(() => _computeError = context.l10n.noFileSelectedLabel);
      return;
    }
    if (_algorithms.isEmpty) {
      setState(() => _computeError = context.l10n.hashVerifierNoAlgorithmSelected);
      return;
    }

    final token = HashCancellationToken();
    setState(() {
      _computeBusy = true;
      _computeError = null;
      _computeIndex = 0;
      _computeDone = 0;
      _computeTotal = null;
      _computeToken = token;
      _computeResults.clear();
    });

    var succeeded = 0;
    for (var i = 0; i < _computeSources.length; i++) {
      if (token.isCancelled) break;
      final source = _computeSources[i];
      if (!mounted) return;
      setState(() {
        _computeIndex = i + 1;
        _computeDone = 0;
        _computeTotal = null;
      });
      try {
        final digests = await _service.computeHashes(
          source: source,
          algorithms: _algorithms,
          cancelToken: token,
          onProgress: (done, total) {
            if (!mounted) return;
            setState(() {
              _computeDone = done;
              _computeTotal = total;
            });
          },
        );
        succeeded++;
        if (!mounted) return;
        setState(() {
          _computeResults[source.id] = HashComputeResult(source: source, digests: digests);
        });
      } on HashOperationCancelledException {
        break;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _computeResults[source.id] =
              HashComputeResult(source: source, digests: const {}, error: e.toString());
        });
      }
    }

    if (!mounted) return;
    final cancelled = token.isCancelled;
    setState(() {
      _computeBusy = false;
      _computeToken = null;
      if (cancelled) {
        _computeError = context.l10n.hashVerifierCancelledMessage;
      } else if (succeeded < _computeSources.length) {
        _computeError =
            context.l10n.hashVerifierComputeErrorsMessage(_computeSources.length - succeeded);
      }
      if (_algorithms.isNotEmpty && !_algorithms.contains(_exportAlgorithm)) {
        _exportAlgorithm = _algorithms.first;
      }
    });
  }

  void _cancelCompute() => _computeToken?.cancel();

  Future<void> _exportManifest() => _exportManifestResults(
        _computeResults.values.where((r) => r.digests.containsKey(_exportAlgorithm)).toList(),
        _exportAlgorithm,
      );

  /// Builds a manifest from [results] for [algorithm] and lets the user save
  /// it either to an on-device folder or a vault folder. Shared by the
  /// Compute tab ([_exportManifest]) and the Vault tab's completed-check
  /// summary, so "export a manifest from a batch of [HashComputeResult]s"
  /// has one implementation regardless of whether the batch came from a
  /// manual selection or a vault scan.
  Future<void> _exportManifestResults(List<HashComputeResult> results, HashAlgorithm algorithm) async {
    if (results.isEmpty) return;
    final manifestText = _service.buildManifestText(results, algorithm);
    final suggestedName = results.length == 1
        ? '${results.first.source.displayName}.${algorithm.manifestExtension}'
        : 'checksums.${algorithm.manifestExtension}';

    final mountedVaults = widget.mountedContainers?.value ?? [];
    final useDevice = await showDeviceOrVaultChooserSheet(
      context: context,
      sheetTitle: context.l10n.singleFileCryptoSelectDestinationTitle,
      deviceTitle: context.l10n.singleFileCryptoFromDeviceTitle,
      deviceSubtitle: context.l10n.singleFileCryptoFromDeviceSubtitle,
      vaultTitle: context.l10n.singleFileCryptoFromVaultTitle,
      vaultSubtitle: context.l10n.singleFileCryptoFromVaultSubtitle,
      showVaultOption: mountedVaults.isNotEmpty,
    );
    if (useDevice == null || !mounted) return;

    if (useDevice) {
      final folder = await vaultExplorerApi.pickExtractFolder();
      if (folder == null || folder.path == null || !mounted) return;
      try {
        final destFile = File('${folder.path}/$suggestedName');
        await destFile.writeAsBytes(utf8.encode(manifestText), flush: true);
        if (mounted) {
          showAppSnackBar(
            context,
            message: context.l10n
                .hashVerifierExportSuccessMessage('${folder.displayName}/$suggestedName'),
            tone: AppBannerTone.success,
          );
        }
      } catch (e) {
        if (mounted) {
          showAppSnackBar(
            context,
            message: context.l10n.hashVerifierExportFailedMessage(e),
            tone: AppBannerTone.error,
          );
        }
      }
    } else {
      final dest = await Navigator.push<CryptoDestination>(
        context,
        MaterialPageRoute(builder: (_) => VaultFolderPickerSheet(mountedContainers: mountedVaults)),
      );
      if (dest == null || !mounted) return;
      try {
        final path = '/${dest.relativePath ?? ''}/$suggestedName'.replaceAll('//', '/');
        final ok = await vaultExplorerApi.writeFileChunk(
          dest.container!,
          path,
          0,
          Uint8List.fromList(utf8.encode(manifestText)),
        );
        if (!mounted) return;
        if (ok) {
          showAppSnackBar(
            context,
            message: context.l10n
                .hashVerifierExportSuccessMessage('${dest.container!.displayName}$path'),
            tone: AppBannerTone.success,
          );
        } else {
          showAppSnackBar(
            context,
            message: context.l10n.hashVerifierExportFailedMessage(''),
            tone: AppBannerTone.error,
          );
        }
      } catch (e) {
        if (mounted) {
          showAppSnackBar(
            context,
            message: context.l10n.hashVerifierExportFailedMessage(e),
            tone: AppBannerTone.error,
          );
        }
      }
    }
  }

  // ============================= Verify tab =============================

  String _basenameOf(String path) {
    final idx = path.lastIndexOf('/');
    return idx < 0 ? path : path.substring(idx + 1);
  }

  void _rematch() {
    final byBasename = <String, CryptoSourceItem>{};
    final byRelPath = <String, CryptoSourceItem>{};
    for (final item in _verifyCandidates) {
      byBasename[item.displayName.toLowerCase()] = item;
      final manifest = _manifestSource;
      if (manifest != null) {
        final rel = _service.relativeToManifestFolder(item, manifest);
        if (rel != null) byRelPath[rel.toLowerCase()] = item;
      }
    }
    final rows = <VerifyRow>[];
    for (final entry in _manifestEntries) {
      final matched =
          byRelPath[entry.fileName.toLowerCase()] ?? byBasename[_basenameOf(entry.fileName).toLowerCase()];
      rows.add(VerifyRow(
        entry: entry,
        matchedSource: matched,
        status: matched == null ? VerifyStatus.missing : VerifyStatus.pending,
      ));
    }
    setState(() => _rows = rows);
  }

  List<CryptoSourceItem> get _extraCandidates {
    final matchedIds = _rows.map((r) => r.matchedSource?.id).whereType<String>().toSet();
    return _verifyCandidates.where((c) => !matchedIds.contains(c.id)).toList();
  }

  Future<void> _pickManifest() async {
    final picked = await _pickSources();
    if (picked.isEmpty || !mounted) return;
    final source = picked.first;
    setState(() {
      _loadingManifest = true;
      _verifyError = null;
    });
    try {
      final text = await _service.readManifestText(source);
      final entries = _service.parseManifest(text);
      if (!mounted) return;
      setState(() {
        _manifestSource = source;
        _manifestEntries = entries;
        _verifyCandidates.clear();
        _rows = [];
        _loadingManifest = false;
        _verifyError = entries.isEmpty ? context.l10n.hashVerifierManifestParseEmptyMessage : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingManifest = false;
        _verifyError = context.l10n.hashVerifierLoadManifestFailedMessage(e);
      });
    }
  }

  Future<void> _autoAddFromManifestFolder() async {
    final manifest = _manifestSource;
    if (manifest == null || !manifest.isFromVault) return;
    setState(() => _loadingManifest = true);
    try {
      final siblings = await _service.collectVaultManifestSiblings(manifest);
      if (!mounted) return;
      var added = 0;
      setState(() {
        final existingIds = _verifyCandidates.map((c) => c.id).toSet();
        for (final item in siblings) {
          if (existingIds.add(item.id)) {
            _verifyCandidates.add(item);
            added++;
          }
        }
        _loadingManifest = false;
      });
      _rematch();
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.hashVerifierAutoAddedCount(added),
          tone: AppBannerTone.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingManifest = false;
        _verifyError = e.toString();
      });
    }
  }

  Future<void> _addVerifyCandidates() async {
    final picked = await _pickSources();
    if (picked.isEmpty || !mounted) return;
    setState(() {
      final existingIds = _verifyCandidates.map((c) => c.id).toSet();
      for (final item in picked) {
        if (existingIds.add(item.id)) _verifyCandidates.add(item);
      }
    });
    _rematch();
  }

  /// Vault tab's "Verify Entire Vault": scans the whole vault the loaded
  /// manifest lives in (not just its folder, unlike
  /// [_autoAddFromManifestFolder]), adds every discovered file as a verify
  /// candidate, then runs the exact same matching and verification as the
  /// manual Verify tab.
  Future<void> _verifyEntireVault() async {
    final manifest = _manifestSource;
    if (manifest == null || !manifest.isFromVault) return;

    setState(() {
      _loadingManifest = true;
      _verifyError = null;
    });
    try {
      final files = await _service.collectEntireVaultFiles(manifest);
      if (!mounted) return;
      setState(() {
        final existingIds = _verifyCandidates.map((c) => c.id).toSet();
        for (final item in files) {
          if (existingIds.add(item.id)) _verifyCandidates.add(item);
        }
        _loadingManifest = false;
      });
      _rematch();
      if (!mounted) return;
      await _runVerifyAll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingManifest = false;
        _verifyError = e.toString();
      });
    }
  }

  Future<void> _runVerifyAll() async {
    final pending = _rows.where((r) => r.matchedSource != null).toList();
    if (pending.isEmpty) return;

    final token = HashCancellationToken();
    setState(() {
      _verifyBusy = true;
      _verifyError = null;
      _verifyIndex = 0;
      _verifyDone = 0;
      _verifyTotal = null;
      _verifyToken = token;
    });

    for (var i = 0; i < pending.length; i++) {
      if (token.isCancelled) break;
      final row = pending[i];
      final rowIndex = _rows.indexOf(row);
      if (!mounted) return;
      setState(() {
        _verifyIndex = i + 1;
        _verifyDone = 0;
        _verifyTotal = null;
        if (rowIndex >= 0) _rows[rowIndex] = row.copyWith(status: VerifyStatus.computing);
      });
      try {
        final digests = await _service.computeHashes(
          source: row.matchedSource!,
          algorithms: {row.entry.algorithm},
          cancelToken: token,
          onProgress: (done, total) {
            if (!mounted) return;
            setState(() {
              _verifyDone = done;
              _verifyTotal = total;
            });
          },
        );
        final computed = digests[row.entry.algorithm];
        final isMatch = computed != null &&
            computed.toLowerCase() == row.entry.expectedHex.toLowerCase();
        if (!mounted) return;
        setState(() {
          if (rowIndex >= 0) {
            _rows[rowIndex] = row.copyWith(
              status: isMatch ? VerifyStatus.match : VerifyStatus.mismatch,
              computedHex: computed,
            );
          }
        });
      } on HashOperationCancelledException {
        if (!mounted) return;
        setState(() {
          if (rowIndex >= 0) _rows[rowIndex] = row.copyWith(status: VerifyStatus.pending);
        });
        break;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          if (rowIndex >= 0) {
            _rows[rowIndex] =
                row.copyWith(status: VerifyStatus.error, errorMessage: e.toString());
          }
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _verifyBusy = false;
      _verifyToken = null;
    });
  }

  void _cancelVerify() => _verifyToken?.cancel();

  // ============================== Vault tab ==============================

  Future<void> _startVaultScan() async {
    final vault = _vaultTarget;
    if (vault == null) return;

    final token = HashCancellationToken();
    final session = VaultScanSession();
    setState(() {
      _vaultToken = token;
      _vaultSession = session;
      _vaultError = null;
      _vaultProgress = const HashOperationProgress(phase: HashOperationPhase.scanning);
    });

    await for (final progress in _opController.scanVault(
      VaultHashOperation(vault),
      cancelToken: token,
      session: session,
    )) {
      if (!mounted) return;
      setState(() => _vaultProgress = progress);
    }

    if (mounted && _vaultProgress.phase == HashOperationPhase.failed) {
      setState(() => _vaultToken = null);
    }
  }

  Future<void> _startVaultHashing() async {
    final session = _vaultSession;
    final token = _vaultToken;
    if (session == null || token == null) return;
    if (_vaultAlgorithms.isEmpty) {
      setState(() => _vaultError = context.l10n.hashVerifierNoAlgorithmSelected);
      return;
    }

    setState(() => _vaultError = null);

    await for (final progress in _opController.hashVaultFiles(
      session,
      algorithms: _vaultAlgorithms,
      cancelToken: token,
    )) {
      if (!mounted) return;
      setState(() {
        _vaultProgress = progress;
        if (_vaultAlgorithms.isNotEmpty && !_vaultAlgorithms.contains(_vaultExportAlgorithm)) {
          _vaultExportAlgorithm = _vaultAlgorithms.first;
        }
      });
    }
  }

  void _cancelVaultOperation() => _vaultToken?.cancel();

  void _resetVaultOperation() {
    setState(() {
      _vaultToken = null;
      _vaultSession = null;
      _vaultError = null;
      _vaultProgress = const HashOperationProgress();
    });
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  // ================================ build ================================

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.toolHashVerifierTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_HashMode>(
              segments: [
                ButtonSegment(
                  value: _HashMode.compute,
                  label: Text(context.l10n.hashVerifierModeCompute),
                  icon: const Icon(Icons.tag_rounded, size: 18),
                ),
                ButtonSegment(
                  value: _HashMode.verify,
                  label: Text(context.l10n.hashVerifierModeVerify),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                ),
                ButtonSegment(
                  value: _HashMode.vault,
                  label: Text(context.l10n.hashVerifierModeVault),
                  icon: const Icon(Icons.folder_zip_outlined, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged:
                  _busy ? null : (sel) => setState(() => _mode = sel.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_mode == _HashMode.compute)
              ..._buildComputeTab(cs, textTheme)
            else if (_mode == _HashMode.verify)
              ..._buildVerifyTab(cs, textTheme)
            else
              ..._buildVaultTab(cs, textTheme),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  // ------------------------- Compute tab widgets -------------------------

  List<Widget> _buildComputeTab(ColorScheme cs, TextTheme textTheme) {
    return [
      Text(
        context.l10n.hashVerifierAlgorithmsLabel,
        style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final algo in HashAlgorithm.values)
            FilterChip(
              label: Text(algo.label),
              selected: _algorithms.contains(algo),
              showCheckmark: false,
              onSelected: _computeBusy
                  ? null
                  : (selected) => setState(() {
                        if (selected) {
                          _algorithms.add(algo);
                        } else {
                          _algorithms.remove(algo);
                        }
                      }),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description_outlined, size: AppIconSize.small, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.hashVerifierFilesLabel,
                        style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      Text(
                        context.l10n.hashVerifierFilesQueuedCount(_computeSources.length),
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _computeBusy ? null : _addComputeSources,
                  child: Text(context.l10n.singleFileCryptoAddFilesButton),
                ),
              ],
            ),
            if (_computeSources.isNotEmpty) ...[
              const SizedBox(height: 4),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final source in _computeSources)
                        _SourceRow(
                          source: source,
                          result: _computeResults[source.id],
                          algorithms: _algorithms,
                          enabled: !_computeBusy,
                          onRemove: () => _removeComputeSource(source),
                          onCopy: _copyDigest,
                        ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _computeBusy ? null : _clearComputeSources,
                  child: Text(context.l10n.singleFileCryptoClearFilesButton),
                ),
              ),
            ],
          ],
        ),
      ),
      if (_computeBusy && _computeSources.length > 1) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.l10n.hashVerifierBatchProgressLabel(_computeIndex, _computeSources.length),
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
      if (_computeBusy) ...[
        const SizedBox(height: AppSpacing.sm),
        LinearProgressIndicator(
          value: (_computeTotal != null && _computeTotal! > 0)
              ? (_computeDone ?? 0) / _computeTotal!
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          _computeTotal != null
              ? context.l10n.splitJoinOperationProgress(
                  formatBytes(_computeDone ?? 0),
                  formatBytes(_computeTotal!),
                )
              : formatBytes(_computeDone ?? 0),
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
      if (_computeError != null) ...[
        const SizedBox(height: AppSpacing.md),
        InlineErrorBanner(_computeError!),
      ],
      const SizedBox(height: AppSpacing.lg),
      if (_computeBusy)
        OutlinedButton(
          onPressed: _cancelCompute,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: Text(context.l10n.hashVerifierCancelButton),
        )
      else
        FilledButton(
          onPressed: _computeSources.isEmpty ? null : _runCompute,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: Text(
            context.l10n.hashVerifierComputeButton(_computeSources.length),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      if (_computeResults.isNotEmpty && !_computeBusy) ...[
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.hashVerifierExportAlgorithmLabel,
                style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            DropdownButton<HashAlgorithm>(
              value: _algorithms.contains(_exportAlgorithm)
                  ? _exportAlgorithm
                  : (_algorithms.isEmpty ? null : _algorithms.first),
              items: [
                for (final algo in _algorithms)
                  DropdownMenuItem(value: algo, child: Text(algo.label)),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _exportAlgorithm = val);
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _computeResults.values.any((r) => r.digests.containsKey(_exportAlgorithm))
              ? _exportManifest
              : null,
          icon: const Icon(Icons.save_alt_rounded, size: 18),
          label: Text(context.l10n.hashVerifierExportManifestButton),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    ];
  }

  // ------------------------- Verify tab widgets -------------------------

  List<Widget> _buildVerifyTab(ColorScheme cs, TextTheme textTheme) {
    final matchCount = _rows.where((r) => r.status == VerifyStatus.match).length;
    final mismatchCount = _rows
        .where((r) => r.status == VerifyStatus.mismatch || r.status == VerifyStatus.error)
        .length;
    final missingCount = _rows.where((r) => r.status == VerifyStatus.missing).length;
    final extras = _extraCandidates;

    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(Icons.checklist_rtl_rounded, size: AppIconSize.small, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.hashVerifierManifestLabel,
                    style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  Text(
                    _manifestSource?.displayName ?? context.l10n.noFileSelectedLabel,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_manifestSource != null)
                    Text(
                      context.l10n.hashVerifierManifestEntryCount(_manifestEntries.length),
                      style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy ? null : _pickManifest,
              child: Text(
                _manifestSource == null
                    ? context.l10n.hashVerifierLoadManifestButton
                    : context.l10n.hashVerifierChangeManifestButton,
              ),
            ),
          ],
        ),
      ),
      if (_manifestSource == null) ...[
        const SizedBox(height: AppSpacing.md),
        InlineBanner(context.l10n.hashVerifierNoManifestLoadedMessage),
      ],
      if (_manifestSource != null) ...[
        const SizedBox(height: AppSpacing.sm),
        if (_manifestSource!.isFromVault)
          OutlinedButton.icon(
            onPressed: _busy ? null : _autoAddFromManifestFolder,
            icon: const Icon(Icons.folder_copy_outlined, size: 18),
            label: Text(context.l10n.hashVerifierAutoAddFolderButton),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _busy ? null : _addVerifyCandidates,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(context.l10n.hashVerifierAddFilesToVerifyButton),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        ),
      ],
      if (_verifyError != null) ...[
        const SizedBox(height: AppSpacing.md),
        InlineErrorBanner(_verifyError!),
      ],
      if (_rows.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        InlineBanner(
          context.l10n.hashVerifierSummaryMessage(matchCount, mismatchCount, missingCount),
          tone: mismatchCount > 0
              ? AppBannerTone.error
              : (missingCount > 0 ? AppBannerTone.warning : AppBannerTone.success),
        ),
        const SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final row in _rows) _VerifyRowTile(row: row),
              ],
            ),
          ),
        ),
      ],
      if (extras.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Text(
          context.l10n.hashVerifierExtraFilesLabel(extras.length),
          style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
      if (_verifyBusy && _rows.where((r) => r.matchedSource != null).length > 1) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.l10n.hashVerifierVerifyProgressLabel(
            _verifyIndex,
            _rows.where((r) => r.matchedSource != null).length,
          ),
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
      if (_verifyBusy) ...[
        const SizedBox(height: AppSpacing.sm),
        LinearProgressIndicator(
          value: (_verifyTotal != null && _verifyTotal! > 0)
              ? (_verifyDone ?? 0) / _verifyTotal!
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          _verifyTotal != null
              ? context.l10n.splitJoinOperationProgress(
                  formatBytes(_verifyDone ?? 0),
                  formatBytes(_verifyTotal!),
                )
              : formatBytes(_verifyDone ?? 0),
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      if (_verifyBusy)
        OutlinedButton(
          onPressed: _cancelVerify,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: Text(context.l10n.hashVerifierCancelButton),
        )
      else
        FilledButton(
          onPressed: _rows.any((r) => r.matchedSource != null) && !_busy ? _runVerifyAll : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: Text(
            context.l10n.hashVerifierVerifyAllButton,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
    ];
  }

  // -------------------------- Vault tab widgets --------------------------

  /// Top of the Vault tab: the two-option chooser when no action has been
  /// picked yet, otherwise a small header (with a "Change" affordance) plus
  /// whichever action's own widgets.
  List<Widget> _buildVaultTab(ColorScheme cs, TextTheme textTheme) {
    final action = _vaultAction;
    if (action == null) return _buildVaultActionChooser(cs, textTheme);

    final canChangeAction = action == _VaultAction.compute
        ? !_vaultBusy
        : !_verifyBusy && !_loadingManifest;

    return [
      Row(
        children: [
          Expanded(
            child: Text(
              action == _VaultAction.compute
                  ? context.l10n.hashVerifierVaultActionComputeTitle
                  : context.l10n.hashVerifierVaultActionVerifyTitle,
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: canChangeAction ? () => setState(() => _vaultAction = null) : null,
            child: Text(context.l10n.hashVerifierVaultChangeActionButton),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      ...(action == _VaultAction.compute
          ? _buildVaultComputeSection(cs, textTheme)
          : _buildVaultVerifySection(cs, textTheme)),
    ];
  }

  List<Widget> _buildVaultActionChooser(ColorScheme cs, TextTheme textTheme) {
    return [
      Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            SheetOptionTile(
              icon: Icons.tag_rounded,
              title: context.l10n.hashVerifierVaultActionComputeTitle,
              subtitle: context.l10n.hashVerifierVaultActionComputeSubtitle,
              onTap: () => setState(() => _vaultAction = _VaultAction.compute),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
            SheetOptionTile(
              icon: Icons.fact_check_outlined,
              iconColor: cs.tertiary,
              title: context.l10n.hashVerifierVaultActionVerifyTitle,
              subtitle: context.l10n.hashVerifierVaultActionVerifySubtitle,
              onTap: () => setState(() => _vaultAction = _VaultAction.verify),
            ),
          ],
        ),
      ),
    ];
  }

  /// "Compute Entire Vault": scan-then-hash flow driven by
  /// [HashOperationController], phase by phase.
  List<Widget> _buildVaultComputeSection(ColorScheme cs, TextTheme textTheme) {
    final phase = _vaultProgress.phase;
    switch (phase) {
      case HashOperationPhase.scanning:
        return _buildVaultScanningTab(cs, textTheme);
      case HashOperationPhase.confirming:
        return _buildVaultConfirmingTab(cs, textTheme);
      case HashOperationPhase.hashing:
        return _buildVaultHashingTab(cs, textTheme);
      case HashOperationPhase.completed:
      case HashOperationPhase.cancelled:
        return _buildVaultCompletedTab(cs, textTheme);
      case HashOperationPhase.failed:
        return _buildVaultFailedTab(cs, textTheme);
      case HashOperationPhase.selecting:
        return _buildVaultSelectingTab(cs, textTheme);
    }
  }

  List<Widget> _buildVaultSelectingTab(ColorScheme cs, TextTheme textTheme) {
    final vaults = widget.mountedContainers?.value ?? [];
    if (vaults.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(
            child: Text(
              context.l10n.hashVerifierVaultNoVaultsMessage,
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ];
    }
    if (_vaultTarget == null || !vaults.any((v) => v.volId == _vaultTarget!.volId)) {
      _vaultTarget = vaults.first;
    }

    return [
      OptionPickerTile<int>(
        label: context.l10n.hashVerifierVaultPickerLabel,
        value: _vaultTarget!.volId,
        prefixIcon: Icons.lock_open_rounded,
        options: [
          for (final v in vaults) SelectOption(value: v.volId, label: v.displayName),
        ],
        onChanged: (volId) => setState(() {
          _vaultTarget = vaults.firstWhere((v) => v.volId == volId, orElse: () => vaults.first);
        }),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        context.l10n.hashVerifierAlgorithmsLabel,
        style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final algo in HashAlgorithm.values)
            FilterChip(
              label: Text(algo.label),
              selected: _vaultAlgorithms.contains(algo),
              showCheckmark: false,
              onSelected: (selected) => setState(() {
                if (selected) {
                  _vaultAlgorithms.add(algo);
                } else {
                  _vaultAlgorithms.remove(algo);
                }
              }),
            ),
        ],
      ),
      if (_vaultError != null) ...[
        const SizedBox(height: AppSpacing.md),
        InlineErrorBanner(_vaultError!),
      ],
      const SizedBox(height: AppSpacing.lg),
      FilledButton.icon(
        onPressed: _vaultAlgorithms.isEmpty ? null : _startVaultScan,
        icon: const Icon(Icons.travel_explore_rounded, size: 18),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
        ),
        label: Text(
          context.l10n.hashVerifierCheckEntireVaultButton,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    ];
  }

  List<Widget> _buildVaultScanningTab(ColorScheme cs, TextTheme textTheme) {
    return [
      Text(
        context.l10n.hashVerifierVaultScanningLabel,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: AppSpacing.sm),
      const LinearProgressIndicator(),
      const SizedBox(height: AppSpacing.sm),
      Text(
        context.l10n.hashVerifierVaultFilesDiscoveredLabel(_vaultProgress.discoveredFiles),
        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: 4),
      Text(
        _vaultProgress.currentPath ?? '',
        style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: AppSpacing.lg),
      OutlinedButton(
        onPressed: _cancelVaultOperation,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
        ),
        child: Text(context.l10n.hashVerifierCancelButton),
      ),
    ];
  }

  List<Widget> _buildVaultConfirmingTab(ColorScheme cs, TextTheme textTheme) {
    final isEmpty = _vaultProgress.discoveredFiles == 0;
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.hashVerifierVaultConfirmTitle,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.hashVerifierVaultConfirmFilesLabel(_vaultProgress.discoveredFiles),
              style: textTheme.bodyMedium,
            ),
            Text(
              formatBytes(_vaultProgress.discoveredBytes),
              style: textTheme.bodyMedium,
            ),
            Text(
              _vaultAlgorithms.map((a) => a.label).join(', '),
              style: textTheme.bodyMedium,
            ),
            if (!isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                context.l10n.hashVerifierVaultConfirmWarning,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                context.l10n.hashVerifierVaultEmptyMessage,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
      if (_vaultError != null) ...[
        const SizedBox(height: AppSpacing.md),
        InlineErrorBanner(_vaultError!),
      ],
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _resetVaultOperation,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
              ),
              child: Text(context.l10n.hashVerifierCancelButton),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton(
              onPressed: isEmpty ? null : _startVaultHashing,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
              ),
              child: Text(
                context.l10n.hashVerifierVaultStartButton,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildVaultHashingTab(ColorScheme cs, TextTheme textTheme) {
    final progress = _vaultProgress;
    return [
      Text(
        context.l10n.hashVerifierVaultHashingProgressLabel(
          progress.completedFiles,
          progress.discoveredFiles,
        ),
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        progress.currentPath ?? '',
        style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: AppSpacing.sm),
      LinearProgressIndicator(value: progress.hashingFraction),
      const SizedBox(height: 6),
      Text(
        context.l10n.splitJoinOperationProgress(
          formatBytes(progress.processedBytes),
          formatBytes(progress.discoveredBytes),
        ),
        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: AppSpacing.lg),
      OutlinedButton(
        onPressed: _cancelVaultOperation,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
        ),
        child: Text(context.l10n.hashVerifierCancelButton),
      ),
    ];
  }

  List<Widget> _buildVaultCompletedTab(ColorScheme cs, TextTheme textTheme) {
    final aggregate = _vaultProgress.aggregate;
    final cancelled = _vaultProgress.phase == HashOperationPhase.cancelled;

    return [
      if (cancelled) InlineErrorBanner(context.l10n.hashVerifierVaultCancelledMessage),
      if (aggregate != null) ...[
        if (cancelled) const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.hashVerifierVaultCompleteTitle,
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(context.l10n.hashVerifierVaultCompleteFilesLabel(aggregate.filesChecked)),
              Text(context.l10n.hashVerifierVaultCompleteBytesLabel(formatBytes(aggregate.bytesProcessed))),
              const SizedBox(height: 8),
              Text(
                context.l10n.hashVerifierVaultCompleteSucceededLabel(aggregate.filesSucceeded),
                style: TextStyle(color: context.semanticColors.success),
              ),
              Text(
                context.l10n.hashVerifierVaultCompleteFailedLabel(aggregate.filesFailed),
                style: aggregate.filesFailed > 0 ? TextStyle(color: cs.error) : null,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.hashVerifierVaultElapsedLabel(_formatElapsed(aggregate.elapsed)),
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (aggregate.fileResults.any((r) => r.hasError)) ...[
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in aggregate.fileResults.where((r) => r.hasError))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${r.source.displayName}: ${r.error}',
                        style: textTheme.labelSmall?.copyWith(color: cs.error),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (aggregate.fileResults.any((r) => !r.hasError)) ...[
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.hashVerifierExportAlgorithmLabel,
                  style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              DropdownButton<HashAlgorithm>(
                value: _vaultAlgorithms.contains(_vaultExportAlgorithm)
                    ? _vaultExportAlgorithm
                    : (_vaultAlgorithms.isEmpty ? null : _vaultAlgorithms.first),
                items: [
                  for (final algo in _vaultAlgorithms)
                    DropdownMenuItem(value: algo, child: Text(algo.label)),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _vaultExportAlgorithm = val);
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _exportManifestResults(
              aggregate.fileResults.where((r) => r.digests.containsKey(_vaultExportAlgorithm)).toList(),
              _vaultExportAlgorithm,
            ),
            icon: const Icon(Icons.save_alt_rounded, size: 18),
            label: Text(context.l10n.hashVerifierExportManifestButton),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
      ],
      const SizedBox(height: AppSpacing.lg),
      FilledButton(
        onPressed: _resetVaultOperation,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
        ),
        child: Text(
          context.l10n.hashVerifierVaultNewCheckButton,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    ];
  }

  List<Widget> _buildVaultFailedTab(ColorScheme cs, TextTheme textTheme) {
    return [
      InlineErrorBanner(
        context.l10n.hashVerifierVaultFailedMessage(_vaultProgress.failureMessage ?? ''),
      ),
      const SizedBox(height: AppSpacing.lg),
      FilledButton(
        onPressed: _resetVaultOperation,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
        ),
        child: Text(
          context.l10n.hashVerifierVaultNewCheckButton,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    ];
  }

  /// "Verify Entire Vault": the same manifest-loading UI as the manual
  /// Verify tab, but with manual "add files" replaced by one button that
  /// scans the manifest's whole vault and runs the existing
  /// match-then-verify pipeline over everything it finds.
  List<Widget> _buildVaultVerifySection(ColorScheme cs, TextTheme textTheme) {
    final matchCount = _rows.where((r) => r.status == VerifyStatus.match).length;
    final mismatchCount = _rows
        .where((r) => r.status == VerifyStatus.mismatch || r.status == VerifyStatus.error)
        .length;
    final missingCount = _rows.where((r) => r.status == VerifyStatus.missing).length;
    final manifestFromVault = _manifestSource?.isFromVault ?? false;
    final matchedRowCount = _rows.where((r) => r.matchedSource != null).length;

    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(Icons.checklist_rtl_rounded, size: AppIconSize.small, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.hashVerifierManifestLabel,
                    style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  Text(
                    _manifestSource?.displayName ?? context.l10n.noFileSelectedLabel,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_manifestSource != null)
                    Text(
                      context.l10n.hashVerifierManifestEntryCount(_manifestEntries.length),
                      style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy ? null : _pickManifest,
              child: Text(
                _manifestSource == null
                    ? context.l10n.hashVerifierLoadManifestButton
                    : context.l10n.hashVerifierChangeManifestButton,
              ),
            ),
          ],
        ),
      ),
      if (_manifestSource == null) ...[
        const SizedBox(height: AppSpacing.md),
        InlineBanner(context.l10n.hashVerifierNoManifestLoadedMessage),
      ] else if (!manifestFromVault) ...[
        const SizedBox(height: AppSpacing.md),
        InlineBanner(
          context.l10n.hashVerifierVaultVerifyRequiresVaultManifestMessage,
          tone: AppBannerTone.warning,
        ),
      ],
      if (_verifyError != null) ...[
        const SizedBox(height: AppSpacing.md),
        InlineErrorBanner(_verifyError!),
      ],
      if (_rows.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        InlineBanner(
          context.l10n.hashVerifierSummaryMessage(matchCount, mismatchCount, missingCount),
          tone: mismatchCount > 0
              ? AppBannerTone.error
              : (missingCount > 0 ? AppBannerTone.warning : AppBannerTone.success),
        ),
        const SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final row in _rows) _VerifyRowTile(row: row),
              ],
            ),
          ),
        ),
      ],
      if (_verifyBusy && matchedRowCount > 1) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.l10n.hashVerifierVerifyProgressLabel(_verifyIndex, matchedRowCount),
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
      if (_verifyBusy) ...[
        const SizedBox(height: AppSpacing.sm),
        LinearProgressIndicator(
          value: (_verifyTotal != null && _verifyTotal! > 0)
              ? (_verifyDone ?? 0) / _verifyTotal!
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          _verifyTotal != null
              ? context.l10n.splitJoinOperationProgress(
                  formatBytes(_verifyDone ?? 0),
                  formatBytes(_verifyTotal!),
                )
              : formatBytes(_verifyDone ?? 0),
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      if (_verifyBusy)
        OutlinedButton(
          onPressed: _cancelVerify,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: Text(context.l10n.hashVerifierCancelButton),
        )
      else
        FilledButton.icon(
          onPressed: (manifestFromVault && !_loadingManifest) ? _verifyEntireVault : null,
          icon: _loadingManifest
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.travel_explore_rounded, size: 18),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          label: Text(
            context.l10n.hashVerifierVaultVerifyButton,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
    ];
  }
}

/// One row inside the Compute tab's file list: filename, remove button,
/// and (once computed) each requested algorithm's hex digest with a copy
/// button.
class _SourceRow extends StatelessWidget {
  final CryptoSourceItem source;
  final HashComputeResult? result;
  final Set<HashAlgorithm> algorithms;
  final bool enabled;
  final VoidCallback onRemove;
  final void Function(String hex) onCopy;

  const _SourceRow({
    required this.source,
    required this.result,
    required this.algorithms,
    required this.enabled,
    required this.onRemove,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                source.isFromVault ? Icons.lock_rounded : iconForFile(source.displayName),
                size: 16,
                color: source.isFromVault ? cs.primary : colorForFile(source.displayName),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source.displayName,
                  style: textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (result?.hasError == true)
                Icon(Icons.error_outline_rounded, size: 16, color: cs.error)
              else if (result != null)
                Icon(Icons.check_circle_outline_rounded, size: 16, color: cs.primary),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                onPressed: enabled ? onRemove : null,
              ),
            ],
          ),
          if (result != null) ...[
            if (result!.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 2),
                child: Text(
                  result!.error!,
                  style: textTheme.labelSmall?.copyWith(color: cs.error),
                ),
              )
            else
              for (final algo in algorithms)
                if (result!.digests[algo] != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            algo.label,
                            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            result!.digests[algo]!,
                            style: textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onCopy(result!.digests[algo]!),
                        ),
                      ],
                    ),
                  ),
          ],
        ],
      ),
    );
  }
}

/// One row inside the Verify tab's results list.
class _VerifyRowTile extends StatelessWidget {
  final VerifyRow row;

  const _VerifyRowTile({required this.row});

  (IconData, Color) _visual(BuildContext context) {
    final cs = context.colors;
    final semantic = context.semanticColors;
    return switch (row.status) {
      VerifyStatus.match => (Icons.check_circle_rounded, semantic.success),
      VerifyStatus.mismatch => (Icons.cancel_rounded, cs.error),
      VerifyStatus.error => (Icons.error_rounded, cs.error),
      VerifyStatus.missing => (Icons.help_outline_rounded, cs.onSurfaceVariant),
      VerifyStatus.pending => (Icons.radio_button_unchecked_rounded, cs.onSurfaceVariant),
      VerifyStatus.computing => (Icons.hourglass_top_rounded, cs.primary),
    };
  }

  String _statusLabel(BuildContext context) => switch (row.status) {
        VerifyStatus.match => context.l10n.hashVerifierStatusMatch,
        VerifyStatus.mismatch => context.l10n.hashVerifierStatusMismatch,
        VerifyStatus.error => row.errorMessage ?? context.l10n.hashVerifierStatusMismatch,
        VerifyStatus.missing => context.l10n.hashVerifierStatusMissing,
        VerifyStatus.pending || VerifyStatus.computing => context.l10n.hashVerifierStatusPending,
      };

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final (icon, color) = _visual(context);
    final showDetail = row.status == VerifyStatus.mismatch || row.status == VerifyStatus.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              row.status == VerifyStatus.computing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: color),
                    )
                  : Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.entry.fileName,
                      style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${row.entry.algorithm.label} • ${_statusLabel(context)}',
                      style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showDetail && row.computedHex != null) ...[
            const SizedBox(height: 6),
            Text(
              '${context.l10n.hashVerifierExpectedLabel}: ${row.entry.expectedHex}',
              style: textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
            ),
            Text(
              '${context.l10n.hashVerifierActualLabel}: ${row.computedHex}',
              style: textTheme.labelSmall?.copyWith(fontFamily: 'monospace', color: cs.error),
            ),
          ],
        ],
      ),
    );
  }
}