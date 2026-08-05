import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';

/// A wrapper widget for [PageView] items that applies custom transition animations
/// based on the chosen [PlaylistTransitionEffect].
class PlaylistTransitionTransformer extends StatelessWidget {
  final PageController pageController;
  final int index;
  final PlaylistTransitionEffect effect;
  final Widget child;

  const PlaylistTransitionTransformer({
    super.key,
    required this.pageController,
    required this.index,
    required this.effect,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (effect == PlaylistTransitionEffect.slide) {
      return child;
    }

    return AnimatedBuilder(
      animation: pageController,
      builder: (context, child) {
        double position = 0.0;
        if (pageController.hasClients &&
            pageController.positions.length == 1 &&
            pageController.position.haveDimensions) {
          position = (pageController.page ?? pageController.initialPage.toDouble()) - index;
        }

        switch (effect) {
          case PlaylistTransitionEffect.slide:
            return child!;
          case PlaylistTransitionEffect.fade:
            return _buildFadeTransition(context, position, child!);
          case PlaylistTransitionEffect.zoom:
            return _buildZoomTransition(context, position, child!);
          case PlaylistTransitionEffect.depth:
            return _buildDepthTransition(context, position, child!);
          case PlaylistTransitionEffect.cube:
            return _buildCubeTransition(context, position, child!);
          case PlaylistTransitionEffect.flip:
            return _buildFlipTransition(context, position, child!);
        }
      },
      child: child,
    );
  }

  /// Fade transition: cross-fades page opacity while counter-translating position.
  Widget _buildFadeTransition(BuildContext context, double position, Widget child) {
    if (position.abs() >= 1.0) {
      return Visibility(
        visible: false,
        maintainState: true,
        child: child,
      );
    }
    final opacity = (1.0 - position.abs()).clamp(0.0, 1.0);
    final width = MediaQuery.sizeOf(context).width;
    return Transform.translate(
      offset: Offset(position * width, 0),
      child: Opacity(
        opacity: opacity,
        child: child,
      ),
    );
  }

  /// Zoom transition: scales down outgoing item while fading out.
  Widget _buildZoomTransition(BuildContext context, double position, Widget child) {
    if (position.abs() >= 1.0) {
      return Visibility(
        visible: false,
        maintainState: true,
        child: child,
      );
    }
    final opacity = (1.0 - position.abs()).clamp(0.0, 1.0);
    final scale = (1.0 - position.abs() * 0.35).clamp(0.65, 1.0);
    final width = MediaQuery.sizeOf(context).width;
    return Transform.translate(
      offset: Offset(position * width * 0.4, 0),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: child,
        ),
      ),
    );
  }

  /// Depth stack transition: outgoing item shrinks and recedes into background,
  /// while incoming item slides smoothly over top.
  Widget _buildDepthTransition(BuildContext context, double position, Widget child) {
    if (position.abs() >= 1.0) {
      return Visibility(
        visible: false,
        maintainState: true,
        child: child,
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    if (position > 0) {
      // Outgoing item (scrolling off to left)
      final scale = (1.0 - position * 0.25).clamp(0.75, 1.0);
      final opacity = (1.0 - position * 0.6).clamp(0.0, 1.0);
      return Transform.translate(
        offset: Offset(position * width * 0.6, 0),
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: child,
          ),
        ),
      );
    } else {
      // Incoming item (sliding in from right)
      return child;
    }
  }

  /// 3D perspective cube rotation around vertical axis.
  Widget _buildCubeTransition(BuildContext context, double position, Widget child) {
    if (position.abs() >= 1.0) {
      return Visibility(
        visible: false,
        maintainState: true,
        child: child,
      );
    }
    final angle = position * (math.pi / 2.2);
    final opacity = (1.0 - position.abs() * 0.4).clamp(0.0, 1.0);

    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateY(angle);

    return Transform(
      transform: matrix,
      alignment: position > 0 ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: opacity,
        child: child,
      ),
    );
  }

  /// 3D card flip animation around vertical axis.
  Widget _buildFlipTransition(BuildContext context, double position, Widget child) {
    if (position.abs() >= 0.99) {
      return Visibility(
        visible: false,
        maintainState: true,
        child: child,
      );
    }
    final angle = position * math.pi;
    if (angle.abs() > math.pi / 2) {
      return const SizedBox.shrink();
    }
    final opacity = (1.0 - position.abs() * 0.3).clamp(0.0, 1.0);

    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateY(angle);

    return Transform(
      transform: matrix,
      alignment: Alignment.center,
      child: Opacity(
        opacity: opacity,
        child: child,
      ),
    );
  }
}
