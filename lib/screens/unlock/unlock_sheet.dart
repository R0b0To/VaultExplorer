import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../../services/vaultexplorer_api.dart';
import '../../services/app_settings_service.dart';
import '../../models/mounted_container.dart';
import '../../utils/validation_utils.dart';
import '../../widgets/common_widgets.dart';
import '../../theme.dart';
import '../lock/pattern_lock_view.dart';

class UnlockSheet extends StatefulWidget {
  final void Function(MountedContainer container, {ContainerRecord? record}) onMounted;
  final String? initialUri;
  final String? initialName;
  final String? prefillPassword;
  final bool documentProvider;
  final List<String> mountedUris;

  const UnlockSheet({
    Key? key,
    required this.onMounted,
    this.initialUri,
    this.initialName,
    this.prefillPassword,
    this.documentProvider = false,
    this.mountedUris = const [],
  }) : super(key: key);

  @override
  State<UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends State<UnlockSheet> {
  late TextEditingController _passwordCtrl;
  final _pimCtrl = TextEditingController();
  String? _selectedUri;
  String? _selectedName;
  bool _obscure = true;
  bool _loading = false;
  bool _remember = false;
  String? _error;
  int _cipherId = 255; // Auto
  int _hashId = 255; // Auto
  String _containerFormat = 'veracrypt';
  final List<KeyfileRef> _keyfiles = [];
  bool _pickingKeyfiles = false;

  /// True when the saved record (or post-unlock result) indicates a LUKS
  /// container — hides PIM, keyfiles, and cipher/hash pickers which don't
  /// apply to LUKS.
  bool get _isLuks => _containerFormat == 'luks1' || _containerFormat == 'luks2';

  // ── Cancel / progress state ──────────────────────────────────────────────
  int? _activeVolId;
  UnlockProgress? _progress;
  late final void Function(int) _onUnlockStarted;
  late final void Function(UnlockProgress) _onUnlockProgress;

  // ── Unlock method state ──────────────────────────────────────────────────
  ContainerUnlockMethod _unlockMethod = ContainerUnlockMethod.password;
  bool _showPasswordFallback = false;
  bool _patternError = false;
  int _patternResetKey = 0;
  String? _storedPatternHash;
  bool _loadingAuth = true;
  bool _containerMissing = false;

  bool get _passwordPrefilled =>
      widget.prefillPassword?.isNotEmpty == true &&
      _passwordCtrl.text == widget.prefillPassword;

  @override
  void initState() {
    super.initState();
    _passwordCtrl = TextEditingController(text: widget.prefillPassword ?? '');
    if (widget.initialUri != null) {
      _selectedUri = widget.initialUri;
      _selectedName = widget.initialName;
      _remember = true;
    }
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

  @override
  void dispose() {
    // If the user backs out while an unlock is still running (there's no
    // PopScope blocking that — see vault_dashboard.dart's plain
    // Navigator.push), the native derivation would otherwise keep running
    // in the background, invisible, and block a subsequent attempt at the
    // same volId for however long it takes to finish. Cancel it here
    // instead of leaving it orphaned.
    if (_loading && _activeVolId != null) {
      vaultExplorerApi.cancelUnlock(_activeVolId!);
    }
    VaultExplorerApi.removeUnlockStartedListener(_onUnlockStarted);
    VaultExplorerApi.removeUnlockProgressListener(_onUnlockProgress);
    _passwordCtrl.dispose();
    _pimCtrl.dispose();
    super.dispose();
  }

  Future<void> _initUnlockMethod() async {
    if (widget.initialUri == null) {
      if (mounted) setState(() => _loadingAuth = false);
      return;
    }

    try {
      final records = await ContainerRepository.instance.loadAll();
      final record = records[widget.initialUri];
      if (record == null) {
        if (mounted) setState(() => _loadingAuth = false);
        return;
      }

      var exists = true;
      try {
        exists = await vaultExplorerApi.documentExists(widget.initialUri!);
      } catch (_) {
        exists = true;
      }
      if (!exists) {
        if (mounted) {
          setState(() {
            _containerMissing = true;
            _loadingAuth = false;
          });
        }
        return;
      }

      _unlockMethod = record.unlockMethod;
      _cipherId = record.cipherId;
      _hashId = record.hashId;
      _containerFormat = record.containerFormat;

      if (_unlockMethod == ContainerUnlockMethod.pattern) {
        _storedPatternHash = await ContainerRepository.instance.getPatternHash(
          widget.initialUri!,
        );
      }

      if (mounted) setState(() => _loadingAuth = false);

      if (_unlockMethod == ContainerUnlockMethod.biometrics) {
        _tryBiometric();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAuth = false);
    }
  }

  Future<void> _relocateContainer() async {
    final oldUri = widget.initialUri;
    if (oldUri == null) return;
    try {
      final result = await vaultExplorerApi.pickContainer();
      if (result == null || !mounted) return;

      setState(() => _loadingAuth = true);

      final records = await ContainerRepository.instance.loadAll();
      final existing = records[oldUri];
      if (existing == null) {
        if (mounted) {
          setState(() {
            _loadingAuth = false;
            _error = 'Saved settings for this container could not be found.';
          });
        }
        return;
      }

      final savedPassword = await ContainerRepository.instance.getPassword(oldUri);
      final savedPatternHash = await ContainerRepository.instance.getPatternHash(oldUri);
      await ContainerRepository.instance.remove(oldUri);

      final migrated = ContainerRecord(
        uri: result.uri,
        label: existing.label,
        rememberPassword: existing.rememberPassword,
        unlockMethod: existing.unlockMethod,
        autoCloseMins: existing.autoCloseMins,
        documentProvider: existing.documentProvider,
        thumbnailCacheMode: existing.thumbnailCacheMode,
        cacheDerivedKey: existing.cacheDerivedKey,
        pendingPassword: savedPassword,
        pendingPatternHash: savedPatternHash,
        cipherId: existing.cipherId,
        hashId: existing.hashId,
        containerFormat: existing.containerFormat,
      );
      await ContainerRepository.instance.save(migrated);
      if (!mounted) return;

      setState(() {
        _selectedUri = migrated.uri;
        _selectedName = result.displayName;
        _unlockMethod = migrated.unlockMethod;
        _cipherId = migrated.cipherId;
        _hashId = migrated.hashId;
        _containerFormat = migrated.containerFormat;
        _storedPatternHash = savedPatternHash;
        _containerMissing = false;
        _loadingAuth = false;
      });

      if (_unlockMethod == ContainerUnlockMethod.biometrics) {
        _tryBiometric();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingAuth = false;
          _error = 'Could not update the container location: $e';
        });
      }
    }
  }

  Future<void> _tryBiometric() async {
    try {
      final localAuth = LocalAuthentication();
      final ok = await localAuth.authenticate(
        localizedReason: 'Authenticate to unlock container',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (ok && mounted) {
        final records = await ContainerRepository.instance.loadAll();
        final record = records[widget.initialUri!];
        final appSettings = await AppSettingsService.loadSettings();
        final shouldCacheGoingForward =
            (record?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled;
        final shouldPreloadCachedKey = record?.cacheDerivedKey ?? false;
        final cachedKey = shouldPreloadCachedKey
            ? await vaultExplorerApi.loadDerivedKey(widget.initialUri!)
            : null;
        debugPrint('unlock: biometric cached-key present=${cachedKey != null && cachedKey.isNotEmpty} for ${widget.initialUri}');
        if (cachedKey != null && cachedKey.isNotEmpty) {
          await _unlock(
            preservedKey: cachedKey,
            shouldCacheDerivedKeyOverride: shouldCacheGoingForward,
          );
          return;
        }

        final pw = await ContainerRepository.instance.getPassword(widget.initialUri!);
        if (pw != null && pw.isNotEmpty) {
          _passwordCtrl.text = pw;
          await _unlock(shouldCacheDerivedKeyOverride: shouldCacheGoingForward, passwordOverride: pw);
        } else {
          setState(() {
            _error = 'Initializing secure credentials. Please unlock manually once to authorize biometric access.';
            _showPasswordFallback = true;
          });
        }
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Biometric error: ${e.message}';
          _showPasswordFallback = true;
        });
      }
    }
  }

  Future<void> _onPatternComplete(List<int> pattern) async {
    if (_storedPatternHash == null) {
      setState(() {
        _error = 'No pattern configured. Please enter password manually.';
        _showPasswordFallback = true;
      });
      return;
    }

    final attempt = hashPattern(pattern);
    if (attempt == _storedPatternHash) {
      final records = await ContainerRepository.instance.loadAll();
      final record = records[widget.initialUri!];
      final appSettings = await AppSettingsService.loadSettings();
      final shouldCacheGoingForward =
          (record?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled;
      final shouldPreloadCachedKey = record?.cacheDerivedKey ?? false;
      final cachedKey = shouldPreloadCachedKey
          ? await vaultExplorerApi.loadDerivedKey(widget.initialUri!)
          : null;

      if (cachedKey != null && cachedKey.isNotEmpty) {
        await _unlock(preservedKey: cachedKey, shouldCacheDerivedKeyOverride: shouldCacheGoingForward);
        return;
      }

      final pw = await ContainerRepository.instance.getPassword(widget.initialUri!);
      if (pw != null && pw.isNotEmpty) {
        _passwordCtrl.text = pw;
        await _unlock(shouldCacheDerivedKeyOverride: shouldCacheGoingForward, passwordOverride: pw);
      } else {
        setState(() {
          _error = 'Initializing secure credentials. Please unlock manually once to authorize pattern access.';
          _showPasswordFallback = true;
        });
      }
    } else {
      setState(() => _patternError = true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() { _patternError = false; _patternResetKey++; });
      });
    }
  }

Future<void> _pickFile() async {
    if (widget.initialUri != null) return;
    try {
      final result = await vaultExplorerApi.pickContainer();
      if (result != null) {
        // Prevent selection of already mounted files
        if (widget.mountedUris.contains(result.uri)) {
          setState(() {
            _error = 'This container is already mounted.';
            _selectedUri = null;
            _selectedName = null;
          });
          return;
        }
        
        setState(() {
          _selectedUri = result.uri;
          _selectedName = result.displayName;
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'File picker failed: $e');
    }
  }

  // Treats a stale-cached-key auth failure the same as a null result, so
  // the caller's existing "clear cache and retry with the real password"
  // logic actually runs instead of this exception bypassing it entirely.
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
  }) async {
    if (_selectedUri == null) {
      setState(() => _error = 'Select a container first');
      return;
    }

    if (widget.mountedUris.contains(_selectedUri)) {
      setState(() => _error = 'This container is already mounted.');
      return;
    }

    var effectivePassword = (passwordOverride ?? _passwordCtrl.text).trim();
    if (effectivePassword.isEmpty && preservedKey == null && _keyfiles.isEmpty) {
      setState(() => _error = 'Password or keyfiles required');
      return;
    }
    setState(() { _loading = true; _error = null; _activeVolId = null; _progress = null; });

    try {
      final pim = clampPim(_pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0);
      final name = _selectedName ?? 'Container';
      final keyfilePaths = _keyfiles.map((k) => k.uri).toList();

      final records = await ContainerRepository.instance.loadAll();
      final record = records[_selectedUri!];
      final appSettings = await AppSettingsService.loadSettings();
      final isKnownRecord = record != null;
      // Only cache the derived key for containers we'll actually keep track of
      // (an existing record, or the user checked "remember"). Otherwise we'd
      // leave an orphaned cached key in the Keystore for a container the app
      // has no record of and will never clear.
      final shouldCacheDerivedKey = shouldCacheDerivedKeyOverride ??
          ((isKnownRecord || _remember) &&
              ((record?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled));

      final shouldPreloadCachedKey = preservedKey == null &&
          _unlockMethod == ContainerUnlockMethod.rememberPassword &&
          _passwordPrefilled &&
          (record?.cacheDerivedKey ?? false);
      final resolvedPreservedKey = preservedKey ??
          (shouldPreloadCachedKey
              ? await vaultExplorerApi.loadDerivedKey(_selectedUri!)
              : null);
      debugPrint('unlock: method=$_unlockMethod shouldCacheDerivedKey=$shouldCacheDerivedKey preservedKeyLen=${resolvedPreservedKey?.length ?? 0}');

      // A stale cached derived key doesn't come back as a null result —
      // native throws PlatformException(code: 'AUTH_FAIL') instead. Only
      // swallow that when we're actually trying a cached key, so it falls
      // into the same "clear cache and retry with the real password"
      // branch below instead of surfacing as a user-facing error for a
      // cache problem the user didn't cause and can't fix.
      var result = resolvedPreservedKey == null
          ? await vaultExplorerApi.unlockContainer(
              _selectedUri!,
              effectivePassword,
              pim,
              displayName: name,
              documentProvider: widget.documentProvider,
              cipherId: _cipherId,
              hashId: _hashId,
              preservedKey: resolvedPreservedKey,
              cacheDerivedKey: shouldCacheDerivedKey,
              keyfilePaths: keyfilePaths,
            )
          : await _unlockSwallowingStaleAuthFail(() => vaultExplorerApi.unlockContainer(
              _selectedUri!,
              effectivePassword,
              pim,
              displayName: name,
              documentProvider: widget.documentProvider,
              cipherId: _cipherId,
              hashId: _hashId,
              preservedKey: resolvedPreservedKey,
              cacheDerivedKey: shouldCacheDerivedKey,
              keyfilePaths: keyfilePaths,
            ));

      if (result == null && resolvedPreservedKey != null) {
        await vaultExplorerApi.clearDerivedKey(_selectedUri!);
        if (effectivePassword.isEmpty) {
          effectivePassword =
              (await ContainerRepository.instance.getPassword(_selectedUri!))?.trim() ?? '';
        }
        if (effectivePassword.isNotEmpty || keyfilePaths.isNotEmpty) {
          result = await vaultExplorerApi.unlockContainer(
            _selectedUri!,
            effectivePassword,
            pim,
            displayName: name,
            documentProvider: widget.documentProvider,
            cipherId: _cipherId,
            hashId: _hashId,
            preservedKey: null,
            cacheDerivedKey: shouldCacheDerivedKey,
            keyfilePaths: keyfilePaths,
          );
        }
      }

      if (result != null) {
        // Tracks the record actually persisted to disk (if any), so we can
        // hand it to onMounted below rather than have the dashboard guess.
        ContainerRecord? savedRecord;

        if (_remember && widget.initialUri == null) {
          final newRecord = ContainerRecord(
            uri: _selectedUri!,
            label: name,
            rememberPassword: false,
            cacheDerivedKey: shouldCacheDerivedKey,
            cipherId: result.matchedCipherId,
            hashId: result.matchedHashId,
            containerFormat: result.containerFormat,
          );
          await ContainerRepository.instance.save(newRecord);
          savedRecord = newRecord;
        } else if (widget.initialUri != null) {
          final records = await ContainerRepository.instance.loadAll();
          final existing = records[widget.initialUri];
          if (existing != null &&
              (existing.cipherId != result.matchedCipherId ||
                  existing.hashId != result.matchedHashId ||
                  existing.containerFormat != result.containerFormat)) {
            final updated = existing.copyWith(
              cacheDerivedKey: shouldCacheDerivedKey,
              cipherId: result.matchedCipherId,
              hashId: result.matchedHashId,
              containerFormat: result.containerFormat,
            );
            await ContainerRepository.instance.save(updated);
            savedRecord = updated;
          } else {
            savedRecord = existing;
          }
        }

        final tempContainer = MountedContainer(
          uri: _selectedUri!,
          displayName: name,
          volId: result.volId,
          rootFiles: result.files,
          mountedAt: DateTime.now(),
          totalSpace: 0,
          freeSpace: 0,
        );

        final space = await vaultExplorerApi.getSpaceInfo(tempContainer);
        final total = (space != null && space.isNotEmpty) ? space[0] : 0;
        final free = (space != null && space.length > 1) ? space[1] : 0;

        widget.onMounted(
          MountedContainer(
            uri: _selectedUri!,
            displayName: name,
            volId: result.volId,
            rootFiles: result.files,
            mountedAt: DateTime.now(),
            totalSpace: total,
            freeSpace: free,
          ),
          record: savedRecord,
        );

        HapticFeedback.lightImpact();
        TextInput.finishAutofillContext(shouldSave: false);

        if (mounted) Navigator.pop(context);
      } else {
        setState(() => _error = 'Incorrect password or invalid container');
      }
    } on PlatformException catch (e) {
      // A cancellation the user asked for isn't an error — just quietly
      // drop back to the form instead of showing an error banner.
      if (e.code != 'CANCELLED') {
        setState(() => _error = e.message ?? 'Unknown error');
      }
    } finally {
      if (mounted) {
        setState(() { _loading = false; _activeVolId = null; _progress = null; });
      }
    }
  }

  Future<void> _pickKeyfiles() async {
    setState(() => _pickingKeyfiles = true);
    try {
      final picked = await vaultExplorerApi.pickKeyfiles();
      if (!mounted) return;
      setState(() {
        for (final k in picked) {
          if (!_keyfiles.any((existing) => existing.uri == k.uri)) {
            _keyfiles.add(k);
          }
        }
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Could not pick keyfiles');
    } finally {
      if (mounted) setState(() => _pickingKeyfiles = false);
    }
  }

  void _removeKeyfile(KeyfileRef keyfile) {
    setState(() => _keyfiles.removeWhere((k) => k.uri == keyfile.uri));
  }

  bool get _showPasswordUI {
    if (_showPasswordFallback) return true;
    if (widget.initialUri == null) return true;
    return _unlockMethod == ContainerUnlockMethod.password ||
        _unlockMethod == ContainerUnlockMethod.rememberPassword;
  }

  /// Live label for the unlock button while [_loading] — "Decrypting..."
  /// until the first progress event arrives (most re-unlocks of a known
  /// container skip auto-detect entirely and never get one), then "Trying
  /// <hash> (i of N)…" for as long as the cipher/hash search is running.
  String get _unlockProgressLabel {
    final p = _progress;
    if (p == null || p.total <= 0) return 'Decrypting...';
    if (_isLuks) {
      return p.total > 1
          ? 'Trying keyslot ${p.attempted} of ${p.total}…'
          : 'Trying keyslot…';
    }
    final hashName = hashAlgorithmName(p.hashId);
    return p.total > 1
        ? 'Trying $hashName (${p.attempted} of ${p.total})…'
        : 'Trying $hashName…';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialUri != null ? 'Unlock Container' : 'Mount Container',
        ),
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Modernized File Picker Card ───────────────────────────
              GestureDetector(
                onTap: _loading ? null : _pickFile,
                child: Card(
                  elevation: 0,
                  color: _selectedUri != null
                      ? cs.primaryContainer.withValues(alpha: 0.12)
                      : cs.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: _selectedUri != null
                          ? cs.primary
                          : cs.outlineVariant.withValues(alpha: 0.5),
                      width: _selectedUri != null ? 1.5 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _selectedUri != null
                                ? cs.primaryContainer
                                : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _selectedUri != null
                                ? Icons.lock_open_outlined
                                : Icons.folder_open_rounded,
                            size: 24,
                            color: _selectedUri != null
                                ? cs.onPrimaryContainer
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedUri != null
                                    ? (_isLuks
                                        ? 'LUKS Container'
                                        : 'Selected Container')
                                    : 'Encrypted Container',
                                style: textTheme.labelLarge?.copyWith(
                                  color: _selectedUri != null
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _selectedName ?? 'Tap to select container file…',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: _selectedUri != null
                                      ? cs.onSurface
                                      : cs.onSurfaceVariant,
                                  fontWeight: _selectedUri != null
                                      ? FontWeight.w500
                                      : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (_selectedUri != null && widget.initialUri == null) ...[
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: _loading
                                ? null
                                : () => setState(() {
                                      _selectedUri = null;
                                      _selectedName = null;
                                    }),
                            style: IconButton.styleFrom(
                              backgroundColor: cs.surfaceContainerHigh,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ] else if (_selectedUri != null && widget.initialUri != null) ...[
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 20,
                            color: cs.primary,
                          ),
                        ] else ...[
                          Icon(
                            Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Auth-specific UI ──────────────────────────────────────────
              if (_loadingAuth)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                )
              // ── Container file unreachable Card ────────────────────────
              else if (_containerMissing) ...[
                Card(
                  elevation: 0,
                  color: cs.errorContainer.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    side: BorderSide(color: cs.error.withValues(alpha: 0.25)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.find_in_page_outlined,
                                color: cs.error,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Container missing',
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: cs.onErrorContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'File path could not be resolved',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: cs.onErrorContainer.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'The container file may have been moved, deleted, or its host storage is currently disconnected.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    _loadingAuth = true;
                                    _containerMissing = false;
                                  });
                                  _initUnlockMethod();
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('Retry'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _relocateContainer,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('Locate file'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ]
              // ── Biometric Card ─────────────────────────────────────────
              else if (_unlockMethod == ContainerUnlockMethod.biometrics && !_showPasswordFallback) ...[
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.fingerprint_rounded,
                            size: 64,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Biometric Unlock',
                          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Authenticate to securely mount the container',
                          style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(() => _showPasswordFallback = true),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text('Use Password'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _tryBiometric,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text('Authenticate'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ]
              // ── Pattern Card ───────────────────────────────────────────
              else if (_unlockMethod == ContainerUnlockMethod.pattern && !_showPasswordFallback) ...[
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Draw Unlock Pattern',
                          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _patternError ? 'Wrong pattern — try again' : 'Connect your pattern sequence',
                          style: textTheme.bodyMedium?.copyWith(
                            color: _patternError ? cs.error : cs.onSurfaceVariant,
                            fontWeight: _patternError ? FontWeight.bold : null,
                          ),
                        ),
                        const SizedBox(height: 24),
                        PatternLockView(
                          key: ValueKey(_patternResetKey),
                          onPatternComplete: _onPatternComplete,
                          showError: _patternError,
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton(
                          onPressed: () => setState(() => _showPasswordFallback = true),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Use Password instead'),
                        ),
                      ],
                    ),
                  ),
                ),
              ]
              // ── Standard password fields ───────────────────────────────
              else if (_showPasswordUI) ...[
                AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Password Field
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        autofocus: widget.initialUri != null && widget.prefillPassword?.isEmpty != false,
                        onChanged: (_) => setState(() {}),
                        keyboardType: TextInputType.visiblePassword,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          hintText: 'Enter container password',
                          prefixIcon: Icon(Icons.lock_outline_rounded, size: 22, color: cs.primary),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_passwordPrefilled)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Tooltip(
                                    message: 'Using saved password',
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
                      const SizedBox(height: 16),

                      // 2. Keyfiles Selection Box. LUKS keyfiles work too —
                      // cryptsetup treats a keyfile as a *replacement* for
                      // the typed password, not an additive mix-in.
                      KeyfilesPicker(
                        keyfiles: _keyfiles,
                        picking: _pickingKeyfiles,
                        onPick: _pickKeyfiles,
                        onRemove: _removeKeyfile,
                      ),
                      if (_isLuks && _keyfiles.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 4),
                          child: Text(
                            'For LUKS containers the keyfile replaces the password.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      const SizedBox(height: 16),

                      // 3. Collapsible Advanced parameters (PIM, Cipher, Hash)
                      //    LUKS doesn't use PIM or VeraCrypt cipher/hash selection.
                      if (!_isLuks)
                        AdvancedParamsPanel(
                          pimController: _pimCtrl,
                          cipherId: _cipherId,
                          hashId: _hashId,
                          enabled: !_loading,
                          onCipherChanged: (val) => setState(() => _cipherId = val),
                          onHashChanged: (val) => setState(() => _hashId = val),
                        ),
                      const SizedBox(height: 16),

                      // 4. Remember container Toggle
                      if (widget.initialUri == null) ...[
                        Container(
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
                          ),
                          child: SwitchListTile(
                            value: _remember,
                            onChanged: (val) => setState(() => _remember = val),
                            title: Text(
                              'Remember container',
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              'Pin container on dashboard for quick access',
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.push_pin_outlined, color: cs.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  InlineErrorBanner(_error!),
                ],
                const SizedBox(height: 32),

                // Primary Unlock Action Button
                FilledButton(
                  onPressed: _loading ? null : _unlock,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: const StadiumBorder(),
                  ),
                  child: _loading
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
                                _unlockProgressLabel,
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
                          'Unlock Container',
                          style: textTheme.titleMedium?.copyWith(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                if (_loading && _activeVolId != null) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => vaultExplorerApi.cancelUnlock(_activeVolId!),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ] else if (_error != null) ...[
                const SizedBox(height: 16),
                InlineErrorBanner(_error!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}