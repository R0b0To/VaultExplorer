import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'gallery_layout.dart';

/// Feeds a [GalleryLayoutHost]'s pre-computed layout to a [SliverGrid].
///
/// Flutter asks for the layout on every scrolled frame, so this only forwards
/// to [GalleryLayoutHost.modelFor], which is O(1) unless something that moves
/// tiles changed.
class GallerySliverGridDelegate extends SliverGridDelegate {
  const GallerySliverGridDelegate(this.host, this.revision);

  final GalleryLayoutHost host;

  /// [GalleryLayoutHost.revision] when the widget was built: how
  /// [shouldRelayout] notices that the (mutable) host changed.
  final int revision;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    return _GalleryGridLayout(
      host.modelFor(constraints.crossAxisExtent),
      axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(covariant GallerySliverGridDelegate oldDelegate) {
    return !identical(oldDelegate.host, host) || oldDelegate.revision != revision;
  }
}

class _GalleryGridLayout extends SliverGridLayout {
  const _GalleryGridLayout(this.model, this.reverseCrossAxis);

  final GalleryLayoutModel model;
  final bool reverseCrossAxis;

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) =>
      model.minChildForOffset(scrollOffset);

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) =>
      model.maxChildForOffset(scrollOffset);

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    if (model.childCount == 0) {
      return const SliverGridGeometry(
        scrollOffset: 0,
        crossAxisOffset: 0,
        mainAxisExtent: 0,
        crossAxisExtent: 0,
      );
    }
    final c = math.max(0, math.min(model.childCount - 1, index));
    final left = model.lefts[c];
    final width = model.widths[c];
    return SliverGridGeometry(
      scrollOffset: model.tops[c],
      crossAxisOffset: reverseCrossAxis ? model.crossExtent - left - width : left,
      mainAxisExtent: model.heights[c],
      crossAxisExtent: width,
    );
  }

  @override
  double computeMaxScrollOffset(int childCount) => model.maxExtent;
}

/// One sliver for every section of a gallery (headers included), instead of a
/// `SliverGrid` per section.
///
/// A sliver per section does not scale: the viewport lays out every sliver on
/// every scrolled frame, and each `RenderSliverGrid` builds at least one child
/// even when it is far outside the viewport (flutter/flutter#49027), so a
/// folder with a few hundred days started a few hundred thumbnail loaders that
/// nobody could see. Here a single render object builds only the children that
/// intersect the viewport (plus the cache extent), wherever it jumps to.
///
/// On top of [SliverGrid] it adds one thing: when [GalleryLayoutHost.adopt] is
/// given an anchor (a ratio was learned, or the pinch changed the zoom), the
/// first layout pass with the new geometry asks the viewport to correct the
/// scroll offset so the anchored child stays where it was. The correction
/// happens inside the same layout pass, so no frame is ever painted with the
/// content shifted.
class GallerySliverGrid extends SliverGrid {
  GallerySliverGrid({super.key, required this.host, required super.delegate})
    : super(gridDelegate: GallerySliverGridDelegate(host, host.revision));

  final GalleryLayoutHost host;

  @override
  RenderSliverGrid createRenderObject(BuildContext context) {
    final element = context as SliverMultiBoxAdaptorElement;
    return _RenderGallerySliverGrid(
      childManager: element,
      gridDelegate: gridDelegate,
      host: host,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSliverGrid renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _RenderGallerySliverGrid).host = host;
  }
}

class _RenderGallerySliverGrid extends RenderSliverGrid {
  _RenderGallerySliverGrid({
    required super.childManager,
    required super.gridDelegate,
    required this.host,
  });

  GalleryLayoutHost host;

  @override
  void performLayout() {
    final constraints = this.constraints;
    host
      ..sliverScrollOffset = constraints.scrollOffset
      ..viewportExtent = constraints.viewportMainAxisExtent
      ..sliverCrossExtent = constraints.crossAxisExtent;

    final anchor = host.pendingAnchor;
    if (anchor != null) {
      host.pendingAnchor = null;
      final model = host.modelFor(constraints.crossAxisExtent);
      if (anchor.child >= 0 && anchor.child < model.childCount) {
        final desired = math.max(
          0.0,
          model.tops[anchor.child] - anchor.viewportOffset,
        );
        final delta = desired - constraints.scrollOffset;
        if (delta.abs() > 0.5) {
          geometry = SliverGeometry(scrollOffsetCorrection: delta);
          return;
        }
      }
    }
    super.performLayout();
  }
}
