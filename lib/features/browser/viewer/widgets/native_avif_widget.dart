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
      final decoded = await vaultExplorerApi.decodeAvif(widget.avifBytes);
      if (decoded == null || decoded.frames.isEmpty) {
        if (mounted) setState(() { _error = 'Invalid AVIF image'; _isLoading = false; });
        return;
      }

      final width = decoded.width;
      final height = decoded.height;
      final rawFrames = decoded.frames;

      // 1. Convert frame 0 immediately so it paints right away
      final frame0Img = await _rgbaToUiImage(rawFrames[0].rgbaBytes, width, height);

      if (!mounted) return;

      // Paint frame 0 and hide spinner immediately
      setState(() {
        _currentFrame = frame0Img;
        _decodedFrames = [frame0Img];
        _durationsMs = [rawFrames[0].durationMs];
        _isLoading = false;
      });

      // 2. Convert remaining animation frames in background if multi-frame
      if (rawFrames.length > 1) {
        for (int i = 1; i < rawFrames.length; i++) {
          if (!mounted) break;
          final img = await _rgbaToUiImage(rawFrames[i].rgbaBytes, width, height);
          _decodedFrames!.add(img);
          _durationsMs!.add(rawFrames[i].durationMs);
        }

        if (mounted && _decodedFrames!.length > 1) {
          _scheduleNextFrame();
        }
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
        child: Text(
          _error ?? 'Failed to render AVIF',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
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