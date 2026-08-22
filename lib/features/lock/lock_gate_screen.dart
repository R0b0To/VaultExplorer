import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/app/main_shell.dart';

class LockGateScreen extends StatefulWidget {
  const LockGateScreen({super.key});

  @override
  State<LockGateScreen> createState() => _LockGateScreenState();
}

class _LockGateScreenState extends State<LockGateScreen> {
  static const _secure = AppSecureStorage.instance;
  static const _kFailedAttempts = 'lock_gate_failed_attempts_v1';
  static const _kLockedUntilMs = 'lock_gate_locked_until_ms_v1';

  AppSettings? _settings;
  bool _loading = true;
  final _pwCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;
  bool _checking = false;
  bool _isAuthenticating = false;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadPersistedLockoutState();
    final s = await AppSettingsService.loadSettings();

    // Re-apply screenshot policy when entering the lock gate
    await SecureScreenPolicy.apply(preference: s.blockScreenshots);

    if (!mounted) return;
    if (!s.useMasterPassword || s.masterPasswordHash == null) {
      _goToDashboard();
      return;
    }
    setState(() {
      _settings = s;
      _loading = false;
    });
    if (s.masterPasswordIsFingerprint) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        _tryBiometric();
      }
    }
  }

  Future<void> _loadPersistedLockoutState() async {
    try {
      final storedAttempts = await _secure.read(key: _kFailedAttempts);
      final storedUntilMs = await _secure.read(key: _kLockedUntilMs);
      _failedAttempts = int.tryParse(storedAttempts ?? '') ?? 0;
      if (storedUntilMs != null) {
        final ms = int.tryParse(storedUntilMs);
        if (ms != null) {
          _lockedUntil = DateTime.fromMillisecondsSinceEpoch(ms);
          if (_lockedUntil!.isBefore(DateTime.now())) {
            _lockedUntil = null;
            await _secure.delete(key: _kLockedUntilMs);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _tryBiometric() async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) {
        if (mounted) {
          setState(() => _error = context.l10n.biometricNotAvailable);
        }
        return;
      }
      final ok = await _localAuth.authenticate(
        localizedReason: context.l10n.unlockVaultExplorerReason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (ok && mounted) _goToDashboard();
    } on LocalAuthException catch (e) {
      final desc = e.description?.toLowerCase() ?? '';
      if (e.code.name.toLowerCase().contains('progress') || desc.contains('progress')) {
        return;
      }
      if (mounted) setState(() => _error = context.l10n.biometricErrorWithCode(e.code.name));
    } on PlatformException catch (e) {
      if (e.code == 'auth_in_progress' ||
          e.code == 'AuthenticationInProgress' ||
          (e.message?.contains('Authentication in progress') ?? false)) {
        return;
      }
      if (mounted) setState(() => _error = context.l10n.biometricErrorWithCode(e.message ?? ''));
    } finally {
      _isAuthenticating = false;
    }
  }

  Duration? _currentLockout() {
    if (_lockedUntil == null) return null;
    final remaining = _lockedUntil!.difference(DateTime.now());
    if (remaining.isNegative) {
      _lockedUntil = null;
      _secure.delete(key: _kLockedUntilMs).catchError((_) {});
      return null;
    }
    return remaining;
  }

  Future<void> _recordFailure() async {
    _failedAttempts++;
    if (_failedAttempts >= 5) {
      final excess = _failedAttempts - 4;
      final seconds = (30 * excess).clamp(30, 300);
      _lockedUntil = DateTime.now().add(Duration(seconds: seconds));
    }
    try {
      await _secure.write(
        key: _kFailedAttempts,
        value: _failedAttempts.toString(),
      );
      if (_lockedUntil != null) {
        await _secure.write(
          key: _kLockedUntilMs,
          value: _lockedUntil!.millisecondsSinceEpoch.toString(),
        );
      }
    } catch (_) {}
  }

  Future<void> _clearLockoutState() async {
    _failedAttempts = 0;
    _lockedUntil = null;
    try {
      await _secure.delete(key: _kFailedAttempts);
      await _secure.delete(key: _kLockedUntilMs);
    } catch (_) {}
  }

  Future<void> _checkPassword() async {
    final s = _settings;
    if (s == null) return;
    final lockout = _currentLockout();
    if (lockout != null) {
      setState(() {
        _error = context.l10n.tooManyFailedAttempts(lockout.inSeconds);
      });
      return;
    }
    final pw = _pwCtrl.text;
    if (pw.isEmpty) {
      setState(() => _error = context.l10n.enterMasterPasswordPrompt);
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final ok = await PasswordHasher.verify(
      candidate: pw,
      hash: s.masterPasswordHash,
      salt: s.masterPasswordSalt,
    );
    if (!mounted) return;
    if (ok) {
      await _clearLockoutState();
      if (s.needsHashUpgrade) {
        _upgradeMasterPasswordHashInBackground(s, pw);
      }
      _goToDashboard();
    } else {
      HapticFeedback.heavyImpact();
      await _recordFailure();
      if (!mounted) return;
      final newLockout = _currentLockout();
      setState(() {
        _checking = false;
        _error = newLockout != null
            ? context.l10n.incorrectPasswordLockedFor(newLockout.inSeconds, _failedAttempts)
            : context.l10n.incorrectPasswordAttempts(_failedAttempts);
      });
      _pwCtrl.clear();
    }
  }

  void _upgradeMasterPasswordHashInBackground(AppSettings s, String pw) {
    PasswordHasher.deriveHash(pw)
        .then((result) async {
          await AppSettingsService.saveMasterPassword(
            s,
            result.hash,
            result.salt,
          );
        })
        .catchError((_) {});
  }

  void _goToDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    final s = _settings!;
    final isLockedOut = _currentLockout() != null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    context.l10n.brandNameNoSpace,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.enterPasswordSubtitle,
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),
                  TextField(
                    controller: _pwCtrl,
                    obscureText: _obscure,
                    enabled: !isLockedOut && !_checking,
                    autofocus: !s.masterPasswordIsFingerprint,
                    autofillHints: null,
                    onSubmitted: (_) => _checkPassword(),
                    decoration: InputDecoration(
                      labelText: context.l10n.masterPasswordFieldLabelTitleCase,
                      prefixIcon: const Icon(Icons.key_rounded, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: textTheme.bodySmall?.copyWith(color: cs.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: (_checking || isLockedOut)
                        ? null
                        : _checkPassword,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: _checking
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                            ),
                          )
                        : Text(context.l10n.unlock),
                  ),
                  if (s.masterPasswordIsFingerprint) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: isLockedOut ? null : _tryBiometric,
                      icon: const Icon(Icons.fingerprint_rounded, size: 20),
                      label: Text(context.l10n.useBiometric),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}