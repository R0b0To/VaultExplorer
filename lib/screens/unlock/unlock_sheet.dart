import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../../services/vaultexplorer_api.dart';
import '../../services/container_repository.dart';
import '../../services/app_settings_service.dart';
import '../../models/mounted_container.dart';
import '../../utils/validation_utils.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../lock/pattern_lock_view.dart';

class UnlockSheet extends StatefulWidget {
  final ValueChanged<MountedContainer> onMounted;
  final String? initialUri;
  final String? initialName;
  final String? prefillPassword;
  final bool documentProvider;

  const UnlockSheet({
    Key? key,
    required this.onMounted,
    this.initialUri,
    this.initialName,
    this.prefillPassword,
    this.documentProvider = false,
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
  }

  @override
  void dispose() {
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

      // FIX: verify the file/document is actually reachable BEFORE doing
      // anything unlock-method-specific. Previously a container on
      // since-removed or relocated removable storage fell straight into
      // the password-lookup logic below — which only knows about locally
      // stored secrets, not file presence — and reported "No saved
      // password found" even when one WAS saved. The real problem was
      // simply that there was nothing there to unlock.
      var exists = true;
      try {
        exists = await vaultExplorerApi.documentExists(widget.initialUri!);
      } catch (_) {
        // If the check itself fails, don't block on our own uncertainty —
        // fall through and let the real unlock attempt surface the error.
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

/// Lets the user point at the same container's new location (moved file,
  /// or re-inserted removable storage now enumerating differently) and
  /// migrates the saved settings onto the new uri — same idea as the USB
  /// sheet's reconnect migration.
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
Future<void>_tryBiometric() async {
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
        // FIX: only attempt to reuse a stored key if THIS container record
        // has previously cached one itself. The global default alone must
        // never justify preloading a key for a uri we've never personally
        // derived one for — see the class-level rationale in _unlock().
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
            _error = 'No saved password found. Please enter it manually.';
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
          _error = 'No saved password found. Please enter it manually.';
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


  // ── File picking ─────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    if (widget.initialUri != null) return;
    try {
      final result = await vaultExplorerApi.pickContainer();
      if (result != null) {
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
    var effectivePassword = (passwordOverride ?? _passwordCtrl.text).trim();
    if (effectivePassword.isEmpty && preservedKey == null && _keyfiles.isEmpty) {
      setState(() => _error = 'Password or keyfiles required');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final pim = clampPim(_pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0);
      final name = _selectedName ?? 'Container';
      final keyfilePaths = _keyfiles.map((k) => k.uri).toList();

      final records = await ContainerRepository.instance.loadAll();
      final record = records[_selectedUri!];
      final appSettings = await AppSettingsService.loadSettings();
      final shouldCacheDerivedKey = shouldCacheDerivedKeyOverride ??
          ((record?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled);


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

      // FIX: a preserved key can go stale (uri reused for a new container).
      // Treat that failure as "the cache was wrong," not "the password was
      // wrong" — purge it and retry with a normal password-based unlock
      // before surfacing an error. Recovers the saved password ourselves if
      // we were only ever handed a key (biometric/pattern path never set one).
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
        if (_remember && widget.initialUri == null) {
          final record = ContainerRecord(
            uri: _selectedUri!,
            label: name,
            rememberPassword: false,
            cacheDerivedKey: shouldCacheDerivedKey,
            cipherId: result.matchedCipherId,
            hashId: result.matchedHashId,
          );
          await ContainerRepository.instance.save(record);
        } else if (widget.initialUri != null) {
          // FIX (perf): keep the saved record's remembered cipher/hash in
          // sync with whatever actually unlocked successfully.
          final records = await ContainerRepository.instance.loadAll();
          final existing = records[widget.initialUri];
          if (existing != null &&
              (existing.cipherId != result.matchedCipherId ||
                  existing.hashId != result.matchedHashId)) {
            await ContainerRepository.instance.save(
              existing.copyWith(
                cacheDerivedKey: shouldCacheDerivedKey,
                cipherId: result.matchedCipherId,
                hashId: result.matchedHashId,
              ),
            );
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
        );

        HapticFeedback.lightImpact();

        TextInput.finishAutofillContext(shouldSave: false);

        if (mounted) Navigator.pop(context);
      } else {
        setState(() => _error = 'Incorrect password or invalid container');
      }
    } on PlatformException catch (e) {
      setState(() => _error = e.message ?? 'Unknown error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Keyfiles ─────────────────────────────────────────────────────────────

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
    if (widget.initialUri == null) return true; // fresh mount — always show
    return _unlockMethod == ContainerUnlockMethod.password ||
        _unlockMethod == ContainerUnlockMethod.rememberPassword;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                widget.initialUri != null
                    ? 'Unlock Container'
                    : 'Mount Container',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // File picker
          GestureDetector(
            onTap: _loading ? null : _pickFile,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: _selectedUri != null
                      ? cs.primary
                      : cs.outlineVariant,
                  width: _selectedUri != null ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _selectedUri != null
                        ? Icons.description_outlined
                        : Icons.folder_open_rounded,
                    size: AppIconSize.standard,
                    color: _selectedUri != null
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedName ?? 'Select VeraCrypt container…',
                      style: textTheme.bodyMedium?.copyWith(
                        color: _selectedUri != null
                            ? cs.onSurface
                            : cs.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_selectedUri != null &&
                      widget.initialUri == null) ...[
                    GestureDetector(
                      onTap: _loading ? null : () => setState(() {
                        _selectedUri = null;
                        _selectedName = null;
                      }),
                      child: Icon(
                        Icons.clear_rounded,
                        size: AppIconSize.small,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.check_circle_rounded,
                      size: AppIconSize.small,
                      color: cs.primary,
                    ),
                  ] else if (_selectedUri != null &&
                      widget.initialUri != null) ...[
                    Icon(
                      Icons.lock_outline_rounded,
                      size: AppIconSize.small,
                      color: cs.primary,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Auth-specific UI ──────────────────────────────────────────
          if (_loadingAuth)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          // ── Container file unreachable ─────────────────────────────
          else if (_containerMissing) ...[
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.find_in_page_outlined,
              color: cs.error,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Container file not found',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Text(
          'The container may have been moved, deleted, or its storage is disconnected.',
          style: textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 16),

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
                child: const Text('Retry'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _relocateContainer,
                child: const Text('Locate file'),
              ),
            ),
          ],
        ),
      ],
    ),
  ),
]
          // ── Biometric prompt feedback ──────────────────────────────
          else if (_unlockMethod == ContainerUnlockMethod.biometrics &&
              !_showPasswordFallback) ...[
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: _loading ? 0.3 : 1.0,
                    child: IgnorePointer(
                      ignoring: _loading,
                      child: Column(
                        children: [
                          Icon(
                            Icons.fingerprint_rounded,
                            size: AppIconSize.hero,
                            color: cs.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Waiting for biometric...',
                            style: textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _tryBiometric,
                            child: const Text('Retry'),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => _showPasswordFallback = true),
                            child: const Text('Use Password'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_loading)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Unlocking...',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ]
          // ── Pattern grid ───────────────────────────────────────────
          else if (_unlockMethod == ContainerUnlockMethod.pattern &&
              !_showPasswordFallback) ...[
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: _loading ? 0.3 : 1.0,
                    child: IgnorePointer(
                      ignoring: _loading,
                      child: Column(
                        children: [
                          Text(
                            _patternError
                                ? 'Wrong pattern — try again'
                                : 'Draw your unlock pattern',
                            style: textTheme.bodyMedium?.copyWith(
                              color: _patternError ? cs.error : cs.onSurfaceVariant,
                              fontWeight: _patternError ? FontWeight.bold : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          PatternLockView(
                            key: ValueKey(_patternResetKey),
                            onPatternComplete: _onPatternComplete,
                            showError: _patternError,
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () =>
                                setState(() => _showPasswordFallback = true),
                            child: const Text('Use Password'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_loading)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Unlocking...',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ]
          // ── Standard password fields ───────────────────────────────
          else if (_showPasswordUI) ...[
            Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: _loading ? 0.3 : 1.0,
                  child: IgnorePointer(
                    ignoring: _loading,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _passwordCtrl,
                                obscureText: _obscure,
                                autofocus:
                                    widget.initialUri != null &&
                                    widget.prefillPassword?.isEmpty != false,
                                onChanged: (_) => setState(() {}),
                                keyboardType: TextInputType.visiblePassword,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: Icon(Icons.key_outlined, size: AppIconSize.small),
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
                                              size: AppIconSize.small,
                                              color: cs.primary,
                                            ),
                                          ),
                                        ),
                                      // FIX: previously each screen hand-rolled this
                                      // toggle; one variant elsewhere in the app used
                                      // the non-outlined icon pair by mistake. This
                                      // shared widget makes that divergence impossible.
                                      PasswordVisibilityToggle(
                                        obscured: _obscure,
                                        onToggle: () =>
                                            setState(() => _obscure = !_obscure),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Keyfiles (optional) — VeraCrypt lets you mix
                              // one or more keyfiles into the password
                              // before derivation, and even supports a
                              // keyfile-only unlock (password left empty).
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Keyfiles (optional)',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed:
                                        _pickingKeyfiles ? null : _pickKeyfiles,
                                    icon: _pickingKeyfiles
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            Icons.attach_file_rounded,
                                            size: AppIconSize.small,
                                          ),
                                    label: const Text('Add'),
                                  ),
                                ],
                              ),
                              if (_keyfiles.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: _keyfiles
                                        .map(
                                          (k) => InputChip(
                                            avatar: Icon(
                                              Icons.description_outlined,
                                              size: AppIconSize.small,
                                            ),
                                            label: Text(
                                              k.displayName,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            onDeleted: () => _removeKeyfile(k),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _pimCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'PIM  (leave blank for default)',
                                  prefixIcon: Icon(Icons.tune_rounded, size: AppIconSize.small),
                                ),
                              ),
                              const SizedBox(height: 12),

                              DropdownButtonFormField<int>(
                                initialValue: _cipherId,
                                decoration: InputDecoration(
                                  labelText: 'Encryption Algorithm',
                                  prefixIcon: Icon(Icons.lock_outline_rounded, size: AppIconSize.small),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 255, child: Text('Auto-detect')),
                                  DropdownMenuItem(value: 0, child: Text('AES')),
                                  DropdownMenuItem(value: 1, child: Text('Serpent')),
                                  DropdownMenuItem(value: 2, child: Text('Twofish')),
                                  DropdownMenuItem(value: 3, child: Text('AES-Twofish')),
                                  DropdownMenuItem(value: 4, child: Text('Serpent-AES')),
                                  DropdownMenuItem(value: 5, child: Text('Twofish-Serpent')),
                                  DropdownMenuItem(value: 6, child: Text('AES-Twofish-Serpent')),
                                  DropdownMenuItem(value: 7, child: Text('Serpent-Twofish-AES')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _cipherId = val);
                                },
                              ),
                              const SizedBox(height: 12),

                              DropdownButtonFormField<int>(
                                initialValue: _hashId,
                                decoration: InputDecoration(
                                  labelText: 'Hash Algorithm',
                                  prefixIcon: Icon(Icons.tag_rounded, size: AppIconSize.small),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 255, child: Text('Auto-detect')),
                                  DropdownMenuItem(value: 0, child: Text('SHA-512')),
                                  DropdownMenuItem(value: 1, child: Text('SHA-256')),
                                  DropdownMenuItem(value: 2, child: Text('Whirlpool')),
                                  DropdownMenuItem(value: 3, child: Text('Streebog')),
                                  DropdownMenuItem(value: 4, child: Text('BLAKE2s-256')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _hashId = val);
                                },
                              ),
                              if (widget.initialUri == null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _remember,
                                      onChanged: (val) =>
                                          setState(() => _remember = val ?? false),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    const SizedBox(width: 10),
                                    GestureDetector(
                                      onTap: () =>
                                          setState(() => _remember = !_remember),
                                      child: Text(
                                        'Remember container on dashboard',
                                        style: textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Include error directly in the Stack if it's shown during Password UI
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          InlineErrorBanner(_error!),
                        ],

                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _loading ? null : _unlock,
                          child: const Text('Unlock'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Unlocking...',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ]
          // ── Safety Fallback Error (If error occurs outside password UI) ──
          else if (_error != null) ...[
            const SizedBox(height: 14),
            InlineErrorBanner(_error!),
          ],
        ],
      ),
    );
  }
}