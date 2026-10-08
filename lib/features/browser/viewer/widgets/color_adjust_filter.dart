import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/viewer/models/viewer_adjustments.dart';

/// Loads and caches the viewer adjustment [ui.FragmentProgram] once.
class ViewerAdjustShader {
  ViewerAdjustShader._();

  static const String assetKey = 'shaders/viewer_adjust.frag';

  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loading;
  static bool _failed = false;

  /// The loaded program, or null while loading / if loading failed.
  static ui.FragmentProgram? get program => _program;

  /// True when the shader path can be used on this device: the program is
  /// loaded and the active renderer supports [ui.ImageFilter.shader]
  /// (Impeller only).
  static bool get isUsable =>
      _program != null && ui.ImageFilter.isShaderFilterSupported;

  /// Starts loading (idempotent). Completes with null on failure; the
  /// widgets then keep using the matrix fallback.
  static Future<ui.FragmentProgram?> ensureLoaded() {
    if (_program != null) return Future.value(_program);
    if (_failed) return Future.value(null);
    return _loading ??= () async {
      try {
        _program = await ui.FragmentProgram.fromAsset(assetKey);
      } catch (e, st) {
        _failed = true;
        debugPrint('ViewerAdjustShader: load failed, using matrix fallback: $e');
        if (kDebugMode) debugPrintStack(stackTrace: st);
      }
      return _program;
    }();
  }
}

/// Applies [adjustments] to [child] without touching the underlying pixels.
///
/// * Identity adjustments return [child] unchanged, so there is no extra
///   compositing layer by default.
/// * With Impeller, all five adjustments run in one fragment shader through
///   [ui.ImageFilter.shader].
/// * Otherwise (Skia, shader failed to load, still loading) it falls back to
///   a [ColorFilter.matrix] covering everything except gamma.
class ColorAdjustFilter extends StatefulWidget {
  const ColorAdjustFilter({
    super.key,
    required this.adjustments,
    required this.child,
  });

  final ViewerAdjustments adjustments;
  final Widget child;

  @override
  State<ColorAdjustFilter> createState() => _ColorAdjustFilterState();
}

class _ColorAdjustFilterState extends State<ColorAdjustFilter> {
  ui.FragmentShader? _shader;
  ui.ImageFilter? _filter;
  ViewerAdjustments? _builtFor;

  @override
  void initState() {
    super.initState();
    _requestProgramIfNeeded();
  }

  @override
  void didUpdateWidget(ColorAdjustFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adjustments.isIdentity && widget.adjustments.isNotIdentity) {
      _requestProgramIfNeeded();
    }
  }

  void _requestProgramIfNeeded() {
    if (widget.adjustments.isIdentity || ViewerAdjustShader.program != null) {
      return;
    }
    unawaited(
      ViewerAdjustShader.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  /// Builds a fresh shader + filter when the adjustments changed.
  ///
  /// A new [ui.FragmentShader] is created per change on purpose: the filter
  /// copies the uniforms when it is created, and [ui.ImageFilter] equality
  /// compares the shader instance, so mutating one shader and reusing it
  /// would compare equal and never repaint.
  ui.ImageFilter _filterFor(ViewerAdjustments a) {
    if (_filter != null && _builtFor == a) return _filter!;
    final program = ViewerAdjustShader.program!;
    final shader = program.fragmentShader()
      // floats 0 and 1 (uSize) are filled in by the engine.
      ..setFloat(2, a.brightness)
      ..setFloat(3, a.contrast)
      ..setFloat(4, a.saturation)
      ..setFloat(5, a.hueRadians)
      ..setFloat(6, a.gamma);
    final filter = ui.ImageFilter.shader(shader);
    // Dispose the previous shader only after this frame, so nothing in the
    // current frame can still be using it.
    final previous = _shader;
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
    _shader = shader;
    _filter = filter;
    _builtFor = a;
    return filter;
  }

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
    _filter = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.adjustments;
    if (a.isIdentity) return widget.child;

    if (ViewerAdjustShader.isUsable) {
      try {
        return ImageFiltered(
          imageFilter: _filterFor(a),
          child: widget.child,
        );
      } catch (e) {
        // Shader / filter creation can throw on unsupported backends.
        debugPrint('ColorAdjustFilter: shader path failed, falling back: $e');
      }
    }

    return ColorFiltered(
      colorFilter: ColorFilter.matrix(a.toColorMatrix()),
      child: widget.child,
    );
  }
}
