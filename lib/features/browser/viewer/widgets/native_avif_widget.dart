import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

class NativeAvifWidget extends StatefulWidget {
  final Uint8List avifBytes;
  final BoxFit fit;

  const NativeAvifWidget({
    super.key,
    required this.avifBytes,
    this.fit = BoxFit.contain,
  });

  @override
  State<NativeAvifWidget> createState() => _NativeAvifWidgetState();
}

class _NativeAvifWidgetState extends State<NativeAvifWidget> {
  ui.Image? _currentFrame;
  List<ui.Image>? _decodedFrames;
  List<int>? _durationsMs;
  int _currentFrameIndex = 0;
  Timer? _animationTimer;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAndAnimate();
  }

  Future<void> _loadAndAnimate() async {
    try {
      final info = await vaultExplorerApi.getAvifInfo(widget.avifBytes);
      if (info == null || info.frameCount == 0) {
        if (mounted) setState(() { _error = 'Invalid AVIF image'; _isLoading = false; });
        return;
      }

      final width = info.width;
      final height = info.height;
      final count = info.frameCount;

      final frames = <ui.Image>[];
      final durations = <int>[];

      for (int i = 0; i < count; i++) {
        final frameData = await vaultExplorerApi.decodeAvifFrame(widget.avifBytes, i);
        if (frameData == null) break;

        final uiImg = await _rgbaToUiImage(frameData.rgbaBytes, width, height);
        frames.add(uiImg);
        durations.add(frameData.durationMs > 0 ? frameData.durationMs : 100);
      }

      if (frames.isEmpty) {
        if (mounted) setState(() { _error = 'Failed to decode AVIF'; _isLoading = false; });
        return;
      }

      if (!mounted) return;

      setState(() {
        _decodedFrames = frames;
        _durationsMs = durations;
        _currentFrame = frames[0];
        _isLoading = false;
      });

      if (frames.length > 1) {
        _scheduleNextFrame();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  void _scheduleNextFrame() {
    if (_decodedFrames == null || _decodedFrames!.length <= 1) return;
    final duration = Duration(milliseconds: _durationsMs![_currentFrameIndex]);
    _animationTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        _currentFrameIndex = (_currentFrameIndex + 1) % _decodedFrames!.length;
        _currentFrame = _decodedFrames![_currentFrameIndex];
      });
      _scheduleNextFrame();
    });
  }

  Future<ui.Image> _rgbaToUiImage(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );
    return completer.future;
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    if (_decodedFrames != null) {
      for (final img in _decodedFrames!) {
        img.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_error != null || _currentFrame == null) {
      return Center(
        child: Text(_error ?? 'Failed to render AVIF', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }
    return RawImage(
      image: _currentFrame,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
    );
  }
}