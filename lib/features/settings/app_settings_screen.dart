import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:vaultexplorer/features/settings/about_screen.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/cards/expressive_card.dart';

import '../../app/vault_explorer_app.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

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

  Future<void> _persist() async {
    try {
      await AppSettingsService.saveSettings(_settings);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Failed to save settings',
          tone: AppBannerTone.error,
        );
      }
    }
  }

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
    if (!enabled) _persist();
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
        showAppSnackBar(
          context,
          message: 'Master password set',
          tone: AppBannerTone.success,
        );
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

    final inputDecorationTheme = InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : Theme(
              data: Theme.of(context).copyWith(
                inputDecorationTheme: inputDecorationTheme,
              ),
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  children: [
                    // ==================== CARD 1: SECURITY & PRIVACY ====================
                    ExpressiveCard(
                      children: [
                        const ExpressiveSectionHeader(
                          title: 'Security & Privacy',
                          subtitle: 'Master authentication, auto-lock & app masking',
                          icon: Icons.shield_rounded,
                        ),
                        SettingsToggleRow(
                          icon: Icons.lock_person_rounded,
                          title: 'Master Password',
                          subtitle: _settings.useMasterPassword &&
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
                                    prefixIcon: const Icon(
                                      Icons.password_rounded,
                                      size: 20,
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
                                    prefixIcon: const Icon(
                                      Icons.password_rounded,
                                      size: 20,
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
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
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
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _saving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
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
                          const Divider(height: 28),

                          if (_biometricAvailable)
                            SettingsToggleRow(
                              icon: Icons.fingerprint_rounded,
                              title: 'Biometric Unlock',
                              subtitle: 'Use fingerprint or face instead of typing',
                              value: _settings.masterPasswordIsFingerprint,
                              onChanged: (v) {
                                setState(() => _settings.masterPasswordIsFingerprint = v);
                                _persist();
                              },
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
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => setState(() {
                                _showPwFields = true;
                                _pwError = null;
                              }),
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              label: const Text('Change password'),
                            ),
                          ),
                        ],

                        const Divider(height: 28),

                        SettingsToggleRow(
                          icon: Icons.lock_clock_rounded,
                          title: 'Auto-Lock',
                          subtitle:
                              'Automatically lock open containers after inactivity.',
                          value: _settings.lockContainersOnScreenLock,
                          onChanged: (v) {
                            setState(() {
                              _settings.lockContainersOnScreenLock = v;
                              if (v && _settings.autoLockMins == 0) {
                                _settings.autoLockMins = 5;
                              } else if (!v) {
                                _settings.autoLockMins = 0;
                              }
                            });
                            _persist();
                          },
                        ),
                        if (_settings.lockContainersOnScreenLock) ...[
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int>(
                            initialValue: _settings.autoLockMins,
                            decoration: const InputDecoration(
                              labelText: 'Auto-Lock After Inactivity',
                              prefixIcon: Icon(Icons.timer_rounded, size: 20),
                            ),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('Never')),
                              DropdownMenuItem(value: 1, child: Text('1 minute')),
                              DropdownMenuItem(value: 2, child: Text('2 minutes')),
                              DropdownMenuItem(value: 5, child: Text('5 minutes')),
                              DropdownMenuItem(value: 10, child: Text('10 minutes')),
                              DropdownMenuItem(value: 15, child: Text('15 minutes')),
                              DropdownMenuItem(value: 30, child: Text('30 minutes')),
                              DropdownMenuItem(value: 60, child: Text('60 minutes')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _settings.autoLockMins = v);
                                _persist();
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              _settings.autoLockMins == 0
                                  ? 'Containers lock immediately when you lock the screen.'
                                  : 'Fires after ${_settings.autoLockMins} minute'
                                      '${_settings.autoLockMins == 1 ? '' : 's'} of inactivity.',
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                            ),
                          ),
                        ],

                        const Divider(height: 28),

                        SettingsToggleRow(
                          icon: Icons.security_rounded,
                          title: 'Block Screenshots',
                          subtitle: 'Prevent screenshots and hide content in recent apps preview.',
                          value: _settings.blockScreenshots,
                          onChanged: (v) async {
                            setState(() => _settings.blockScreenshots = v);
                            await vaultExplorerApi.setSecureScreen(v);
                            await _persist();
                          },
                        ),

                        const Divider(height: 28),

                        SettingsToggleRow(
                          icon: Icons.key_rounded,
                          title: 'Cache derived keys by default',
                          subtitle:
                              'Reuse the last derived key in Keystore for faster unlocks.',
                          value: _settings.defaultDerivedKeyCacheEnabled,
                          onChanged: (v) {
                            setState(() => _settings.defaultDerivedKeyCacheEnabled = v);
                            _persist();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ==================== CARD 2: APPEARANCE & INTERFACE ====================
                    ExpressiveCard(
                      children: [
                        const ExpressiveSectionHeader(
                          title: 'Appearance & Interface',
                          subtitle: 'Themes, container card sorting & gestures',
                          icon: Icons.palette_rounded,
                        ),
                        DropdownButtonFormField<ThemeMode>(
                          initialValue: _settings.themeMode,
                          decoration: const InputDecoration(
                            labelText: 'App Theme',
                            prefixIcon: Icon(Icons.palette_rounded, size: 20),
                          ),
                          items: const [
                            DropdownMenuItem(value: ThemeMode.system, child: Text('System Default')),
                            DropdownMenuItem(value: ThemeMode.light, child: Text('Light Theme')),
                            DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark Theme')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _settings.themeMode = v);
                              appThemeModeNotifier.value = v;
                              _persist();
                            }
                          },
                        ),

                        const Divider(height: 28),

                        DropdownButtonFormField<ContainerSortMode>(
                          initialValue: _settings.containerSortMode,
                          decoration: const InputDecoration(
                            labelText: 'Sort Container Cards By',
                            prefixIcon: Icon(Icons.sort_rounded, size: 20),
                          ),
                          items: ContainerSortMode.values.map((mode) {
                            return DropdownMenuItem(
                              value: mode,
                              child: Text(mode.label),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _settings.containerSortMode = v);
                              _persist();
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            _settings.containerSortMode == ContainerSortMode.manual
                                ? 'Long-press and drag a card to reorder it manually.'
                                : 'Cards are ordered automatically; drag-to-reorder is disabled while active.',
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ),

                        const Divider(height: 28),

                        SettingsToggleRow(
                          icon: Icons.swap_horiz_rounded,
                          title: 'Swap Edit/Delete Swipe Actions',
                          subtitle: 'Reveal Edit on the left and Delete on the right '
                              'when swiping a container card.',
                          value: _settings.swapCardActions,
                          onChanged: (v) {
                            setState(() => _settings.swapCardActions = v);
                            _persist();
                          },
                        ),

                        const Divider(height: 28),

                        SettingsToggleRow(
                          icon: Icons.gesture_rounded,
                          title: 'Swipe Tutorial Nudge',
                          subtitle:
                              'Play a quick nudge animation on the first card to teach swipe gestures.',
                          value: !_settings.hasSeenSwipeTutorial,
                          onChanged: (v) {
                            setState(() => _settings.hasSeenSwipeTutorial = !v);
                            _persist();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ==================== CARD 3: VAULT & FILE HANDLING ====================
                    ExpressiveCard(
                      children: [
                        const ExpressiveSectionHeader(
                          title: 'Vault & File Handling',
                          subtitle: 'Document provider, thumbnails & file defaults',
                          icon: Icons.folder_shared_rounded,
                        ),
                        SettingsToggleRow(
                          icon: Icons.folder_shared_rounded,
                          title: 'Document Provider (default)',
                          subtitle:
                              'New containers will be exposed in Android\'s file '
                              'picker by default.',
                          value: _settings.defaultDocumentProvider,
                          onChanged: (v) {
                            setState(() => _settings.defaultDocumentProvider = v);
                            _persist();
                          },
                        ),

                        const Divider(height: 28),

                        DropdownButtonFormField<ThumbnailCacheMode>(
                          initialValue: _settings.defaultThumbnailCacheMode,
                          decoration: const InputDecoration(
                            labelText: 'Thumbnail Caching (default)',
                            prefixIcon: Icon(Icons.cached_rounded, size: 20),
                          ),
                          items: ThumbnailCacheMode.values.map((mode) {
                            return DropdownMenuItem(
                              value: mode,
                              child: Text(mode.label),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _settings.defaultThumbnailCacheMode = v);
                              _persist();
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

                        const SizedBox(height: 14),

                        DropdownButtonFormField<ThumbnailQuality>(
                          initialValue: _settings.defaultThumbnailQuality,
                          decoration: const InputDecoration(
                            labelText: 'Thumbnail Quality (default)',
                            prefixIcon: Icon(Icons.high_quality_rounded, size: 20),
                          ),
                          items: ThumbnailQuality.values.map((q) {
                            return DropdownMenuItem(
                              value: q,
                              child: Text(q.label),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _settings.defaultThumbnailQuality = v);
                              _persist();
                            }
                          },
                        ),

                        const Divider(height: 28),

                        Text(
                          'File Associations',
                          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),

                        if (_settings.extensionPreferences.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
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
                                      size: 20,
                                    ),
                                    tooltip: 'Remove association',
                                    onPressed: () {
                                      setState(() => _settings.extensionPreferences.remove(entry.key));
                                      _persist();
                                    },
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ==================== CARD 4: ABOUT ====================
                    ExpressiveCard(
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AboutScreen()),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(Icons.info_outline_rounded, color: cs.primary, size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'About VaultExplorer',
                                          style: textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Version, open-source licenses & project details',
                                          style: textTheme.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHigh,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.chevron_right_rounded,
                                      color: cs.onSurfaceVariant,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}
