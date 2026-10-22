import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';

/// Presentation options a host hands to every directory viewport it builds.
///
/// These describe how the viewport should look, not which tab it is: the
/// workspace supplies identity, and the shell supplies chrome. Keeping them in
/// one value object stops them from growing into more constructor parameters
/// on the viewport itself.
@immutable
class BrowserViewportOptions {
  const BrowserViewportOptions({
    this.showBackButton = true,
    this.wrapAppBarTitle,
    this.onOpenStorageSwitcher,
    this.thumbnailCacheMode,
    this.thumbnailQuality,
  });

  /// Whether the toolbar may show a back affordance. Decoy mode hides it
  /// because there is no Dashboard route beneath it.
  final bool showBackButton;

  /// Lets decoy mode attach its hidden trigger to the toolbar title.
  final Widget Function(Widget title)? wrapAppBarTitle;
  final VoidCallback? onOpenStorageSwitcher;
  final ThumbnailCacheMode? thumbnailCacheMode;
  final ThumbnailQuality? thumbnailQuality;
}
