import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart'
    show AppBannerTone, InlineBanner;

/// The short-lived banner the audio and video editors flash near the top of
/// the screen (for example when a segment edit has no room). Showing a new
/// one replaces the current one; it removes itself after two seconds.
class EditorToast {
  OverlayEntry? _entry;
  Timer? _timer;

  void show(
    BuildContext context,
    String message, {
    AppBannerTone tone = AppBannerTone.info,
  }) {
    clear();
    final overlay = Overlay.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;
    _entry = OverlayEntry(
      builder: (_) => Positioned(
        top: top,
        left: 16,
        right: 16,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: InlineBanner(message, tone: tone),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(const Duration(seconds: 2), clear);
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}
