import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// A short message for the A-B repeat button, drawn over the video.
///
/// It is not a SnackBar on purpose. A snackbar sits at the bottom of the
/// screen, on top of the very button that was just pressed, and swallows taps
/// until it times out, so the next press (marking B, say) would have to wait.
/// This sits clear of the top and bottom bars and ignores pointer events
/// entirely, so nothing underneath is ever blocked.
class AbLoopToast extends StatelessWidget {
  const AbLoopToast({super.key, required this.data});

  /// The message to show; null shows nothing.
  final ValueListenable<String?> data;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.45),
        child: ValueListenableBuilder<String?>(
          valueListenable: data,
          builder: (context, toast, _) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: toast == null
                  ? const SizedBox.shrink()
                  : Container(
                      key: ValueKey(toast),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: cs.inverseSurface,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        toast,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onInverseSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}
