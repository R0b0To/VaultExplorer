import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vaultexplorer/main.dart';
import '../../models/thumbnail_cache_mode.dart';
import '../../services/app_settings_service.dart';
import '../../services/password_hasher.dart';
import '../../services/vaultexplorer_api.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  AppSettings _settings = AppSettings();
  bool _loading = true;
  bool _saving = false;

  bool _showPwFields = false;
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();
  bool _obscurePw = true;
  bool _obscureConfirm = true;
  String? _pwError;

  bool _biometricAvailable = false;
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await AppSettingsService.loadSettings();
    bool bioAvail = false;
    try {
      bioAvail =
          await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _settings = s;
        _biometricAvailable = bioAvail;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await AppSettingsService.saveSettings(_settings);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  void _toggleMasterPassword(bool enabled) {
    setState(() {
      _settings.useMasterPassword = enabled;
      if (!enabled) {
        AppSettingsService.clearMasterPassword(_settings);
        _settings.masterPasswordIsFingerprint = false;
        _showPwFields = false;
        _pwCtrl.clear();
        _pwConfirmCtrl.clear();
        _pwError = null;
      } else {
        _showPwFields = true;
      }
    });
  }

  /// Derives PBKDF2-SHA512 via [PasswordHasher] and persists hash to Android Keystore.
  Future<void> _confirmPassword() async {
    final pw = _pwCtrl.text;
    final confirm = _pwConfirmCtrl.text;
    if (pw.isEmpty) {
      setState(() => _pwError = 'Password cannot be empty');
      return;
    }
    if (pw.length < 4) {
      setState(() => _pwError = 'At least 4 characters required');
      return;
    }
    if (pw != confirm) {
      setState(() => _pwError = 'Passwords do not match');
      return;
    }

    setState(() {
      _saving = true;
      _pwError = null;
    });

    try {
      final (:hash, :salt) = await PasswordHasher.deriveHash(pw);
      if (!mounted) return;

      await AppSettingsService.saveMasterPassword(_settings, hash, salt);

      setState(() {
        _showPwFields = false;
        _pwCtrl.clear();
        _pwConfirmCtrl.clear();
        _saving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Master password set')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pwError = 'Failed to hash password — please try again';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Settings'),
        actions: [
          if (!_loading && !_showPwFields)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: cs.primary,
                      ),
                    )
                  : Text(
                      'Save',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : ListView(
              // FIX: standardized to the same page-padding pattern used by
              // vault_item_edit_screen.dart (bottom 32 clears Android
              // gesture-nav on 16/17 edge-to-edge; top 12 gives breathing
              // room under the AppBar). Previously this screen used a flat
              // EdgeInsets.all(16).
              padding: AppSpacing.pagePadding,
              children: [
                const SectionLabel('Security'),
                _Card(
                  cs: cs,
                  children: [
                    SettingsToggleRow(
                      icon: Icons.lock_person_rounded,
                      title: 'Master Password',
                      subtitle:
                          _settings.useMasterPassword &&
                              _settings.masterPasswordHash != null
                          ? 'Active — tap toggle to remove'
                          : 'Require a password to open the app',
                      value: _settings.useMasterPassword,
                      onChanged: _toggleMasterPassword,
                    ),

                    if (_settings.useMasterPassword && _showPwFields) ...[
                      const SizedBox(height: 14),
                      AutofillGroup(
                        child: Column(
                          children: [
                            TextField(
                              controller: _pwCtrl,
                              obscureText: _obscurePw,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                labelText: _settings.masterPasswordHash != null
                                    ? 'New password'
                                    : 'Master password',
                                prefixIcon: Icon(
                                  Icons.password_rounded,
                                  size: AppIconSize.small,
                                ),
                                suffixIcon: PasswordVisibilityToggle(
                                  obscured: _obscurePw,
                                  onToggle: () =>
                                      setState(() => _obscurePw = !_obscurePw),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _pwConfirmCtrl,
                              obscureText: _obscureConfirm,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                labelText: 'Confirm password',
                                prefixIcon: Icon(
                                  Icons.password_rounded,
                                  size: AppIconSize.small,
                                ),
                                suffixIcon: PasswordVisibilityToggle(
                                  obscured: _obscureConfirm,
                                  onToggle: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_pwError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _pwError!,
                          style: textTheme.bodySmall?.copyWith(color: cs.error),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(() {
                                      _showPwFields = false;
                                      _pwCtrl.clear();
                                      _pwConfirmCtrl.clear();
                                      _pwError = null;
                                      if (_settings.masterPasswordHash ==
                                          null) {
                                        _settings.useMasterPassword = false;
                                      }
                                    }),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving ? null : _confirmPassword,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 48),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _settings.masterPasswordHash != null
                                          ? 'Update'
                                          : 'Set Password',
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (_settings.useMasterPassword &&
                        _settings.masterPasswordHash != null &&
                        !_showPwFields) ...[
                      const Divider(height: 24),

                      if (_biometricAvailable)
                        SettingsToggleRow(
                          icon: Icons.fingerprint_rounded,
                          title: 'Biometric Unlock',
                          subtitle: 'Use fingerprint or face instead of typing',
                          value: _settings.masterPasswordIsFingerprint,
                          onChanged: (v) => setState(
                            () => _settings.masterPasswordIsFingerprint = v,
                          ),
                        ),
                      if (!_biometricAvailable)
                        Padding(
                          padding: const EdgeInsets.only(left: 32, top: 4),
                          child: Text(
                            'Biometric not available on this device',
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),

                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _showPwFields = true;
                          _pwError = null;
                        }),
                        icon: Icon(Icons.edit_rounded, size: AppIconSize.small),
                        label: const Text('Change password'),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 24),

                const SectionLabel('Privacy'),
                _Card(
                  cs: cs,
                  children: [
                    SettingsToggleRow(
                      icon: Icons.security_rounded,
                      title: 'Block Screenshots',
                      subtitle:
                          'Prevent screenshots and hide content in recent apps preview.',
                      value: _settings.blockScreenshots,
                      onChanged: (v) async {
                        setState(() => _settings.blockScreenshots = v);
                        await vaultExplorerApi.setSecureScreen(v);
                      },
                    ),
                    const Divider(height: 24),
                    SettingsToggleRow(
                      icon: Icons.key_rounded,
                      title: 'Cache derived keys by default',
                      subtitle:
                          'Reuse the last derived key in Android Keystore for faster unlocks across supported methods.',
                      value: _settings.defaultDerivedKeyCacheEnabled,
                      onChanged: (v) => setState(
                        () => _settings.defaultDerivedKeyCacheEnabled = v,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                const SectionLabel('Integration'),
                _Card(
                  cs: cs,
                  children: [
                    SettingsToggleRow(
                      icon: Icons.folder_shared_rounded,
                      title: 'Document Provider (default)',
                      subtitle:
                          'New containers will be exposed in Android\'s file '
                          'picker by default.',
                      value: _settings.defaultDocumentProvider,
                      onChanged: (v) =>
                          setState(() => _settings.defaultDocumentProvider = v),
                    ),
                    const Divider(height: 24),
                    DropdownButtonFormField<ThumbnailCacheMode>(
                      initialValue: _settings.defaultThumbnailCacheMode,
                      decoration: InputDecoration(
                        labelText: 'Thumbnail Caching (default)',
                        prefixIcon: Icon(Icons.cached_rounded, size: AppIconSize.small),
                      ),
                      items: ThumbnailCacheMode.values.map((mode) {
                        return DropdownMenuItem(
                          value: mode,
                          child: Text(mode.label),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(
                            () => _settings.defaultThumbnailCacheMode = v,
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        _settings.defaultThumbnailCacheMode.description,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                const SectionLabel('File Associations'),
                _Card(
                  cs: cs,
                  children: [
                    if (_settings.extensionPreferences.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No remembered file associations yet. You will be prompted when opening non-media files.',
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Default actions when tapping files in the browser:',
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const Divider(),
                      ..._settings.extensionPreferences.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer.withValues(
                                    alpha: 0.3,
                                  ),
                                  borderRadius: BorderRadius.circular(AppRadius.sm / 2),
                                ),
                                child: Text(
                                  '.${entry.key.toUpperCase()}',
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  entry.value == 'editor'
                                      ? 'In-app Text Editor'
                                      : (entry.value == 'media'
                                            ? 'In-app Media Viewer'
                                            : (entry.value.startsWith(
                                                    'package:',
                                                  )
                                                  ? 'App: ${entry.value.substring(8)}'
                                                  : 'External App')),
                                  style: textTheme.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: cs.error,
                                  size: AppIconSize.standard,
                                ),
                                tooltip: 'Remove association',
                                onPressed: () {
                                  setState(() {
                                    _settings.extensionPreferences.remove(
                                      entry.key,
                                    );
                                  });
                                  _save(); // Auto-save after removing
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),

                const SizedBox(height: 24),

                const SectionLabel('About'),
                _Card(
                  cs: cs,
                  children: [
                    _InfoRow('Version', appVersion, cs),
                    const Divider(),
                    _InfoRow('Encryption', 'AES-256-XTS (VeraCrypt)', cs),
                    const Divider(),
                    _InfoRow('Key derivation', 'PBKDF2-SHA512', cs),
                    const Divider(),
                    _InfoRow('Filesystem', 'FAT32 / exFAT via FatFs', cs),
                    const Divider(),
                    GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse('https://github.com/R0b0To/VaultExplorer'),
                      ),
                      child: _InfoRow(
                        'GitHub',
                        'https://github.com/R0b0To/VaultExplorer',
                        cs,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────
//
// _SectionLabel and _ToggleRow were removed from this file — they are now
// the shared SectionLabel / SettingsToggleRow widgets in
// lib/widgets/common_widgets.dart, previously duplicated verbatim here and
// in container_config_sheet.dart.

class _Card extends StatelessWidget {
  final List<Widget> children;
  final ColorScheme cs;
  const _Card({required this.children, required this.cs});

  @override
  Widget build(BuildContext context) => Card(
    color: cs.surfaceContainerLow,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  const _InfoRow(this.label, this.value, this.cs);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}