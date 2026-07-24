import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:vaultexplorer/features/settings/about_screen.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import '../../app/vault_explorer_app.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen>
    with WidgetsBindingObserver {
  AppSettings _settings = AppSettings();
  bool _loading = true;
  bool _saving = false;
  bool _hasAllStorageAccess = false;
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
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkStoragePermission();
    }
  }

  Future<void> _checkStoragePermission() async {
    const api = VaultExplorerApi();
    final hasAccess = await api.hasAllFilesAccess();
    if (mounted) {
      setState(() {
        _hasAllStorageAccess = hasAccess;
      });
    }
  }

  Future<void> _toggleStoragePermission(bool enable) async {
    const api = VaultExplorerApi();
    if (enable) {
      final grant = await showAppConfirmDialog(
        context,
        title: 'Enable Fast Storage Access',
        message:
            'Granting "All Files Access" allows Vault Explorer to perform direct POSIX file operations, speeding up folder vault performance by up to 1000x.',
        confirmLabel: 'Open Settings',
      );
      if (grant) {
        await api.requestAllFilesAccess();
      }
    } else {
      final revoke = await showAppConfirmDialog(
        context,
        title: 'Disable Storage Access',
        message:
            'Android requires "All Files Access" to be turned off inside System Settings. Would you like to open Settings to turn it off?',
        confirmLabel: 'Open Settings',
      );
      if (revoke) {
        await api.requestAllFilesAccess();
      }
    }
  }

  Future<void> _load() async {
    final s = await AppSettingsService.loadSettings();
    bool bioAvail = false;
    try {
      bioAvail =
          await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
    } catch (_) {}
    const api = VaultExplorerApi();
    final hasAccess = await api.hasAllFilesAccess();
    if (mounted) {
      setState(() {
        _settings = s;
        _biometricAvailable = bioAvail;
        _hasAllStorageAccess = hasAccess;
        _loading = false;
      });
    }
  }

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

  String _labelForAssociation(String value) {
    if (value == 'editor') return 'In-app Text Editor';
    if (value == 'media') return 'In-app Media Viewer';
    if (value.startsWith('package:')) return 'App: ${value.substring(8)}';
    return 'External App';
  }

  Widget _buildSectionGroup({required List<Widget> children}) {
    if (children.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(children.length, (index) {
        final isFirst = index == 0;
        final isLast = index == children.length - 1;
        final isOnly = children.length == 1;

        BorderRadius radius;
        if (isOnly) {
          radius = BorderRadius.circular(20);
        } else if (isFirst) {
          radius = const BorderRadius.vertical(
            top: Radius.circular(20),
            bottom: Radius.circular(4),
          );
        } else if (isLast) {
          radius = const BorderRadius.vertical(
            top: Radius.circular(4),
            bottom: Radius.circular(20),
          );
        } else {
          radius = BorderRadius.circular(4);
        }

        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 2.0),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: ListTileTheme(
              tileColor: Colors.transparent,
              child: children[index],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSectionHeader(String title) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Text(
        title,
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: cs.primary,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  Widget _buildSelectTile<T>({
    required String label,
    required T value,
    required List<_SelectOption<T>> options,
    required ValueChanged<T> onChanged,
    String? subtitle,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      title: Text(
        label,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle != null
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
            )
          : null,
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (dialogContext) {
            final dialogTheme = Theme.of(dialogContext);
            final mediaQuery = MediaQuery.of(dialogContext);
            final isLandscape =
                mediaQuery.orientation == Orientation.landscape;

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  maxHeight: isLandscape
                      ? mediaQuery.size.height * 0.85
                      : mediaQuery.size.height * 0.75,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          label,
                          style: dialogTheme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: options.map((opt) {
                              final isSelected = opt.value == value;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                child: RadioListTile<T>(
                                  activeColor: cs.primary,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 0,
                                  ),
                                  value: opt.value,
                                  groupValue: value,
                                  title: Text(
                                    opt.label,
                                    style: dialogTheme.textTheme.bodyMedium
                                        ?.copyWith(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isSelected ? cs.primary : null,
                                    ),
                                  ),
                                  subtitle: opt.subtitle != null
                                      ? Text(
                                          opt.subtitle!,
                                          style: dialogTheme
                                              .textTheme.bodySmall
                                              ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        )
                                      : null,
                                  onChanged: (T? newValue) {
                                    if (newValue != null) {
                                      Navigator.of(dialogContext).pop();
                                      onChanged(newValue);
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(

      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: const Text('App Settings',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    children: [
                      // ── Security & Privacy ──────────────────────────────────
                      _buildSectionHeader('Security & Privacy'),
                      _buildSectionGroup(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SwitchListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                title: Text('Master Password',
                                    style: textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  _settings.useMasterPassword &&
                                          _settings.masterPasswordHash != null
                                      ? 'Active — tap toggle to remove'
                                      : 'Require a password to open the app',
                                  style: textTheme.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                                value: _settings.useMasterPassword,
                                onChanged: _toggleMasterPassword,
                              ),
                              if (_settings.useMasterPassword && _showPwFields) ...[
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: AutofillGroup(
                                    child: Column(
                                      children: [
                                        TextField(
                                          controller: _pwCtrl,
                                          obscureText: _obscurePw,
                                          autofillHints: const [
                                            AutofillHints.newPassword
                                          ],
                                          decoration: InputDecoration(
                                            filled: true,
                                            fillColor: cs.surfaceContainerHighest,
                                            labelText:
                                                _settings.masterPasswordHash != null
                                                    ? 'New password'
                                                    : 'Master password',
                                            suffixIcon: PasswordVisibilityToggle(
                                              obscured: _obscurePw,
                                              onToggle: () => setState(
                                                  () => _obscurePw = !_obscurePw),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _pwConfirmCtrl,
                                          obscureText: _obscureConfirm,
                                          autofillHints: const [
                                            AutofillHints.newPassword
                                          ],
                                          decoration: InputDecoration(
                                            filled: true,
                                            fillColor: cs.surfaceContainerHighest,
                                            labelText: 'Confirm password',
                                            suffixIcon: PasswordVisibilityToggle(
                                              obscured: _obscureConfirm,
                                              onToggle: () => setState(() =>
                                                  _obscureConfirm = !_obscureConfirm),
                                            ),
                                          ),
                                        ),
                                        if (_pwError != null) ...[
                                          const SizedBox(height: 10),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              _pwError!,
                                              style: textTheme.bodySmall
                                                  ?.copyWith(color: cs.error),
                                            ),
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
                                                          if (_settings
                                                                  .masterPasswordHash ==
                                                              null) {
                                                            _settings
                                                                .useMasterPassword = false;
                                                          }
                                                        }),
                                                style: OutlinedButton.styleFrom(
                                                  minimumSize: const Size(0, 44),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(12),
                                                  ),
                                                ),
                                                child: const Text('Cancel'),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: FilledButton(
                                                onPressed:
                                                    _saving ? null : _confirmPassword,
                                                style: FilledButton.styleFrom(
                                                  minimumSize: const Size(0, 44),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(12),
                                                  ),
                                                ),
                                                child: _saving
                                                    ? const SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                      )
                                                    : Text(
                                                        _settings.masterPasswordHash !=
                                                                null
                                                            ? 'Update'
                                                            : 'Set Password',
                                                      ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (_settings.useMasterPassword &&
                              _settings.masterPasswordHash != null &&
                              !_showPwFields &&
                              _biometricAvailable)
                            SwitchListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              title: Text('Biometric Unlock',
                                  style: textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                'Use fingerprint or face recognition',
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              value: _settings.masterPasswordIsFingerprint,
                              onChanged: (v) {
                                setState(() =>
                                    _settings.masterPasswordIsFingerprint = v);
                                _persist();
                              },
                            ),
                          if (_settings.useMasterPassword &&
                              _settings.masterPasswordHash != null &&
                              !_showPwFields)
                            ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              title: Text(
                                'Change Master Password',
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary,
                                ),
                              ),
                              subtitle: Text(
                                'Update master password credentials',
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              trailing: Icon(Icons.chevron_right_rounded,
                                  color: cs.onSurfaceVariant),
                              onTap: () => setState(() {
                                _showPwFields = true;
                                _pwError = null;
                              }),
                            ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text('Auto-Lock Containers',
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'Automatically lock open vaults after inactivity',
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
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
                          if (_settings.lockContainersOnScreenLock)
                            _buildSelectTile<int>(
                              label: 'Auto-Lock Timeout',
                              subtitle: _settings.autoLockMins == 0
                                  ? 'Containers lock immediately on screen lock'
                                  : 'Locks after ${_settings.autoLockMins} minute${_settings.autoLockMins == 1 ? '' : 's'} of inactivity',
                              value: _settings.autoLockMins,
                              options: const [
                                _SelectOption(value: 0, label: 'Never'),
                                _SelectOption(value: 1, label: '1 minute'),
                                _SelectOption(value: 2, label: '2 minutes'),
                                _SelectOption(value: 5, label: '5 minutes'),
                                _SelectOption(value: 10, label: '10 minutes'),
                                _SelectOption(value: 15, label: '15 minutes'),
                                _SelectOption(value: 30, label: '30 minutes'),
                                _SelectOption(value: 60, label: '60 minutes'),
                              ],
                              onChanged: (v) {
                                setState(() => _settings.autoLockMins = v);
                                _persist();
                              },
                            ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text('Block Screenshots',
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'Prevent screenshots and hide recent apps preview',
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            value: _settings.blockScreenshots,
                            onChanged: (v) async {
                              setState(() => _settings.blockScreenshots = v);
                              await vaultExplorerApi.setSecureScreen(v);
                              await _persist();
                            },
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text('Cache Derived Keys by Default',
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'Store derived key material in Keystore for faster unlocks',
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            value: _settings.defaultDerivedKeyCacheEnabled,
                            onChanged: (v) {
                              setState(
                                  () => _settings.defaultDerivedKeyCacheEnabled = v);
                              _persist();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Appearance & Interface ──────────────────────────────
                      _buildSectionHeader('Appearance & Interface'),
                      _buildSectionGroup(
                        children: [
                          _buildSelectTile<ThemeMode>(
                            label: 'App Theme',
                            subtitle: _settings.themeMode == ThemeMode.system
                                ? 'App uses System Default theme'
                                : _settings.themeMode == ThemeMode.light
                                    ? 'App uses Light Theme'
                                    : 'App uses Dark Theme',
                            value: _settings.themeMode,
                            options: const [
                              _SelectOption(
                                  value: ThemeMode.system,
                                  label: 'System Default'),
                              _SelectOption(
                                  value: ThemeMode.light,
                                  label: 'Light Theme'),
                              _SelectOption(
                                  value: ThemeMode.dark, label: 'Dark Theme'),
                            ],
                            onChanged: (v) {
                              setState(() => _settings.themeMode = v);
                              appThemeModeNotifier.value = v;
                              _persist();
                            },
                          ),
                          _buildSelectTile<ContainerSortMode>(
                            label: 'Sort Containers By',
                            subtitle: _settings.containerSortMode ==
                                    ContainerSortMode.manual
                                ? 'Long-press and drag cards on dashboard to reorder'
                                : 'Containers are sorted by ${_settings.containerSortMode.label} automatically',
                            value: _settings.containerSortMode,
                            options: ContainerSortMode.values.map((mode) {
                              return _SelectOption(
                                value: mode,
                                label: mode.label,
                              );
                            }).toList(),
                            onChanged: (v) {
                              setState(() => _settings.containerSortMode = v);
                              _persist();
                            },
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text('Swap Card Swipe Actions',
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'Reveal Edit on left and Delete on right when swiping cards',
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            value: _settings.swapCardActions,
                            onChanged: (v) {
                              setState(() => _settings.swapCardActions = v);
                              _persist();
                            },
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text('Swipe Gesture Hint',
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'Show card peek animation on first container',
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            value: !_settings.hasSeenSwipeTutorial,
                            onChanged: (v) {
                              setState(() => _settings.hasSeenSwipeTutorial = !v);
                              _persist();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Vault & File Handling ──────────────────────────────
                      _buildSectionHeader('Vault & File Handling'),
                      _buildSectionGroup(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text('Fast Storage Access',
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              _hasAllStorageAccess
                                  ? 'All Files Access granted (maximum speed)'
                                  : 'Grant All Files Access in System Settings for optimal speed',
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            value: _hasAllStorageAccess,
                            onChanged: (v) => _toggleStoragePermission(v),
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text('Android File Provider (default)',
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'Expose new containers to Android File Picker by default',
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            value: _settings.defaultDocumentProvider,
                            onChanged: (v) {
                              setState(
                                  () => _settings.defaultDocumentProvider = v);
                              _persist();
                            },
                          ),
                          _buildSelectTile<ThumbnailCacheMode>(
                            label: 'Thumbnail Caching (default)',
                            subtitle:
                                _settings.defaultThumbnailCacheMode.description,
                            value: _settings.defaultThumbnailCacheMode,
                            options: ThumbnailCacheMode.values.map((mode) {
                              return _SelectOption(
                                value: mode,
                                label: mode.label,
                                subtitle: mode.description,
                              );
                            }).toList(),
                            onChanged: (v) {
                              setState(() =>
                                  _settings.defaultThumbnailCacheMode = v);
                              _persist();
                            },
                          ),
                          _buildSelectTile<ThumbnailQuality>(
                            label: 'Thumbnail Quality (default)',
                            subtitle:
                                'Thumbnails are generated with ${_settings.defaultThumbnailQuality.label.toLowerCase()} quality',
                            value: _settings.defaultThumbnailQuality,
                            options: ThumbnailQuality.values.map((q) {
                              return _SelectOption(
                                value: q,
                                label: q.label,
                              );
                            }).toList(),
                            onChanged: (v) {
                              setState(
                                  () => _settings.defaultThumbnailQuality = v);
                              _persist();
                            },
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(
                                  'File Associations',
                                  style: textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (_settings.extensionPreferences.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                                  child: Text(
                                    'No remembered file associations yet. You will be prompted when opening files.',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      height: 1.3,
                                    ),
                                  ),
                                )
                              else ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                                  child: Text(
                                    'Default actions when opening non-standard files:',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                ..._settings.extensionPreferences.entries.map((entry) {
                                  return ListTile(
                                    dense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 16),
                                    title: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color:
                                                cs.primaryContainer.withValues(alpha: 0.3),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '.${entry.key.toUpperCase()}',
                                            style: textTheme.labelMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: cs.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _labelForAssociation(entry.value),
                                            style: textTheme.bodyMedium,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: Icon(Icons.delete_outline_rounded,
                                          color: cs.error, size: 20),
                                      tooltip: 'Remove association',
                                      onPressed: () {
                                        setState(() => _settings.extensionPreferences
                                            .remove(entry.key));
                                        _persist();
                                      },
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── About Card ──────────────────────────────────────────
                      _buildSectionGroup(
                        children: [
                          ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(
                              'About VaultExplorer',
                              style: textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Version $appVersion · Open source licenses & details',
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AboutScreen()),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _SelectOption<T> {
  final T value;
  final String label;
  final String? subtitle;

  const _SelectOption({
    required this.value,
    required this.label,
    this.subtitle,
  });
}