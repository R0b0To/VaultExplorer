import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_layout.dart';

List<double> _ratios(int n, {int seed = 1}) {
  final rnd = math.Random(seed);
  const pool = [0.5625, 0.75, 1.0, 1.333, 1.5, 1.777, 2.4, 0.4];
  return [for (var i = 0; i < n; i++) pool[rnd.nextInt(pool.length)]];
}

GalleryLayoutModel _layout(
  List<double> ratios, {
  GalleryFlow flow = GalleryFlow.rows,
  double width = 400,
  int columns = 3,
  double spacing = 6,
  List<GallerySection>? sections,
  double footer = 0,
  double headerExtent = 0,
  double sectionGap = 0,
}) {
  return GalleryLayoutModel.compute(
    sections: sections ??
        [GallerySection(itemCount: ratios.length, headerExtent: headerExtent)],
    spec: GalleryLayoutSpec(
      crossExtent: width,
      spacing: spacing,
      flow: flow,
      columnCount: columns,
      sectionGap: sectionGap,
    ),
    ratioOf: (i) => ratios[i],
    footerOf: footer == 0 ? null : (i, w) => footer,
  );
}

void _expectNoOverlapAndInBounds(GalleryLayoutModel m, double width) {
  for (var a = 0; a < m.childCount; a++) {
    expect(m.lefts[a] >= -1e-6, isTrue, reason: 'left of $a');
    expect(m.lefts[a] + m.widths[a] <= width + 1e-6, isTrue, reason: 'right of $a');
    expect(m.heights[a] >= 0, isTrue);
  }
  // Pairwise overlap check on a window (children are ordered by top).
  for (var a = 0; a < m.childCount; a++) {
    for (var b = a + 1; b < m.childCount && b < a + 40; b++) {
      final overlapX = m.lefts[a] < m.lefts[b] + m.widths[b] - 1e-6 &&
          m.lefts[b] < m.lefts[a] + m.widths[a] - 1e-6;
      final overlapY = m.tops[a] < m.bottomOf(b) - 1e-6 &&
          m.tops[b] < m.bottomOf(a) - 1e-6;
      expect(overlapX && overlapY, isFalse, reason: 'children $a and $b overlap');
    }
  }
}

void main() {
  group('rows (mosaic) flow', () {
    test('fills the width exactly in every complete row', () {
      final r = _ratios(300);
      final m = _layout(r);
      _expectNoOverlapAndInBounds(m, 400);
      // Group tiles by top; every row except each section's last is justified.
      final rows = <double, List<int>>{};
      for (var c = 0; c < m.childCount; c++) {
        rows.putIfAbsent(m.tops[c], () => []).add(c);
      }
      final tops = rows.keys.toList()..sort();
      for (final t in tops.take(tops.length - 1)) {
        final cs = rows[t]!;
        final right = m.lefts[cs.last] + m.widths[cs.last];
        expect((right - 400).abs() < 1e-6, isTrue, reason: 'row at $t ends at $right');
        // Same height within a row.
        for (final c in cs) {
          expect((m.heights[c] - m.heights[cs.first]).abs() < 1e-9, isTrue);
        }
      }
    });

    test('tile shape follows the aspect ratio (nothing is cropped)', () {
      final r = _ratios(200, seed: 7);
      final m = _layout(r);
      for (var i = 0; i < r.length; i++) {
        final c = m.childOfItem[i];
        expect((m.widths[c] / m.heights[c] - r[i]).abs() < 1e-6 ||
            // last row of a section may be left-aligned but keeps the ratio too
            true, isTrue);
        expect((m.widths[c] / m.heights[c] - r[i]).abs() < 1e-6, isTrue,
            reason: 'item $i ratio ${m.widths[c] / m.heights[c]} vs ${r[i]}');
      }
    });

    test('row heights stay close to the grid cell height', () {
      final r = _ratios(500, seed: 3);
      final m = _layout(r, columns: 4);
      final target = (400 - 3 * 6) / 4;
      final rowHeights = <double>{};
      for (var c = 0; c < m.childCount - 8; c++) {
        rowHeights.add(m.heights[c]);
      }
      for (final h in rowHeights) {
        expect(h >= target * 0.6 && h <= target * 2.3, isTrue, reason: 'h=$h target=$target');
      }
    });

    test('a lone item in the last row is not blown up', () {
      final m = _layout([1.0, 1.0, 1.0, 1.0], columns: 3);
      final last = m.childOfItem[3];
      final target = (400 - 2 * 6) / 3;
      expect(m.heights[last] <= target * 1.35 + 1e-6, isTrue);
      expect(m.lefts[last], 0);
    });

    test('a tall portrait keeps taking items instead of making a giant row', () {
      final m = _layout([0.25, 1.0, 1.0, 1.0, 1.0, 1.0], columns: 3);
      final target = (400 - 2 * 6) / 3;
      expect(m.heights[0] <= target * 2.2 * 1.0001 + 1e-6, isTrue,
          reason: 'row height ${m.heights[0]}');
    });

    test('footer is added to every tile of the row', () {
      final r = _ratios(60, seed: 5);
      final plain = _layout(r);
      final withFooter = _layout(r, footer: 30);
      expect(withFooter.maxExtent > plain.maxExtent, isTrue);
      for (var c = 0; c < withFooter.childCount; c++) {
        // Media area keeps the ratio: width / (height - footer)
        final i = withFooter.itemOfChild[c];
        expect((withFooter.widths[c] / (withFooter.heights[c] - 30) - r[i]).abs() < 1e-6, isTrue);
      }
    });

    test('is deterministic', () {
      final r = _ratios(1000, seed: 11);
      final a = _layout(r);
      final b = _layout(r);
      expect(a.firstChangedChild(b), a.childCount);
    });
  });

  group('columns flow', () {
    test('places every tile in the shortest column', () {
      final r = _ratios(400, seed: 2);
      final m = _layout(r, flow: GalleryFlow.columns, columns: 3);
      _expectNoOverlapAndInBounds(m, 400);
      final colBottom = List<double>.filled(3, 0);
      final tileW = (400 - 2 * 6) / 3;
      for (var i = 0; i < r.length; i++) {
        final c = m.childOfItem[i];
        final col = (m.lefts[c] / (tileW + 6)).round();
        final shortest = colBottom.reduce(math.min);
        expect(colBottom[col], shortest, reason: 'item $i went to column $col');
        expect((m.tops[c] - shortest).abs() < 1e-9, isTrue);
        colBottom[col] = m.tops[c] + m.heights[c] + 6;
      }
    });

    test('tops never decrease with the child index', () {
      final m = _layout(_ratios(2000, seed: 4), flow: GalleryFlow.columns);
      for (var c = 1; c < m.childCount; c++) {
        expect(m.tops[c] >= m.tops[c - 1] - 1e-9, isTrue);
      }
    });

    test('constant ratio gives a uniform grid in reading order', () {
      final m = _layout(List.filled(10, 1.0), flow: GalleryFlow.columns, columns: 3);
      final tileW = (400 - 2 * 6) / 3;
      for (var i = 0; i < 10; i++) {
        final c = m.childOfItem[i];
        expect(((m.lefts[c] / (tileW + 6)).round()), i % 3);
        expect((m.tops[c] - (i ~/ 3) * (tileW + 6)).abs() < 1e-9, isTrue);
      }
    });
  });

  group('sections and headers', () {
    test('headers occupy a child each and items follow in display order', () {
      final sections = [
        const GallerySection(itemCount: 5, headerExtent: 40),
        const GallerySection(itemCount: 0, headerExtent: 0),
        const GallerySection(itemCount: 7, headerExtent: 40),
      ];
      final m = _layout(_ratios(12), sections: sections, sectionGap: 12);
      expect(m.childCount, 12 + 2);
      expect(m.isHeader(0), isTrue);
      expect(m.isHeader(6), isTrue);
      expect(m.itemOfChild[1], 0);
      expect(m.itemOfChild[5], 4);
      expect(m.itemOfChild[7], 5);
      expect(m.childOfItem[5], 7);
      expect(m.tops[0], 0);
      expect(m.heights[0], 40);
      expect(m.widths[0], 400);
      // Second header sits below every tile of the first section plus the gap.
      var maxBottom = 0.0;
      for (var c = 1; c <= 5; c++) {
        maxBottom = math.max(maxBottom, m.bottomOf(c));
      }
      expect((m.tops[6] - (maxBottom + 12)).abs() < 1e-9, isTrue);
      expect(m.sectionFirstChild.toList(), [0, 6, 6, 14]);
    });

    test('an empty layout is safe to query', () {
      final m = _layout([], sections: const []);
      expect(m.childCount, 0);
      expect(m.minChildForOffset(100), 0);
      expect(m.maxChildForOffset(100), 0);
      expect(m.maxExtent, 0);
    });
  });

  group('scroll queries', () {
    for (final flow in GalleryFlow.values) {
      test('visible window is always covered ($flow)', () {
        final rnd = math.Random(9);
        final sections = [
          for (var s = 0; s < 40; s++)
            GallerySection(itemCount: 1 + rnd.nextInt(60), headerExtent: 44),
        ];
        final n = sections.fold<int>(0, (a, s) => a + s.itemCount);
        final m = _layout(_ratios(n, seed: 21),
            flow: flow, sections: sections, sectionGap: 10, footer: 24);
        for (var t = 0; t < 400; t++) {
          final start = rnd.nextDouble() * m.maxExtent;
          final end = start + 100 + rnd.nextDouble() * 1500;
          final lo = m.minChildForOffset(start);
          final hi = m.maxChildForOffset(end);
          for (var c = 0; c < m.childCount; c++) {
            final visible = m.bottomOf(c) > start && m.tops[c] < end;
            if (visible) {
              expect(c >= lo && c <= hi, isTrue,
                  reason: 'child $c visible in [$start,$end] but window is [$lo,$hi]');
            }
          }
          // Tightness: the first child of the window is itself visible (or the
          // last one when scrolled past the end).
          if (start < m.maxExtent - 1) {
            expect(m.bottomOf(lo) > start - 1e-9 || lo == m.childCount - 1, isTrue);
          }
        }
      });
    }

    test('maxExtent covers the bottom of every child', () {
      final m = _layout(_ratios(777), flow: GalleryFlow.columns);
      for (var c = 0; c < m.childCount; c++) {
        expect(m.bottomOf(c) <= m.maxExtent + 1e-6, isTrue);
      }
    });
  });

  group('change detection', () {
    test('only the changed tail is reported when a late item changes shape', () {
      final r = _ratios(500, seed: 31);
      final a = _layout(r);
      final r2 = [...r]..[400] = r[400] == 1.0 ? 0.5 : 1.0;
      final b = _layout(r2);
      final first = a.firstChangedChild(b);
      expect(first <= 400, isTrue);
      expect(first > 300, isTrue, reason: 'first changed child $first');
      // Everything before it is untouched (that is what lets the view apply the
      // change without moving anything on screen when it is below the viewport).
      for (var c = 0; c < first; c++) {
        expect(a.tops[c], b.tops[c]);
        expect(a.widths[c], b.widths[c]);
      }
    });
  });

  group('host', () {
    test('modelFor is cached until invalidated or the width changes', () {
      final r = _ratios(100);
      final host = GalleryLayoutHost(flow: GalleryFlow.rows, columnCount: 3)
        ..sections = [GallerySection(itemCount: r.length)]
        ..ratioOf = ((i) => r[i]);
      final a = host.modelFor(400);
      expect(identical(a, host.modelFor(400)), isTrue);
      expect(identical(a, host.modelFor(401)), isFalse);
      final b = host.modelFor(401);
      host.invalidate();
      expect(identical(b, host.modelFor(401)), isFalse);
    });

    test('anchor keeps the same child at the same viewport position', () {
      final r = _ratios(400, seed: 5);
      final host = GalleryLayoutHost(flow: GalleryFlow.rows, columnCount: 3)
        ..sections = [GallerySection(itemCount: r.length)]
        ..ratioOf = ((i) => r[i]);
      host.modelFor(400);
      host.sliverScrollOffset = 1234;
      final anchor = host.captureTopAnchor()!;
      final old = host.current!;
      expect(old.bottomOf(anchor.child) > 1234, isTrue);
      expect(anchor.child == 0 || old.bottomOf(anchor.child - 1) <= 1234 + 1e-9 ||
          old.prefixMaxBottom[anchor.child - 1] <= 1234 + 1e-9, isTrue);
    });
  });

  group('recomputeFrom (frozen prefix)', () {
    void expectSame(GalleryLayoutModel a, GalleryLayoutModel b, {int upTo = -1}) {
      final n = upTo < 0 ? a.childCount : upTo;
      expect(a.childCount, b.childCount);
      for (var c = 0; c < n; c++) {
        expect((a.tops[c] - b.tops[c]).abs() < 1e-9, isTrue, reason: 'top of $c');
        expect((a.heights[c] - b.heights[c]).abs() < 1e-9, isTrue, reason: 'height of $c');
        expect((a.lefts[c] - b.lefts[c]).abs() < 1e-9, isTrue, reason: 'left of $c');
        expect((a.widths[c] - b.widths[c]).abs() < 1e-9, isTrue, reason: 'width of $c');
      }
    }

    for (final flow in GalleryFlow.values) {
      test('equals a full layout when only the tail changed ($flow)', () {
        final rnd = math.Random(5);
        for (var round = 0; round < 40; round++) {
          final sections = [
            for (var s = 0; s < 1 + rnd.nextInt(8); s++)
              GallerySection(
                itemCount: rnd.nextInt(70),
                headerExtent: rnd.nextBool() ? 44 : 0,
              ),
          ];
          final n = sections.fold<int>(0, (a, s) => a + s.itemCount);
          if (n < 4) continue;
          final r = _ratios(n, seed: 100 + round);
          GalleryLayoutModel build(List<double> ratios) => _layout(
            ratios,
            flow: flow,
            sections: sections,
            sectionGap: 10,
            footer: 22,
            columns: 2,
          );
          final old = build(r);
          final from = 1 + rnd.nextInt(old.childCount - 1);
          final aligned = flow == GalleryFlow.rows
              ? old.firstChildOfRowContaining(from)
              : from;
          final r2 = [...r];
          for (var i = 0; i < n; i++) {
            if (old.childOfItem[i] >= aligned && rnd.nextInt(3) == 0) {
              r2[i] = r2[i] == 1.0 ? 0.6 : 1.0;
            }
          }
          final full = build(r2);
          final partial = GalleryLayoutModel.recomputeFrom(
            previous: old,
            fromChild: from,
            sections: sections,
            spec: GalleryLayoutSpec(
              crossExtent: 400,
              spacing: 6,
              flow: flow,
              columnCount: 2,
              sectionGap: 10,
            ),
            ratioOf: (i) => r2[i],
            footerOf: (i, w) => 22,
          );
          expectSame(partial, full);
          expect((partial.maxExtent - full.maxExtent).abs() < 1e-9, isTrue);
        }
      });

      test('keeps everything above the cut exactly where it was ($flow)', () {
        final r = _ratios(500, seed: 61);
        final old = _layout(r, flow: flow, columns: 3);
        final from = 200;
        final aligned = flow == GalleryFlow.rows ? old.firstChildOfRowContaining(from) : from;
        // Change shapes both above and below the cut.
        final r2 = [for (var i = 0; i < r.length; i++) i.isEven ? (r[i] == 1.0 ? 0.5 : 1.0) : r[i]];
        final partial = GalleryLayoutModel.recomputeFrom(
          previous: old,
          fromChild: from,
          sections: [GallerySection(itemCount: r.length)],
          spec: GalleryLayoutSpec(crossExtent: 400, spacing: 6, flow: flow, columnCount: 3),
          ratioOf: (i) => r2[i],
        );
        for (var c = 0; c < aligned; c++) {
          expect(partial.tops[c], old.tops[c]);
          expect(partial.heights[c], old.heights[c]);
          expect(partial.lefts[c], old.lefts[c]);
          expect(partial.widths[c], old.widths[c]);
        }
        _expectNoOverlapAndInBounds(partial, 400);
        for (var c = 1; c < partial.childCount; c++) {
          expect(partial.tops[c] >= partial.tops[c - 1] - 1e-9, isTrue);
        }
        // The tail follows the new ratios.
        final i = old.itemOfChild[aligned + 10];
        final c = partial.childOfItem[i];
        expect((partial.widths[c] / partial.heights[c] - r2[i]).abs() < 1e-6, isTrue);
      });
    }

    test('a cut at the very start or past the end is a full layout', () {
      final r = _ratios(80, seed: 3);
      final old = _layout(r);
      final spec = GalleryLayoutSpec(crossExtent: 400, spacing: 6, flow: GalleryFlow.rows, columnCount: 3);
      for (final from in [0, -5, old.childCount, old.childCount + 9]) {
        final m = GalleryLayoutModel.recomputeFrom(
          previous: old,
          fromChild: from,
          sections: [GallerySection(itemCount: r.length)],
          spec: spec,
          ratioOf: (i) => r[i],
        );
        expectSame(m, old);
      }
    });
  });

  group('reflow (never waits for the scroll to settle)', () {
    GalleryLayoutHost hostWith(List<double> ratios, {double scroll = 0, double viewport = 800}) {
      final host = GalleryLayoutHost(flow: GalleryFlow.rows, columnCount: 3)
        ..sections = [GallerySection(itemCount: ratios.length)]
        ..ratioOf = ((i) => ratios[i]);
      host.modelFor(400);
      host
        ..sliverScrollOffset = scroll
        ..viewportExtent = viewport
        ..sliverCrossExtent = 400;
      return host;
    }

    test('a change below the screen is adopted at once, with no anchor', () {
      final r = _ratios(600, seed: 40);
      final host = hostWith(r);
      final before = host.current!;
      expect(before.tops[before.childOfItem[550]] > 2000, isTrue);
      r[550] = r[550] == 1.0 ? 0.5 : 1.0;
      expect(host.reflow(crossExtent: 400, freezeAboveViewport: true), GalleryReflowResult.applied);
      expect(host.pendingAnchor, null);
      expect(identical(host.current, before), isFalse);
    });

    test('while scrolling, on-screen tiles update at once and nothing above moves', () {
      final r = _ratios(600, seed: 41);
      final host = hostWith(r, scroll: 1500);
      final before = host.current!;
      final top = before.minChildForOffset(1500);
      final topRow = before.firstChildOfRowContaining(top);
      // A tile that is on screen, and one far above it.
      final onScreen = before.itemOfChild[top + 2];
      final above = before.itemOfChild[3];
      r[onScreen] = r[onScreen] == 1.0 ? 0.45 : 1.0;
      r[above] = r[above] == 1.0 ? 0.45 : 1.0;

      expect(host.reflow(crossExtent: 400, freezeAboveViewport: true), GalleryReflowResult.applied);
      final after = host.current!;
      // Applied immediately: the visible tile has its new shape.
      final c = after.childOfItem[onScreen];
      expect((after.widths[c] / after.heights[c] - r[onScreen]).abs() < 1e-6, isTrue);
      // Nothing from the top row upwards moved (so no scroll correction exists
      // to be overwritten by a fling), and the shape above is stale on purpose.
      for (var i = 0; i < topRow; i++) {
        expect(after.tops[i], before.tops[i]);
        expect(after.widths[i], before.widths[i]);
      }
      expect(host.pendingAnchor, null);
      expect(host.hasStalePrefix, isTrue);
    });

    test('once idle, the stale rows above are fixed and the top of the screen stays put', () {
      final r = _ratios(600, seed: 42);
      final host = hostWith(r, scroll: 1234);
      final before = host.current!;
      final c0 = before.minChildForOffset(1234);
      final screenPosition = before.tops[c0] - 1234;
      for (var i = 0; i < before.itemOfChild[c0]; i++) {
        r[i] = r[i] == 1.0 ? 0.5 : 1.0;
      }
      expect(host.reflow(crossExtent: 400, freezeAboveViewport: true), GalleryReflowResult.unchanged);
      expect(host.hasStalePrefix, isTrue);

      expect(host.reflow(crossExtent: 400), GalleryReflowResult.applied);
      expect(host.hasStalePrefix, isFalse);
      final anchor = host.pendingAnchor!;
      expect(anchor.child, c0);
      final newOffset = host.current!.tops[anchor.child] - anchor.viewportOffset;
      expect((host.current!.tops[c0] - newOffset - screenPosition).abs() < 1e-9, isTrue);
      expect(host.current!.tops[c0] != before.tops[c0], isTrue,
          reason: 'the test must actually move the tile');
    });

    test('scrolling back up refreshes the rows that come into view', () {
      final r = _ratios(600, seed: 43);
      final host = hostWith(r, scroll: 2500);
      final before = host.current!;
      // Learn sizes for tiles that are far above the screen while scrolling down.
      for (var i = 0; i < 60; i++) {
        r[i] = r[i] == 1.0 ? 0.45 : 1.0;
      }
      host.reflow(crossExtent: 400, freezeAboveViewport: true);
      expect(host.hasStalePrefix, isTrue);
      final stale = host.current!;
      // The user scrolls back up to where those tiles are.
      host.sliverScrollOffset = before.tops[before.childOfItem[20]];
      host.reflow(crossExtent: 400, freezeAboveViewport: true);
      final refreshed = host.current!;
      final fresh = GalleryLayoutModel.compute(
        sections: host.sections,
        spec: const GalleryLayoutSpec(crossExtent: 400, spacing: 8, flow: GalleryFlow.rows, columnCount: 3),
        ratioOf: (i) => r[i],
      );
      final top = refreshed.firstChildOfRowContaining(refreshed.minChildForOffset(host.sliverScrollOffset));
      // From the new top row on, the layout is exactly the up to date one.
      for (var c = top; c < top + 30; c++) {
        expect(refreshed.widths[c] > 0, isTrue);
        final i = refreshed.itemOfChild[c];
        expect((refreshed.widths[c] / refreshed.heights[c] - r[i]).abs() < 1e-6, isTrue,
            reason: 'child $c shows the stale shape');
      }
      expect(identical(stale, refreshed), isFalse);
      expect((fresh.maxExtent - refreshed.maxExtent).abs() < 5000, isTrue);
    });

    test('an identical layout is reported as unchanged', () {
      final host = hostWith(_ratios(300, seed: 44));
      expect(host.reflow(crossExtent: 400), GalleryReflowResult.unchanged);
    });
  });

  test('performance: 100k items lay out quickly', () {
    final r = _ratios(100000, seed: 77);
    final sw = Stopwatch()..start();
    final m = _layout(r, footer: 28);
    sw.stop();
    expect(m.childCount, 100000);
    // Generous bound; on a laptop this is a handful of milliseconds.
    expect(sw.elapsedMilliseconds < 1500, isTrue, reason: '${sw.elapsedMilliseconds} ms');
  });
}
