import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Media3's spherical surface, attached to the current native player.
/// The native view owns drags so the playlist and seek gestures cannot turn
/// the camera movement into navigation or a seek.
class AndroidSphericalVideoView extends StatefulWidget {
  const AndroidSphericalVideoView({
    super.key,
    required this.sensorEnabled,
    required this.onTap,
  });

  final bool sensorEnabled;
  final VoidCallback onTap;

  @override
  State<AndroidSphericalVideoView> createState() =>
      _AndroidSphericalVideoViewState();
}

class _AndroidSphericalVideoViewState extends State<AndroidSphericalVideoView> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant AndroidSphericalVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sensorEnabled != widget.sensorEnabled) _syncSensor();
  }

  void _onCreated(int viewId) {
    final channel = MethodChannel(
      'com.aeidolon.vaultexplorer/spherical_video/$viewId',
    );
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (mounted && call.method == 'tap') widget.onTap();
    });
    _syncSensor();
  }

  void _syncSensor() {
    final channel = _channel;
    if (channel == null) return;
    unawaited(
      channel
          .invokeMethod<void>('setSensorEnabled', {
            'enabled': widget.sensorEnabled,
          })
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AndroidView(
    viewType: 'com.aeidolon.vaultexplorer/spherical_video',
    onPlatformViewCreated: _onCreated,
    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
    },
  );
}
