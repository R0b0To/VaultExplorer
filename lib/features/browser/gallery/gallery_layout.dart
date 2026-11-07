import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart geometry engine behind the gallery (masonry/mosaic) views.
///
/// Nothing in this file touches Flutter: it turns "N items with aspect ratios,
/// split into sections with optional headers" into the exact rectangle of every
/// child, so the sliver that consumes it ([GallerySliverGrid]) never has to
/// measure a child to learn where the next one goes. That is what keeps a jump
/// to the middle of a 40,000-item folder (the fast-scroll handle does exactly
/// that) down to a binary search, and what makes the scroll extent exact rather
/// than an estimate that changes while you drag.
///
/// The design follows mosaic view (one
/// pre-computed layout for every section, a single lazily-built sliver instead
/// of one grid per section, justified rows), written for this app's needs:
/// tiles carry a caption footer, ratios arrive late, and the same engine also
/// drives the column ("Pinterest") flow and the uniform grid.
///
/// **Child index space.** A section with a header contributes one header child
/// followed by its items; a section without one contributes only its items.
/// Item indices are *display* indices (the concatenation of every section's
/// items). [GalleryLayoutModel.itemOfChild] / [GalleryLayoutModel.childOfItem]
/// translate between the two.
enum GalleryFlow {
  /// Justified rows ("mosaic"): every tile in a row has the same height and a
  /// width proportional to its aspect ratio, so rows fill the full width and no
  /// image is cropped.
  rows,

  /// Fixed number of equal-width columns, each tile as tall as its ratio says,
  /// every tile going into the currently shortest column. With a constant
  /// ratio this is a plain uniform grid.
  columns,
}

/// A run of items under an optional header.
class GallerySection {
  const GallerySection({required this.itemCount, this.headerExtent = 0});

  final int itemCount;

  /// Height of the header child. Zero (or less) means "no header child".
  final double headerExtent;

  bool get hasHeader => headerExtent > 0;
}

/// Width/height of the media area of item [item]. Must be finite and > 0.
typedef GalleryRatioOf = double Function(int item);

/// Height of the caption footer drawn under item [item]'s media area when the
/// tile is [tileWidth] wide. Zero for a tile without a caption.
typedef GalleryFooterOf = double Function(int item, double tileWidth);

class GalleryLayoutSpec {
  const GalleryLayoutSpec({
    required this.crossExtent,
    required this.spacing,
    required this.flow,
    required this.columnCount,
    this.minTileWidth = 56.0,
    this.maxRowHeightFactor = 2.2,
    this.lastRowHeightFactor = 1.35,
    this.sectionGap = 0.0,
  }) : assert(columnCount > 0);

  /// Width available to the sliver.
  final double crossExtent;

  /// Gap between tiles, in both axes.
  final double spacing;
  final GalleryFlow flow;

  /// [GalleryFlow.columns]: the exact number of columns.
  /// [GalleryFlow.rows]: the zoom level; a row aims for the height a cell has
  /// in a [columnCount]-column grid, so switching layouts keeps the same scale.
  final int columnCount;

  /// [GalleryFlow.rows]: a row is closed rather than made so crowded that its
  /// narrowest tile drops below this width (the caption has to fit).
  final double minTileWidth;

  /// [GalleryFlow.rows]: a row that would be taller than the target by this
  /// factor keeps taking items instead (a lone portrait photo does not get a
  /// row of its own that is three screens tall).
  final double maxRowHeightFactor;

  /// [GalleryFlow.rows]: the last, incomplete row of a section is not stretched
  /// to the full width; it is capped at this multiple of the target height and
  /// left-aligned.
  final double lastRowHeightFactor;

  /// Space after the last tile of every section.
  final double sectionGap;

  double get targetExtent =>
      math.max(1.0, (crossExtent - (columnCount - 1) * spacing) / columnCount);
}

/// The result of laying out a gallery: one rectangle per child, plus the
/// queries a sliver needs.
///
/// Every array is indexed by child index. `tops` is non-decreasing in the child
/// index for every flow (rows are laid out top to bottom, and a column-flow
/// tile always goes into the shortest column, whose height never decreases);
/// `bottoms` are *not* monotonic in the column flow, which is why the
/// leading-edge query goes through [prefixMaxBottom].
class GalleryLayoutModel {
  GalleryLayoutModel._({
    required this.crossExtent,
    required this.childCount,
    required this.itemCount,
    required this.maxExtent,
    required this.tops,
    required this.heights,
    required this.lefts,
    required this.widths,
    required this.prefixMaxBottom,
    required this.itemOfChild,
    required this.sectionOfChild,
    required this.childOfItem,
    required this.sectionFirstChild,
  });

  /// An empty layout (no children).
  factory GalleryLayoutModel.empty(double crossExtent) => GalleryLayoutModel._(
    crossExtent: crossExtent,
    childCount: 0,
    itemCount: 0,
    maxExtent: 0,
    tops: Float64List(0),
    heights: Float64List(0),
    lefts: Float64List(0),
    widths: Float64List(0),
    prefixMaxBottom: Float64List(0),
    itemOfChild: Int32List(0),
    sectionOfChild: Int32List(0),
    childOfItem: Int32List(0),
    sectionFirstChild: Int32List(1),
  );

  final double crossExtent;
  final int childCount;
  final int itemCount;

  /// Total main-axis extent (exact).
  final double maxExtent;

  final Float64List tops;
  final Float64List heights;

  /// Offset from the *start* edge of the cross axis (left in LTR).
  final Float64List lefts;
  final Float64List widths;

  /// `prefixMaxBottom[c]` = the largest bottom edge among children `0..c`.
  final Float64List prefixMaxBottom;

  /// Display index of the item at child `c`, or -1 for a header.
  final Int32List itemOfChild;
  final Int32List sectionOfChild;

  /// Child index of display item `i`.
  final Int32List childOfItem;

  /// `sectionFirstChild[s]` = first child of section `s`; has one extra entry
  /// (== [childCount]).
  final Int32List sectionFirstChild;

  bool isHeader(int child) => itemOfChild[child] < 0;

  double bottomOf(int child) => tops[child] + heights[child];

  /// Smallest child whose bottom edge is below [offset] (i.e. not yet scrolled
  /// past), clamped to a valid index.
  int minChildForOffset(double offset) {
    if (childCount == 0) return 0;
    var lo = 0;
    var hi = childCount;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (prefixMaxBottom[mid] > offset) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo >= childCount ? childCount - 1 : lo;
  }

  /// Largest child whose top edge is above [offset], clamped to a valid index.
  int maxChildForOffset(double offset) {
    if (childCount == 0) return 0;
    var lo = 0;
    var hi = childCount;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (tops[mid] >= offset) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return math.max(0, math.min(childCount - 1, lo - 1));
  }

  /// First index in `0..childCount` at which this layout and [other] differ,
  /// or `childCount` if they are identical. Requires the same child count;
  /// otherwise everything counts as changed (0).
  int firstChangedChild(GalleryLayoutModel other) {
    if (other.childCount != childCount) return 0;
    const eps = 0.01;
    for (var c = 0; c < childCount; c++) {
      if ((tops[c] - other.tops[c]).abs() > eps ||
          (heights[c] - other.heights[c]).abs() > eps ||
          (lefts[c] - other.lefts[c]).abs() > eps ||
          (widths[c] - other.widths[c]).abs() > eps) {
        return c;
      }
    }
    return childCount;
  }

  /// Computes the layout.
  ///
  /// O(items); the only per-item work is [ratioOf] and [footerOf]. Both should
  /// be array reads -- this runs again whenever a ratio is learned or the zoom
  /// changes.
  static GalleryLayoutModel compute({
    required List<GallerySection> sections,
    required GalleryLayoutSpec spec,
    required GalleryRatioOf ratioOf,
    GalleryFooterOf? footerOf,
  }) => _compute(
    sections: sections,
    spec: spec,
    ratioOf: ratioOf,
    footerOf: footerOf,
    previous: null,
    fromChild: 0,
  );

  /// Recomputes the layout from child [fromChild] on, keeping every child
  /// before it *exactly* where [previous] had it.
  ///
  /// This is what lets the gallery apply a freshly learned size while the user
  /// is flinging through it: nothing at or above the top of the screen moves
  /// (so the scroll offset needs no correction, which a fling would overwrite
  /// anyway), and everything on screen is up to date at once. Tiles above the
  /// screen are merely out of date until [GalleryLayoutHost.reflow] is allowed
  /// to recompute everything.
  ///
  /// [previous] must come from the same [sections] and the same spec (only the
  /// ratios and footers may differ), otherwise this is a full [compute]. In the
  /// rows flow [fromChild] is moved back to the start of its row.
  static GalleryLayoutModel recomputeFrom({
    required GalleryLayoutModel previous,
    required int fromChild,
    required List<GallerySection> sections,
    required GalleryLayoutSpec spec,
    required GalleryRatioOf ratioOf,
    GalleryFooterOf? footerOf,
  }) {
    if (fromChild <= 0 ||
        fromChild >= previous.childCount ||
        previous.crossExtent != spec.crossExtent) {
      return compute(
        sections: sections,
        spec: spec,
        ratioOf: ratioOf,
        footerOf: footerOf,
      );
    }
    final from = spec.flow == GalleryFlow.rows
        ? previous.firstChildOfRowContaining(fromChild)
        : fromChild;
    return _compute(
      sections: sections,
      spec: spec,
      ratioOf: ratioOf,
      footerOf: footerOf,
      previous: previous,
      fromChild: from,
    );
  }

  /// First child of the row [child] is in (rows flow): the first child with the
  /// same top. Headers are rows of their own.
  int firstChildOfRowContaining(int child) {
    final top = tops[child];
    var lo = 0;
    var hi = child;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (tops[mid] >= top) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  static GalleryLayoutModel _compute({
    required List<GallerySection> sections,
    required GalleryLayoutSpec spec,
    required GalleryRatioOf ratioOf,
    required GalleryFooterOf? footerOf,
    required GalleryLayoutModel? previous,
    required int fromChild,
  }) {
    var itemCount = 0;
    var headerCount = 0;
    for (final s in sections) {
      itemCount += s.itemCount;
      if (s.hasHeader) headerCount++;
    }
    final childCount = itemCount + headerCount;
    if (childCount == 0) return GalleryLayoutModel.empty(spec.crossExtent);
    if (previous != null && previous.childCount != childCount) {
      // Not the same sections after all: nothing to keep.
      return _compute(
        sections: sections,
        spec: spec,
        ratioOf: ratioOf,
        footerOf: footerOf,
        previous: null,
        fromChild: 0,
      );
    }

    final tops = Float64List(childCount);
    final heights = Float64List(childCount);
    final lefts = Float64List(childCount);
    final widths = Float64List(childCount);
    final itemOfChild = Int32List(childCount);
    final sectionOfChild = Int32List(childCount);
    final childOfItem = Int32List(itemCount);
    final sectionFirstChild = Int32List(sections.length + 1);

    void keepFromPrevious(int start, int end) {
      if (previous == null || end <= start) return;
      tops.setRange(start, end, previous.tops, start);
      heights.setRange(start, end, previous.heights, start);
      lefts.setRange(start, end, previous.lefts, start);
      widths.setRange(start, end, previous.widths, start);
    }

    final w = spec.crossExtent;
    var cursor = 0.0;
    var child = 0;
    var item = 0;

    for (var si = 0; si < sections.length; si++) {
      final section = sections[si];
      sectionFirstChild[si] = child;
      final sectionChildCount =
          (section.hasHeader ? 1 : 0) + section.itemCount;
      if (sectionChildCount == 0) continue;
      final sectionEndChild = child + sectionChildCount;

      // Index maps do not depend on geometry.
      var c = child;
      if (section.hasHeader) {
        itemOfChild[c] = -1;
        sectionOfChild[c] = si;
        c++;
      }
      final firstItemChild = c;
      for (var k = 0; k < section.itemCount; k++) {
        itemOfChild[firstItemChild + k] = item + k;
        sectionOfChild[firstItemChild + k] = si;
        childOfItem[item + k] = firstItemChild + k;
      }

      if (previous != null && sectionEndChild <= fromChild) {
        // The whole section is in the frozen prefix.
        keepFromPrevious(child, sectionEndChild);
        cursor = previous.prefixMaxBottom[sectionEndChild - 1] + spec.sectionGap;
        child = sectionEndChild;
        item += section.itemCount;
        continue;
      }

      if (section.hasHeader) {
        if (previous != null && fromChild > child) {
          keepFromPrevious(child, child + 1);
          cursor = tops[child] + heights[child];
        } else {
          tops[child] = cursor;
          heights[child] = section.headerExtent;
          lefts[child] = 0;
          widths[child] = w;
          cursor += section.headerExtent;
        }
      }

      if (section.itemCount > 0) {
        // Resume in the middle of the section when the frozen prefix ends in it.
        final resume =
            previous != null &&
            fromChild > firstItemChild &&
            fromChild < sectionEndChild;
        final skipped = resume ? fromChild - firstItemChild : 0;
        if (resume) keepFromPrevious(firstItemChild, fromChild);
        final sectionEnd = switch (spec.flow) {
          GalleryFlow.rows => _layoutRows(
            spec: spec,
            firstItem: item + skipped,
            itemCount: section.itemCount - skipped,
            firstChild: firstItemChild + skipped,
            startOffset: resume ? previous.tops[fromChild] : cursor,
            ratioOf: ratioOf,
            footerOf: footerOf,
            tops: tops,
            heights: heights,
            lefts: lefts,
            widths: widths,
          ),
          GalleryFlow.columns => _layoutColumns(
            spec: spec,
            firstItem: item + skipped,
            itemCount: section.itemCount - skipped,
            firstChild: firstItemChild + skipped,
            startOffset: cursor,
            initialBottoms: resume
                ? _columnBottomsOfPrefix(
                    spec: spec,
                    sectionStart: cursor,
                    firstChild: firstItemChild,
                    endChild: fromChild,
                    tops: tops,
                    heights: heights,
                    lefts: lefts,
                  )
                : null,
            ratioOf: ratioOf,
            footerOf: footerOf,
            tops: tops,
            heights: heights,
            lefts: lefts,
            widths: widths,
          ),
        };
        cursor = sectionEnd;
      }
      child = sectionEndChild;
      item += section.itemCount;
      cursor += spec.sectionGap;
    }
    sectionFirstChild[sections.length] = childCount;

    final prefixMaxBottom = Float64List(childCount);
    var running = 0.0;
    for (var c = 0; c < childCount; c++) {
      running = math.max(running, tops[c] + heights[c]);
      prefixMaxBottom[c] = running;
    }

    return GalleryLayoutModel._(
      crossExtent: w,
      childCount: childCount,
      itemCount: itemCount,
      // Not `cursor`: that includes the trailing section gap, and a sliver that
      // has reached its end reports the bottom of its last child instead, so
      // the two would disagree by the gap.
      maxExtent: running,
      tops: tops,
      heights: heights,
      lefts: lefts,
      widths: widths,
      prefixMaxBottom: prefixMaxBottom,
      itemOfChild: itemOfChild,
      sectionOfChild: sectionOfChild,
      childOfItem: childOfItem,
      sectionFirstChild: sectionFirstChild,
    );
  }

  /// Column bottoms after the tiles `firstChild..endChild` of a section, read
  /// from their (already copied) geometry.
  static Float64List _columnBottomsOfPrefix({
    required GalleryLayoutSpec spec,
    required double sectionStart,
    required int firstChild,
    required int endChild,
    required Float64List tops,
    required Float64List heights,
    required Float64List lefts,
  }) {
    final cols = spec.columnCount;
    final bottoms = Float64List(cols)..fillRange(0, cols, sectionStart);
    final stride = spec.targetExtent + spec.spacing;
    for (var c = firstChild; c < endChild; c++) {
      final column = math.max(0, math.min(cols - 1, (lefts[c] / stride).round()));
      final bottom = tops[c] + heights[c] + spec.spacing;
      if (bottom > bottoms[column]) bottoms[column] = bottom;
    }
    return bottoms;
  }

  /// Justified rows for one section. Returns the section's end offset (the
  /// bottom edge of its last row, without trailing spacing).
  static double _layoutRows({
    required GalleryLayoutSpec spec,
    required int firstItem,
    required int itemCount,
    required int firstChild,
    required double startOffset,
    required GalleryRatioOf ratioOf,
    required GalleryFooterOf? footerOf,
    required Float64List tops,
    required Float64List heights,
    required Float64List lefts,
    required Float64List widths,
  }) {
    final w = spec.crossExtent;
    final s = spec.spacing;
    final target = spec.targetExtent;
    final maxH = target * spec.maxRowHeightFactor;
    final minW = math.min(spec.minTileWidth, target);

    var cursor = startOffset;
    var rowFirst = 0; // section-local index of the row's first item
    var n = 0;
    var ratioSum = 0.0;
    var minRatio = double.infinity;

    void closeRow({required bool last}) {
      if (n == 0) return;
      final avail = w - (n - 1) * s;
      final natural = avail / ratioSum;
      final capped = last && natural > target * spec.lastRowHeightFactor;
      final h = capped ? target * spec.lastRowHeightFactor : natural;
      final stretch = !capped;

      // The row's caption slot is as tall as its tallest caption, so tiles
      // line up; a tile that needs none just gets a taller picture.
      var footer = 0.0;
      if (footerOf != null) {
        for (var k = 0; k < n; k++) {
          final i = firstItem + rowFirst + k;
          final tileW = h * ratioOf(i);
          footer = math.max(footer, footerOf(i, tileW));
        }
      }
      final rowH = h + footer;

      var left = 0.0;
      for (var k = 0; k < n; k++) {
        final i = firstItem + rowFirst + k;
        final c = firstChild + rowFirst + k;
        var tileW = h * ratioOf(i);
        // Absorb floating-point drift so a justified row ends exactly on the
        // edge instead of 1e-13 px past it.
        if (stretch && k == n - 1) tileW = w - left;
        tops[c] = cursor;
        heights[c] = rowH;
        lefts[c] = left;
        widths[c] = tileW;
        left += tileW + s;
      }
      cursor += rowH + s;
      rowFirst += n;
      n = 0;
      ratioSum = 0;
      minRatio = double.infinity;
    }

    for (var k = 0; k < itemCount; k++) {
      final r = ratioOf(firstItem + k);
      if (n > 0) {
        final nextN = n + 1;
        final nextSum = ratioSum + r;
        final nextAvail = w - (nextN - 1) * s;
        final nextH = nextAvail / nextSum;
        final nextMinW = nextH * math.min(minRatio, r);
        final currentH = (w - (n - 1) * s) / ratioSum;
        // A row that is still too tall has to keep taking items, whatever
        // they look like.
        if (currentH <= maxH) {
          if (nextMinW < minW) {
            closeRow(last: false);
          } else if (nextH < target) {
            // Adding the item would make the row shorter than the target:
            // take whichever of the two heights is closer to it.
            if (currentH - target < target - nextH) closeRow(last: false);
          }
        }
      }
      n++;
      ratioSum += r;
      minRatio = math.min(minRatio, r);
    }
    closeRow(last: true);
    return cursor - s;
  }

  /// Shortest-column-first placement for one section. Returns the section's end
  /// offset (the bottom of its tallest column, without trailing spacing).
  static double _layoutColumns({
    required GalleryLayoutSpec spec,
    required int firstItem,
    required int itemCount,
    required int firstChild,
    required double startOffset,
    Float64List? initialBottoms,
    required GalleryRatioOf ratioOf,
    required GalleryFooterOf? footerOf,
    required Float64List tops,
    required Float64List heights,
    required Float64List lefts,
    required Float64List widths,
  }) {
    final cols = spec.columnCount;
    final s = spec.spacing;
    final tileW = spec.targetExtent;
    final colBottom =
        initialBottoms ?? (Float64List(cols)..fillRange(0, cols, startOffset));

    for (var k = 0; k < itemCount; k++) {
      final i = firstItem + k;
      var column = 0;
      var shortest = colBottom[0];
      for (var c = 1; c < cols; c++) {
        if (colBottom[c] < shortest) {
          shortest = colBottom[c];
          column = c;
        }
      }
      var h = tileW / ratioOf(i) + (footerOf?.call(i, tileW) ?? 0.0);
      if (!h.isFinite || h < 0) h = 0;
      final c = firstChild + k;
      tops[c] = shortest;
      heights[c] = h;
      lefts[c] = column * (tileW + s);
      widths[c] = tileW;
      colBottom[column] = shortest + h + s;
    }
    var tallest = startOffset;
    for (final b in colBottom) {
      if (b > tallest) tallest = b;
    }
    return tallest - s;
  }
}

/// What [GalleryLayoutHost.reflow] did.
enum GalleryReflowResult {
  /// The recomputed layout is identical; nothing to rebuild.
  unchanged,

  /// The new layout was adopted; the view must rebuild.
  applied,
}

/// Keeps one child at the same place on screen across a relayout.
class GalleryAnchor {
  const GalleryAnchor({required this.child, required this.viewportOffset});

  /// Child index (stable across ratio and zoom changes: the child index space
  /// only depends on the sections).
  final int child;

  /// Where the child's top edge was relative to the sliver's scroll offset.
  final double viewportOffset;
}

/// Owns the inputs of a gallery layout and caches the model computed from
/// them, so the sliver can ask for it on every layout pass for free.
///
/// Flutter calls `SliverGridDelegate.getLayout` on *every* scrolled frame, so
/// [modelFor] must be O(1) unless something that moves tiles has changed:
/// that is what [invalidate] and the crossExtent comparison are for.
class GalleryLayoutHost {
  GalleryLayoutHost({
    this.flow = GalleryFlow.rows,
    this.columnCount = 3,
    this.spacing = 8.0,
    this.sectionGap = 0.0,
    this.minTileWidth = 56.0,
  });

  GalleryFlow flow;
  int columnCount;
  double spacing;
  double sectionGap;
  double minTileWidth;

  List<GallerySection> sections = const [];
  GalleryRatioOf ratioOf = _unitRatio;
  GalleryFooterOf? footerOf;

  /// Bumped whenever the model changes; widgets pass it to the delegate so
  /// `shouldRelayout` can tell.
  int revision = 0;

  /// Set when the next layout pass should keep this child where it is; consumed
  /// (cleared) by the sliver.
  GalleryAnchor? pendingAnchor;

  /// Written by the sliver on every layout pass (sliver coordinates).
  double sliverScrollOffset = 0;
  double viewportExtent = 0;
  double sliverCrossExtent = 0;

  GalleryLayoutModel? _model;
  bool _dirty = true;

  static double _unitRatio(int _) => 1.0;

  /// The model most recently adopted (null before the first layout).
  GalleryLayoutModel? get current => _model;

  /// Something that moves tiles changed: recompute on next [modelFor].
  void invalidate() {
    _dirty = true;
    revision++;
  }

  GalleryLayoutSpec _specFor(double crossExtent) => GalleryLayoutSpec(
    crossExtent: crossExtent,
    spacing: spacing,
    flow: flow,
    columnCount: columnCount,
    minTileWidth: minTileWidth,
    sectionGap: sectionGap,
  );

  /// Builds a model from the current inputs without adopting it.
  GalleryLayoutModel buildCandidate(double crossExtent) =>
      GalleryLayoutModel.compute(
        sections: sections,
        spec: _specFor(crossExtent),
        ratioOf: ratioOf,
        footerOf: footerOf,
      );

  /// Makes [model] the layout in use and asks for a relayout, optionally
  /// keeping [anchor] in place.
  void adopt(GalleryLayoutModel model, {GalleryAnchor? anchor}) {
    _model = model;
    _dirty = false;
    pendingAnchor = anchor;
    revision++;
  }

  /// Makes [model] current without a relayout (nothing moved).
  void adoptQuietly(GalleryLayoutModel model) {
    _model = model;
    _dirty = false;
  }

  /// True while the layout above the top of the screen is known to be out of
  /// date (a [reflow] with `freezeAboveViewport` adopted a partial update).
  /// The view should call [reflow] again, without freezing, once it can.
  bool hasStalePrefix = false;

  /// Recomputes the layout after ratios changed and adopts it. Never defers:
  /// whatever is on screen is correct as soon as this returns.
  ///
  /// * [freezeAboveViewport] (the user is scrolling): everything from the top
  ///   row on screen downwards is recomputed, everything above it keeps its
  ///   exact old position. Nothing the user can see moves *vertically*, so no
  ///   scroll correction is needed (and none would survive a fling: the
  ///   ballistic simulation writes an absolute offset on every tick). Tiles
  ///   that are on screen change shape the moment their size is known. The
  ///   rows above are merely stale -- [hasStalePrefix] -- until the next
  ///   unfrozen reflow, which the view runs as soon as it is idle; and if the
  ///   user scrolls back up, the top row moves up with them, so the rows they
  ///   are looking at are refreshed by the very next reflow.
  /// * Otherwise (idle): everything is recomputed. When that moves anything
  ///   above the bottom of the screen it is adopted with an anchor on the tile
  ///   at the top of the screen, which the sliver turns into a same-pass scroll
  ///   correction.
  GalleryReflowResult reflow({
    required double crossExtent,
    bool freezeAboveViewport = false,
  }) {
    final old = _model;
    if (old == null || old.childCount == 0 || old.crossExtent != crossExtent) {
      adopt(buildCandidate(crossExtent));
      hasStalePrefix = false;
      return GalleryReflowResult.applied;
    }

    GalleryLayoutModel next;
    var frozen = false;
    if (freezeAboveViewport) {
      final top = old.minChildForOffset(sliverScrollOffset);
      final from = old.firstChildOfRowContaining(top);
      if (from > 0) {
        next = GalleryLayoutModel.recomputeFrom(
          previous: old,
          fromChild: from,
          sections: sections,
          spec: _specFor(crossExtent),
          ratioOf: ratioOf,
          footerOf: footerOf,
        );
        frozen = true;
      } else {
        next = buildCandidate(crossExtent);
      }
    } else {
      next = buildCandidate(crossExtent);
    }

    final firstChanged = old.firstChangedChild(next);
    if (firstChanged >= next.childCount) {
      adoptQuietly(next);
      // An unfrozen pass that found nothing to change has made the prefix
      // current; a frozen one never looked at it, so a size that changed above
      // the screen shows up here as "nothing changed" and is still pending.
      hasStalePrefix = frozen;
      return GalleryReflowResult.unchanged;
    }
    final viewportEnd = sliverScrollOffset + viewportExtent;
    final movesVisible = old.tops[firstChanged] < viewportEnd;
    // A frozen update never moves anything above the top row, so it needs no
    // anchor; an idle one anchors the top of the screen.
    final anchor = (!frozen && movesVisible) ? captureTopAnchor() : null;
    adopt(next, anchor: anchor);
    hasStalePrefix = frozen;
    return GalleryReflowResult.applied;
  }

  /// The model for [crossExtent], recomputed only when stale.
  GalleryLayoutModel modelFor(double crossExtent) {
    final cached = _model;
    if (cached != null && !_dirty && cached.crossExtent == crossExtent) {
      return cached;
    }
    final model = buildCandidate(crossExtent);
    _model = model;
    _dirty = false;
    return model;
  }

  /// The anchor that keeps whatever is at the top of the screen in place.
  GalleryAnchor? captureTopAnchor() {
    final m = _model;
    if (m == null || m.childCount == 0) return null;
    final c = m.minChildForOffset(sliverScrollOffset);
    return GalleryAnchor(child: c, viewportOffset: m.tops[c] - sliverScrollOffset);
  }

  /// The anchor that keeps whatever is at [offsetInViewport] (e.g. the pinch's
  /// focal point) at that same place on screen.
  GalleryAnchor? captureAnchorAt(double offsetInViewport) {
    final m = _model;
    if (m == null || m.childCount == 0) return null;
    final c = m.minChildForOffset(sliverScrollOffset + offsetInViewport);
    return GalleryAnchor(child: c, viewportOffset: m.tops[c] - sliverScrollOffset);
  }
}
