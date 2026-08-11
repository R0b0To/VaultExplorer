// File: lib/features/browser/viewer/native_media3_player_view.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';

/// Renders the native Media3 [PlayerView] inside an [AndroidView].
///
/// The [AndroidView] is always created when this widget is in the tree so
/// the native [PlayerView]'s SurfaceView is available for ExoPlayer to
/// render decoded frames into. Before the video size is known, the view
/// is wrapped in a 1×1 box (effectively invisible); once dimensions
/// arrive, it fills its parent.
class NativeMedia3PlayerView extends StatefulWidget {
  final NativeMedia3Controller media3Controller;

  const NativeMedia3PlayerView({
    super.key,
    required this.media3Controller,
  });

  @override
  State<NativeMedia3PlayerView> createState() => _NativeMedia3PlayerViewState();
}

class _NativeMedia3PlayerViewState extends State<NativeMedia3PlayerView> {
  /// The AndroidView is built once and kept alive across rebuilds so
  /// Flutter doesn't recreate the PlatformView (and its SurfaceView).
  late final Widget _androidView;

  @override
  void initState() {
    super.initState();
    _androidView = const AndroidView(
      viewType: 'com.aeidolon.vaultexplorer/native_player_view',
      creationParamsCodec: StandardMessageCodec(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NativeVideoValue>(
      valueListenable: widget.media3Controller,
      builder: (context, value, child) {
        if (widget.media3Controller.isDisposed) {
          return const SizedBox.shrink();
        }

        final bool sizeKnown =
            value.isInitialized && value.size.width > 0 && value.size.height > 0;

        if (!sizeKnown) {
          // Surface must exist but doesn't need to be visible yet.
          // Wrap in an Offstage-like tiny box that still lays out the
          // platform view (Offstage itself doesn't create the platform
          // view's surface).
          return SizedBox(
            width: 1,
            height: 1,
            child: _androidView,
          );
        }

        return _androidView;
      },
    );
  }
}
