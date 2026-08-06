import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';

class PlaylistTransitionTransformer extends StatelessWidget {
  final PageController pageController;
  final int index;
  final PlaylistTransitionEffect effect;
  final Axis scrollDirection;
  final Widget child;

  const PlaylistTransitionTransformer({
    super.key,
    required this.pageController,
    required this.index,
    required this.effect,
    this.scrollDirection = Axis.horizontal,
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

  Widget _buildFadeTransition(BuildContext context, double position, Widget child) {
    if (position.abs() >= 1.0) {
      return Visibility(
        visible: false,
        maintainState: true,
        child: child,
      );
    }
    final opacity = (1.0 - position.abs()).clamp(0.0, 1.0);
    final size = MediaQuery.sizeOf(context);
    final isVertical = scrollDirection == Axis.vertical;
    final offset = isVertical
        ? Offset(0, position * size.height)
        : Offset(position * size.width, 0);

    return Transform.translate(
      offset: offset,
      child: Opacity(
        opacity: opacity,
        child: child,
      ),
    );
  }

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
    final size = MediaQuery.sizeOf(context);
    final isVertical = scrollDirection == Axis.vertical;
    final offset = isVertical
        ? Offset(0, position * size.height * 0.4)
        : Offset(position * size.width * 0.4, 0);

    return Transform.translate(
      offset: offset,
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: child,
        ),
      ),
    );
  }

  Widget _buildDepthTransition(BuildContext context, double position, Widget child) {
    if (position.abs() >= 1.0) {
      return Visibility(
        visible: false,
        maintainState: true,
        child: child,
      );
    }
    final size = MediaQuery.sizeOf(context);
    final isVertical = scrollDirection == Axis.vertical;

    if (position > 0) {
      final scale = (1.0 - position * 0.25).clamp(0.75, 1.0);
      final opacity = (1.0 - position * 0.6).clamp(0.0, 1.0);
      final offset = isVertical
          ? Offset(0, position * size.height * 0.6)
          : Offset(position * size.width * 0.6, 0);

      return Transform.translate(
        offset: offset,
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: child,
          ),
        ),
      );
    } else {
      return child;
    }
  }

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
    final isVertical = scrollDirection == Axis.vertical;

    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.001);

    if (isVertical) {
      matrix.rotateX(-angle);
    } else {
      matrix.rotateY(angle);
    }

    final alignment = isVertical
        ? (position > 0 ? Alignment.bottomCenter : Alignment.topCenter)
        : (position > 0 ? Alignment.centerRight : Alignment.centerLeft);

    return Transform(
      transform: matrix,
      alignment: alignment,
      child: Opacity(
        opacity: opacity,
        child: child,
      ),
    );
  }

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
    final isVertical = scrollDirection == Axis.vertical;

    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0012);

    if (isVertical) {
      matrix.rotateX(-angle);
    } else {
      matrix.rotateY(angle);
    }

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