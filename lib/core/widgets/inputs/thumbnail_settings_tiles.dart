import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/inputs/option_picker_tile.dart';
import 'package:vaultexplorer/core/widgets/inputs/thumbnail_quality_picker.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';

/// The thumbnail cache-mode + quality controls, shared by every screen that
/// edits thumbnail settings (a vault's config sheet, the app-wide default in
/// App settings / File manager settings, and the Local Storage slot).
///
/// Purely presentational: it owns no state and talks to no provider, so each
/// host decides when and where a change is stored (the vault config sheet
/// keeps a draft until Save; the settings screens apply immediately).
///
/// When [useGlobalDefault] is non-null a "Use global default" switch is
/// shown first, and the two pickers are only shown while it is off. A null
/// [useGlobalDefault] means this scope has no parent to inherit from (the
/// default itself, or the Local Storage slot), so the pickers are always
/// shown.
class ThumbnailSettingsTiles extends StatelessWidget {
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final ValueChanged<ThumbnailCacheMode> onCacheModeChanged;
  final ValueChanged<ThumbnailQuality> onQualityChanged;
  final String cacheModeLabel;
  final String qualityLabel;

  /// Uses the "hidden folder" wording for the in-container option instead of
  /// naming an encrypted container. See
  /// [ThumbnailCacheMode.getLocalizedLabel].
  final bool isLocalStorage;

  final bool? useGlobalDefault;
  final ValueChanged<bool>? onUseGlobalDefaultChanged;

  const ThumbnailSettingsTiles({
    super.key,
    required this.cacheMode,
    required this.quality,
    required this.onCacheModeChanged,
    required this.onQualityChanged,
    required this.cacheModeLabel,
    required this.qualityLabel,
    this.isLocalStorage = false,
    this.useGlobalDefault,
    this.onUseGlobalDefaultChanged,
  }) : assert(
         useGlobalDefault == null || onUseGlobalDefaultChanged != null,
         'A "use global default" switch needs a change handler',
       );

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;
    final inherit = useGlobalDefault;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inherit != null)
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            value: inherit,
            onChanged: onUseGlobalDefaultChanged,
            title: Text(
              l10n.useGlobalDefaultSubtitle,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              l10n.thumbnailUseGlobalDefaultDesc,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            secondary: Icon(Icons.sync_alt_rounded, color: cs.primary),
          ),
        if (inherit != true) ...[
          OptionPickerTile<ThumbnailCacheMode>(
            label: cacheModeLabel,
            value: cacheMode,
            options: ThumbnailCacheMode.values.map((mode) {
              return SelectOption(
                value: mode,
                label: mode.getLocalizedLabel(
                  l10n,
                  isLocalStorage: isLocalStorage,
                ),
                subtitle: mode.getLocalizedDescription(
                  l10n,
                  isLocalStorage: isLocalStorage,
                ),
              );
            }).toList(),
            onChanged: onCacheModeChanged,
          ),
          ThumbnailQualityTile(
            label: qualityLabel,
            value: quality,
            onChanged: onQualityChanged,
          ),
        ],
      ],
    );
  }
}
