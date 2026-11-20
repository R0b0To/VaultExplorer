import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Where to read one item's size from.
class GalleryProbeTarget {
  const GalleryProbeTarget(this.container, this.path);

  final MountedContainer container;

  /// Path of the file inside [container].
  final String path;
}

/// Reads the pixel size of [paths] in [container] (null = unknown), e.g.
/// `VaultFileIoApi.probeImageDimensions`.
typedef GalleryProbeBatch =
    Future<List<({int width, int height})?>> Function(
      MountedContainer container,
      List<String> paths,
    );

/// Learns the aspect ratio of every image in a gallery *before* its tile is
/// built, so the layout is right the first time instead of reshuffling as
/// thumbnails arrive.
///
/// MediaStore hands it every entry's width and height
/// up front. A vault has no such index (and, by design, no database), so the
/// answer has to be read from the files. [GalleryProbeBatch] does that
/// cheaply -- headers only, a few KB per file -- and this class decides in what
/// order and how politely:
///
/// * **Nearest first.** Items are probed outward from [focusIndex] (the first
///   visible one, re-read before every batch, so a jump with the fast-scroll
///   handle immediately re-targets the work), two ahead for every one behind
///   because that is the direction people scroll.
/// * **One batch in flight**, a short pause between batches, and a pause while
///   [paused] says so (video playback owns the decoder and the disk).
/// * **Follows the viewport** (`follow: true`): a run does not end when its
///   window is exhausted, it keeps watching, so measuring continues as the user
///   scrolls instead of waiting for them to stop.
/// * **Every item at most once.** An image that cannot be probed is not retried
///   in a loop; it simply keeps its default shape until its thumbnail teaches
///   the view the real one, which is what happened before this existed.
class GalleryRatioPrefetcher {
  GalleryRatioPrefetcher({
    required this.probe,
    this.batchSize = 32,
    this.gap = const Duration(milliseconds: 12),
    this.lookAhead = 1500,
    this.lookBehind = 600,
    this.idleGap = const Duration(milliseconds: 250),
  });

  final GalleryProbeBatch probe;
  final int batchSize;
  final Duration gap;

  /// How far from the focus items are probed. A whole 40,000-photo folder is
  /// never worth reading up front; a run ends when its window is exhausted and
  /// the view starts the next one when the scroll settles.
  final int lookAhead;
  final int lookBehind;

  /// [start] with `follow: true`: how often a run that has nothing left to do
  /// looks again (the focus moved, or a tile asked for a size).
  final Duration idleGap;

  int _generation = 0;
  Uint8List _tried = Uint8List(0);

  // Pauses between batches are cancellable: a view that is disposed (or a run
  // that is restarted) must not leave a timer pending behind it.
  Timer? _sleepTimer;
  Completer<void>? _sleeper;

  bool get isRunning => _running;
  bool _running = false;

  /// (Re)starts prefetching; any run in progress is abandoned.
  ///
  /// [wantsProbe] must be cheap (it is called for items far from the focus):
  /// true only for an image whose ratio is still unknown.
  void start({
    required int itemCount,
    required bool Function(int index) wantsProbe,
    required GalleryProbeTarget? Function(int index) targetOf,
    required int Function() focusIndex,
    required void Function(int index, int width, int height) onResult,
    bool Function()? paused,
    bool resetTried = true,
    bool follow = false,
  }) {
    final generation = ++_generation;
    _wakeSleeper();
    // Items already attempted stay attempted across restarts for the same
    // list, so an image that cannot be probed is not retried at every scroll.
    if (resetTried || _tried.length != itemCount) _tried = Uint8List(itemCount);
    if (itemCount == 0) {
      _running = false;
      return;
    }
    unawaited(
      _run(
        generation: generation,
        itemCount: itemCount,
        wantsProbe: wantsProbe,
        targetOf: targetOf,
        focusIndex: focusIndex,
        onResult: onResult,
        paused: paused,
        follow: follow,
      ),
    );
  }

  /// Abandons the current run (the in-flight batch's result is dropped).
  void stop() {
    _generation++;
    _running = false;
    _wakeSleeper();
  }

  Future<void> _sleep(Duration duration) {
    final sleeper = Completer<void>();
    _sleeper = sleeper;
    _sleepTimer = Timer(duration, () {
      if (!sleeper.isCompleted) sleeper.complete();
    });
    return sleeper.future;
  }

  void _wakeSleeper() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    final sleeper = _sleeper;
    _sleeper = null;
    if (sleeper != null && !sleeper.isCompleted) sleeper.complete();
  }

  /// Picks up to [batchSize] untried indices that [wantsProbe], nearest to
  /// [focus] first. Exposed for tests.
  List<int> collectBatch({
    required int itemCount,
    required int focus,
    required bool Function(int index) wantsProbe,
  }) {
    final picks = <int>[];
    var forward = math.max(0, math.min(itemCount - 1, focus));
    final forwardEnd = math.min(itemCount, forward + lookAhead);
    final backwardEnd = math.max(0, forward - lookBehind);
    var backward = forward - 1;
    while (picks.length < batchSize &&
        (forward < forwardEnd || backward >= backwardEnd)) {
      for (var k = 0; k < 2 && forward < forwardEnd && picks.length < batchSize; k++) {
        if (_tried[forward] == 0 && wantsProbe(forward)) picks.add(forward);
        forward++;
      }
      if (backward >= backwardEnd && picks.length < batchSize) {
        if (_tried[backward] == 0 && wantsProbe(backward)) picks.add(backward);
        backward--;
      }
    }
    return picks;
  }

  Future<void> _run({
    required int generation,
    required int itemCount,
    required bool Function(int index) wantsProbe,
    required GalleryProbeTarget? Function(int index) targetOf,
    required int Function() focusIndex,
    required void Function(int index, int width, int height) onResult,
    required bool Function()? paused,
    required bool follow,
  }) async {
    _running = true;
    try {
      while (generation == _generation) {
        if (paused?.call() ?? false) {
          await _sleep(const Duration(milliseconds: 300));
          continue;
        }
        final batch = collectBatch(
          itemCount: itemCount,
          focus: focusIndex(),
          wantsProbe: wantsProbe,
        );
        if (batch.isEmpty) {
          if (!follow) return;
          // Nothing within reach is left to measure: keep watching. Scrolling
          // moves the focus, which brings new items into reach, and nothing has
          // to be told about it.
          await _sleep(idleGap);
          continue;
        }

        // One native call per container (a category view mixes vaults).
        final groups = <String, _ProbeGroup>{};
        for (final index in batch) {
          _tried[index] = 1;
          final target = targetOf(index);
          if (target == null) continue;
          groups
              .putIfAbsent(target.container.uri, () => _ProbeGroup(target.container))
              .add(index, target.path);
        }
        for (final group in groups.values) {
          final sizes = await probe(group.container, group.paths);
          if (generation != _generation) return;
          for (var k = 0; k < group.indices.length && k < sizes.length; k++) {
            final size = sizes[k];
            if (size != null) onResult(group.indices[k], size.width, size.height);
          }
        }
        await _sleep(gap);
      }
    } catch (_) {
      // A failed probe only means shapes get learned from thumbnails instead;
      // the next start() begins a fresh run.
    } finally {
      if (generation == _generation) _running = false;
    }
  }
}

class _ProbeGroup {
  _ProbeGroup(this.container);

  final MountedContainer container;
  final List<int> indices = [];
  final List<String> paths = [];

  void add(int index, String path) {
    indices.add(index);
    paths.add(path);
  }
}
