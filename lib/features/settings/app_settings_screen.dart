import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/features/settings/about_screen.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
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
  DisguiseMode _disguiseMode = DisguiseMode.vault;
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
        title: context.l10n.enableFastStorageAccessTitle,
        message: context.l10n.enableFastStorageAccessMessage,
        confirmLabel: context.l10n.openSettings,
      );
      if (grant) {
        await api.requestAllFilesAccess();
      }
    } else {
      final revoke = await showAppConfirmDialog(
        context,
        title: context.l10n.disableStorageAccessTitle,
        message: context.l10n.disableStorageAccessMessage,
        confirmLabel: context.l10n.openSettings,
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
    final disguiseMode = await disguiseModeApi.getMode();

    if (mounted) {
      setState(() {
        _settings = s;
        _biometricAvailable = bioAvail;
        _hasAllStorageAccess = hasAccess;
        _disguiseMode = disguiseMode;
        _loading = false;
      });
    }
  }

  Future<void> _setDiscreteMode(bool enable) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: enable ? context.l10n.enableDiscreteModeTitle : context.l10n.disableDiscreteModeTitle,
      message: enable ? context.l10n.enableDiscreteModeMessage : context.l10n.disableDiscreteModeMessage,
      confirmLabel: enable ? context.l10n.enable : context.l10n.disable,
    );
    if (!confirmed || !mounted) return;

    final targetMode = enable ? DisguiseMode.decoy : DisguiseMode.vault;
    try {
      await disguiseModeApi.setMode(targetMode);
      if (!mounted) return;
      setState(() => _disguiseMode = targetMode);
      applyDisguiseModeTaskSwitcherLabel(targetMode, context.l10n);
      showAppSnackBar(
        context,
        message: enable
            ? context.l10n.discreteModeEnabledSnack
            : context.l10n.discreteModeDisabledSnack,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      SystemNavigator.pop();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: context.l10n.failedToChangeDiscreteMode,
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _persist() async {
    try {
      await AppSettingsService.saveSettings(_settings);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.failedToSaveSettings,
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
      setState(() => _pwError = context.l10n.passwordCannotBeEmpty);
      return;
    }
    if (pw.length < 4) {
      setState(() => _pwError = context.l10n.atLeast4CharsRequired);
      return;
    }
    if (pw != confirm) {
      setState(() => _pwError = context.l10n.passwordsDoNotMatch);
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
          message: context.l10n.masterPasswordSetSnack,
          tone: AppBannerTone.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pwError = context.l10n.failedToHashPassword;
          _saving = false;
        });
      }
    }
  }

  String _labelForAssociation(String value) {
    if (value == 'editor') return context.l10n.fileAssocInAppTextEditor;
    if (value == 'media') return context.l10n.fileAssocInAppMediaViewer;
    if (value.startsWith('package:')) return context.l10n.fileAssocAppPrefix(value.substring(8));
    return context.l10n.fileAssocExternalApp;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(context.l10n.appSettingsTitle,
            style: const TextStyle(fontWeight: FontWeight.bold)),
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
                      SectionHeader(context.l10n.sectionSecurityPrivacy),
                      SectionCard(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SwitchListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                title: Text(context.l10n.masterPasswordTitle,
                                    style: textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  _settings.useMasterPassword &&
                                          _settings.masterPasswordHash != null
                                      ? context.l10n.masterPasswordActiveSubtitle
                                      : context.l10n.masterPasswordInactiveSubtitle,
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
                                                    ? context.l10n.newPasswordLabel
                                                    : context.l10n.masterPasswordFieldLabel,
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
                                            labelText: context.l10n.confirmPasswordLabel,
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
                                                child: Text(context.l10n.cancel),
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
                                                            ? context.l10n.update
                                                            : context.l10n.setPassword,
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
                              title: Text(context.l10n.biometricUnlockTitle,
                                  style: textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                context.l10n.biometricUnlockSubtitle,
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
                                context.l10n.changeMasterPasswordTitle,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary,
                                ),
                              ),
                              subtitle: Text(
                                context.l10n.changeMasterPasswordSubtitle,
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
                            title: Text(context.l10n.autoLockContainersTitle,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              context.l10n.autoLockContainersSubtitle,
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
                            OptionPickerTile<int>(
                              label: context.l10n.autoLockTimeoutLabel,
                              value: _settings.autoLockMins,
                              options: [
                                SelectOption(value: 0, label: context.l10n.immediately),
                                SelectOption(value: 1, label: context.l10n.nMinutes(1)),
                                SelectOption(value: 2, label: context.l10n.nMinutes(2)),
                                SelectOption(value: 5, label: context.l10n.nMinutes(5)),
                                SelectOption(value: 10, label: context.l10n.nMinutes(10)),
                                SelectOption(value: 15, label: context.l10n.nMinutes(15)),
                                SelectOption(value: 30, label: context.l10n.nMinutes(30)),
                                SelectOption(value: 60, label: context.l10n.nMinutes(60)),
                              ],
                              onChanged: (v) {
                                setState(() => _settings.autoLockMins = v);
                                _persist();
                              },
                            ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(context.l10n.blockScreenshotsTitle,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              context.l10n.blockScreenshotsSubtitle,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            value: _settings.blockScreenshots,
                            onChanged: (v) async {
                              setState(() => _settings.blockScreenshots = v);
                              await SecureScreenPolicy.apply(preference: v);
                              await _persist();
                            },
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(context.l10n.discreteModeTitle,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              _disguiseMode == DisguiseMode.decoy
                                  ? context.l10n.discreteModeActiveSubtitle
                                  : context.l10n.discreteModeInactiveSubtitle,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            value: _disguiseMode == DisguiseMode.decoy,
                            onChanged: (v) => _setDiscreteMode(v),
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(context.l10n.cacheDerivedKeysTitle,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              context.l10n.cacheDerivedKeysSubtitle,
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
                      SectionHeader(context.l10n.sectionAppearanceInterface),
                      SectionCard(
                        children: [
                          OptionPickerTile<ThemeMode>(
                            label: context.l10n.appThemeLabel,
                            value: _settings.themeMode,
                            options: [
                              SelectOption(
                                  value: ThemeMode.system,
                                  label: context.l10n.systemDefault),
                              SelectOption(
                                  value: ThemeMode.light,
                                  label: context.l10n.lightTheme),
                              SelectOption(
                                  value: ThemeMode.dark, label: context.l10n.darkTheme),
                            ],
                            onChanged: (v) {
                              setState(() => _settings.themeMode = v);
                              appThemeModeNotifier.value = v;
                              _persist();
                            },
                          ),
                          OptionPickerTile<String>(
                            label: context.l10n.languageLabel,
                            value: _settings.languageCode ?? 'system',
                            options: [
                              SelectOption(value: 'system', label: context.l10n.systemDefault),
                              const SelectOption(value: 'en', label: 'English'),
                            ],
                            onChanged: (v) {
                              final code = v == 'system' ? null : v;
                              setState(() => _settings.languageCode = code);
                              appLocaleNotifier.value = code != null ? Locale(code) : null;
                              _persist();
                            },
                          ),
                          OptionPickerTile<ContainerSortMode>(
                            label: context.l10n.sortContainersByLabel,
                            value: _settings.containerSortMode,
                            options: ContainerSortMode.values.map((mode) {
                              return SelectOption(
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
                            title: Text(context.l10n.swapCardSwipeActionsTitle,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              context.l10n.swapCardSwipeActionsSubtitle,
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
                            title: Text(context.l10n.swipeGestureHintTitle,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              context.l10n.swipeGestureHintSubtitle,
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
                      SectionHeader(context.l10n.sectionVaultFileHandling),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(context.l10n.autoOpenOnUnlockTitle,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              _settings.autoOpenOnUnlock
                                  ? context.l10n.autoOpenOnUnlockActiveSubtitle
                                  : context.l10n.autoOpenOnUnlockInactiveSubtitle,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            value: _settings.autoOpenOnUnlock,
                            onChanged: (v) {
                              setState(() => _settings.autoOpenOnUnlock = v);
                              _persist();
                            },
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(context.l10n.enableJsHtmlTitle,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              _settings.htmlEnableJavaScript
                                  ? context.l10n.jsEnabledSubtitle
                                  : context.l10n.jsDisabledSubtitle,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            value: _settings.htmlEnableJavaScript,
                            onChanged: (v) {
                              setState(() => _settings.htmlEnableJavaScript = v);
                              _persist();
                            },
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(context.l10n.fastStorageAccessTitle,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              _hasAllStorageAccess
                                  ? context.l10n.fastStorageAccessGrantedSubtitle
                                  : context.l10n.fastStorageAccessNotGrantedSubtitle,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            value: _hasAllStorageAccess,
                            onChanged: (v) => _toggleStoragePermission(v),
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(context.l10n.androidFileProviderTitle,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              context.l10n.androidFileProviderSubtitle,
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
                          OptionPickerTile<ThumbnailCacheMode>(
                            label: context.l10n.thumbnailCachingDefaultLabel,
                            value: _settings.defaultThumbnailCacheMode,
                            options: ThumbnailCacheMode.values.map((mode) {
                              return SelectOption(
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
                          ThumbnailQualityTile(
                            label: context.l10n.thumbnailQualityDefaultLabel,
                            value: _settings.defaultThumbnailQuality,
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
                                  context.l10n.fileAssociationsHeader,
                                  style: textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (_settings.extensionPreferences.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                                  child: Text(
                                    context.l10n.noFileAssociationsYet,
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
                                    context.l10n.defaultActionsHeader,
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
                                      tooltip: context.l10n.removeAssociationTooltip,
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
                      SectionCard(
                        children: [
                          ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(
                              context.l10n.aboutAppTitle,
                              style: textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              context.l10n.versionInfoSubtitle(appVersion),
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