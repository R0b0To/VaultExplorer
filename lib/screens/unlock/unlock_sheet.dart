import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../../services/vaultexplorer_api.dart';
import '../../services/app_settings_service.dart';
import '../../models/mounted_container.dart';
import '../../utils/validation_utils.dart';
import '../../widgets/common_widgets.dart';
import '../lock/pattern_lock_view.dart';
import '../../models/crypto_algorithms.dart';

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
  final List<KeyfileRef> _keyfiles = [];
  bool _pickingKeyfiles = false;

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
        setState(() => _progress = progress);
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
      );
      await ContainerRepository.instance.save(migrated);
      if (!mounted) return;

      setState(() {
        _selectedUri = migrated.uri;
        _selectedName = result.displayName;
        _unlockMethod = migrated.unlockMethod;
        _cipherId = migrated.cipherId;
        _hashId = migrated.hashId;
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

      var result = await vaultExplorerApi.unlockContainer(
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
      );

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
          );
          await ContainerRepository.instance.save(newRecord);
          savedRecord = newRecord;
        } else if (widget.initialUri != null) {
          final records = await ContainerRepository.instance.loadAll();
          final existing = records[widget.initialUri];
          if (existing != null &&
              (existing.cipherId != result.matchedCipherId ||
                  existing.hashId != result.matchedHashId)) {
            final updated = existing.copyWith(
              cacheDerivedKey: shouldCacheDerivedKey,
              cipherId: result.matchedCipherId,
              hashId: result.matchedHashId,
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

  String get _unlockProgressLabel {
    final p = _progress;
    if (p == null || p.total <= 0) return 'Decrypting...';
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
                      ? cs.primaryContainer.withOpacity(0.12)
                      : cs.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: _selectedUri != null
                          ? cs.primary
                          : cs.outlineVariant.withOpacity(0.5),
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
                                    ? 'Selected Container'
                                    : 'VeraCrypt Container',
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
                            color: cs.onSurfaceVariant.withOpacity(0.5),
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
                  color: cs.errorContainer.withOpacity(0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: cs.error.withOpacity(0.25)),
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
                                      color: cs.onErrorContainer.withOpacity(0.8),
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
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: cs.outlineVariant.withOpacity(0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withOpacity(0.4),
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
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: cs.outlineVariant.withOpacity(0.3)),
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
                          filled: true,
                          fillColor: cs.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: cs.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: cs.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: cs.primary, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2. Keyfiles Selection Box
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.insert_drive_file_outlined, size: 20, color: cs.primary),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Keyfiles (optional)',
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                TextButton.icon(
                                  onPressed: _pickingKeyfiles ? null : _pickKeyfiles,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: _pickingKeyfiles
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Add file'),
                                ),
                              ],
                            ),
                            if (_keyfiles.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _keyfiles
                                    .map(
                                      (k) => InputChip(
                                        avatar: Icon(Icons.description_outlined, size: 16, color: cs.onSurfaceVariant),
                                        label: Text(
                                          k.displayName,
                                          style: textTheme.bodySmall,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onDeleted: () => _removeKeyfile(k),
                                        deleteIconColor: cs.error,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        backgroundColor: cs.surfaceContainerHigh,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              Text(
                                'No keyfiles attached',
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant.withOpacity(0.6),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 3. Collapsible Advanced parameters (PIM, Cipher, Hash)
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          title: Text(
                            'Advanced parameters',
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                          leading: Icon(Icons.tune_rounded, color: cs.primary),
                          childrenPadding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
                          ),
                          collapsedShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
                          ),
                          backgroundColor: cs.surfaceContainerLow,
                          collapsedBackgroundColor: cs.surfaceContainerLow,
                          children: [
                            TextField(
                              controller: _pimCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'PIM  (leave blank for default)',
                                prefixIcon: Icon(Icons.password_outlined, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<int>(
                              initialValue: _cipherId,
                              decoration: InputDecoration(
                                labelText: 'Encryption Algorithm',
                                prefixIcon: Icon(Icons.security_rounded, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: CipherAlgo.dropdownItems(),
                              onChanged: (val) {
                                if (val != null) setState(() => _cipherId = val);
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<int>(
                              initialValue: _hashId,
                              decoration: InputDecoration(
                                labelText: 'Hash Algorithm',
                                prefixIcon: Icon(Icons.tag_rounded, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: HashAlgo.dropdownItems(),
                              onChanged: (val) {
                                if (val != null) setState(() => _hashId = val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 4. Remember container Toggle
                      if (widget.initialUri == null) ...[
                        Container(
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
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
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error!,
                            style: textTheme.bodyMedium?.copyWith(
                              color: cs.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),

                // Primary Unlock Action Button
                FilledButton(
                  onPressed: _loading ? null : _unlock,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
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
                                color: cs.primary,
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