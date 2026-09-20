import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:vaultexplorer/core/api/quick_capture_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';

/// Settings for the Quick Capture entry point (Quick Settings tile +
/// pinned home screen shortcut -- see VaultQuickCaptureActivity,
/// CaptureTileService.kt, QuickCaptureShortcuts.kt). Mirrors
/// EmergencySettingsScreen's self-contained load/reload pattern rather
/// than folding into AppSettingsScreen's own larger state, since this
/// only ever needs its own small, independently-loadable snapshot.
class QuickCaptureSettingsScreen extends ConsumerStatefulWidget {
  const QuickCaptureSettingsScreen({super.key});

  @override
  ConsumerState<QuickCaptureSettingsScreen> createState() =>
      _QuickCaptureSettingsScreenState();
}

class _QuickCaptureSettingsScreenState
    extends ConsumerState<QuickCaptureSettingsScreen> {
  bool _loading = true;
  QuickCaptureSettingsSnapshot? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  QuickCaptureApi get _api => ref.read(quickCaptureApiProvider);

  Future<void> _load() async {
    final settings = await _api.getQuickCaptureSettings();
    if (mounted) {
      setState(() {
        _settings = settings;
        _loading = false;
      });
    }
  }

  Future<void> _setTileEnabled(bool enabled) async {
    final ok = await _api.setQuickCaptureTileEnabled(enabled);
    if (ok && mounted) await _load();
  }

  Future<void> _requestPinShortcut() async {
    final ok = await _api.requestPinQuickCaptureShortcut();
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: ok
          ? context.l10n.quickCaptureShortcutRequestedMessage
          : context.l10n.quickCaptureShortcutUnsupportedMessage,
      tone: ok ? AppBannerTone.success : AppBannerTone.warning,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tileEnabled = _settings?.tileEnabled ?? false;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.quickCaptureSettingsTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
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
                      horizontal: 16,
                      vertical: 12,
                    ),
                    children: [
                      SectionHeader(context.l10n.sectionQuickCapture),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            title: Text(
                              context.l10n.quickCaptureTileToggleTitle,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              context.l10n.quickCaptureTileToggleSubtitle,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            value: tileEnabled,
                            onChanged: _setTileEnabled,
                          ),
                          ListTile(
                            enabled: tileEnabled,
                            leading: Icon(
                              Icons.push_pin_rounded,
                              color: tileEnabled ? cs.primary : cs.onSurfaceVariant,
                            ),
                            title: Text(
                              context.l10n.quickCaptureAddShortcutTitle,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              context.l10n.quickCaptureAddShortcutSubtitle,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            onTap: _requestPinShortcut,
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
