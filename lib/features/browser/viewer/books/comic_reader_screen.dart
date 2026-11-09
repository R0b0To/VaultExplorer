import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/image_dimensions.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/book_reader_state_store.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/image_page_item.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/playlist_carousel_overlay.dart';
import 'package:vaultexplorer/features/browser/viewer/zoom_snap_back.dart';

/// Full-screen comic (.cbz) reader.
///
/// Pages are read straight out of the archive in memory (see
/// [VaultBookApi]) and handed to the media viewer's own [ImagePageItem], so
/// zoom, pan, double-tap and edge taps feel exactly like the image viewer --
/// but without staging the pages as plaintext files, which is what putting a
/// whole comic through the regular playlist would require.
///
/// The reader owns the book session: it closes it (and drops the cached
/// pages) when it goes away.
class ComicReaderScreen extends ConsumerStatefulWidget {
  /// The vault the comic was opened from; the reader goes blank if it locks.
  final MountedContainer container;
  final String title;
  final String filePath;
  final String token;

  /// Archive entry names in reading order (see `comicPageNames`).
  final List<String> pages;

  const ComicReaderScreen({
    super.key,
    required this.container,
    required this.title,
    required this.filePath,
    required this.token,
    required this.pages,
  });

  @override
  ConsumerState<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends ConsumerState<ComicReaderScreen>
    with SingleTickerProviderStateMixin {
  late final VaultBookApi _api;
  late final VaultEngineEvents _events;
  bool _locked = false;
  final PageController _controller = PageController();
  final ScrollController _verticalController = ScrollController();

  /// Page bytes live in the shared in-memory image cache under this throwaway
  /// container identity, so they never collide with real vault files.
  late final MountedContainer _cacheContainer = buildLocalStorageContainer(
    rootPath: '',
    displayName: widget.title,
    readOnly: true,
  );

  final Map<int, Future<void>> _inFlight = {};
  final Map<int, (int, int)> _dimensions = {};
  late final List<GlobalKey> _verticalPageKeys = List<GlobalKey>.generate(
    widget.pages.length,
    (_) => GlobalKey(),
  );
  final ValueNotifier<bool> _swipeLocked = ValueNotifier<bool>(false);
  final Set<int> _pointers = <int>{};
  bool _zoomLock = false;

  // Vertical (continuous) mode is zoomed as one piece: see
  // [_onVerticalTransformChanged].
  final TransformationController _verticalTransform =
      TransformationController();
  late final AnimationController _verticalZoomController;
  Animation<Matrix4>? _verticalZoomAnimation;
  double _verticalScale = 1.0;
  bool _clampingVertical = false;
  Size _verticalViewport = Size.zero;
  TapDownDetails? _verticalDoubleTapDetails;
  Timer? _verticalSnapBackTimer;

  int _index = 0;
  double? _scrubValue;
  bool _showUi = true;
  bool _carouselVisible = true;
  bool _rtl = false;
  bool _ready = false;
  String _mode = 'single';
  List<BookReaderBookmark> _bookmarks = const [];
  late final String _documentId = bookReaderStateStore.documentId(
    widget.container,
    widget.filePath,
  );
  bool _verticalIndexUpdatePending = false;

  @override
  void initState() {
    super.initState();
    _api = ref.read(vaultBookApiProvider);
    _events = ref.read(vaultEngineEventsProvider);
    _events.addContainerLockedListener(_onContainerLocked);
    _verticalController.addListener(_onVerticalScroll);
    _verticalTransform.addListener(_onVerticalTransformChanged);
    _verticalZoomController =
        AnimationController(
          vsync: this,
          duration: MediaViewerConstants.animationDuration,
        )..addListener(() {
          final animation = _verticalZoomAnimation;
          if (animation != null) _setVerticalMatrix(animation.value);
        });
    unawaited(_restoreState());
  }

  Future<void> _restoreState() async {
    final saved = await bookReaderStateStore.load(_documentId);
    if (!mounted) return;
    setState(() {
      _index = saved.position.clamp(0, widget.pages.length - 1).toInt();
      _rtl = saved.rtl;
      _carouselVisible = saved.showComicThumbnails;
      _mode = const {'single', 'spread', 'vertical'}.contains(saved.mode)
          ? saved.mode
          : 'single';
      _bookmarks = saved.bookmarks
          .where(
            (bookmark) =>
                bookmark.position >= 0 &&
                bookmark.position < widget.pages.length,
          )
          .toList(growable: false);
      _ready = true;
    });
    if (_mode == 'vertical') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_verticalController.hasClients) {
          _verticalController.jumpTo(_estimatedVerticalOffset(_index));
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _controller.jumpToPage(_slideForPage(_index));
        }
      });
    }
    _prefetch(_index);
  }

  Future<void> _saveState({double fraction = 0}) => bookReaderStateStore.save(
    _documentId,
    BookReaderState(
      position: _index,
      fraction: fraction,
      rtl: _rtl,
      showComicThumbnails: _carouselVisible,
      mode: _mode,
      bookmarks: _bookmarks,
    ),
  );

  void _onContainerLocked(int volId) {
    if (volId != widget.container.volId || !mounted) return;
    // Drop every decrypted page now rather than waiting for dispose.
    for (var i = 0; i < widget.pages.length; i++) {
      FullResImageCache.invalidate(_cacheContainer, _cacheKey(i));
    }
    setState(() => _locked = true);
  }

  @override
  void dispose() {
    _events.removeContainerLockedListener(_onContainerLocked);
    _verticalSnapBackTimer?.cancel();
    _verticalZoomController.dispose();
    _verticalTransform.removeListener(_onVerticalTransformChanged);
    _verticalTransform.dispose();
    _controller.dispose();
    _verticalController.dispose();
    _swipeLocked.dispose();
    for (var i = 0; i < widget.pages.length; i++) {
      FullResImageCache.invalidate(_cacheContainer, _cacheKey(i));
    }
    unawaited(_api.close(widget.token));
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  String _cacheKey(int i) => 'comic/${widget.token}/${widget.pages[i]}';

  Future<void> _ensureLoaded(int i) {
    if (FullResImageCache.get(_cacheContainer, _cacheKey(i)) != null) {
      return Future<void>.value();
    }
    // Block body on purpose: an arrow body would return the removed future --
    // this very one -- and whenComplete would then wait on itself forever.
    return _inFlight[i] ??= _fetch(i).whenComplete(() {
      _inFlight.remove(i);
    });
  }

  Future<void> _fetch(int i) async {
    final Uint8List bytes = await _api.readEntry(widget.token, widget.pages[i]);
    // A read that finishes after the reader is gone (or its vault locked)
    // must not put decrypted pages back into the shared cache.
    if (!mounted || _locked) return;
    FullResImageCache.put(_cacheContainer, _cacheKey(i), bytes);
    final dimensions = extractImageDimensionsFromBytes(bytes);
    if (dimensions != null) _dimensions[i] = dimensions;
  }

  void _prefetch(int center) {
    for (final i in [center, center + 1, center - 1, center + 2]) {
      if (i < 0 || i >= widget.pages.length) continue;
      unawaited(_ensureLoaded(i).catchError((Object _) {}));
    }
  }

  void _onPageChanged(int i) {
    final index = _mode == 'spread' ? _spreadStarts[i] : i;
    setState(() {
      _index = index;
    });
    // A new page always starts un-zoomed.
    _zoomLock = false;
    _updateSwipeLock();
    _prefetch(index);
    unawaited(_saveState());
  }

  void _goTo(int i) {
    if (i < 0 || i >= widget.pages.length) return;
    if (_mode == 'vertical') {
      if (!_verticalController.hasClients) return;
      // The scroll offset only means something at 1x.
      _resetVerticalZoom();
      unawaited(
        _verticalController.animateTo(
          _estimatedVerticalOffset(i),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      if (!_controller.hasClients) return;
      unawaited(
        _controller.animateToPage(
          _slideForPage(i),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  /// [rightEdge] true = the viewer's right tap zone. Reading right to left
  /// the next page is on the left, so the zones swap meaning.
  void _onEdgeTap(bool rightEdge) {
    final forward = _rtl ? !rightEdge : rightEdge;
    if (_mode == 'spread') {
      final target = forward
          ? (_index == 0 ? 1 : _index + 2)
          : (_index <= 1 ? 0 : _index - 2);
      _goTo(target);
      return;
    }
    _goTo(_index + (forward ? 1 : -1));
  }

  List<int> get _spreadStarts {
    final starts = <int>[0];
    for (var page = 1; page < widget.pages.length; page += 2) {
      starts.add(page);
    }
    return starts;
  }

  int _slideForPage(int page) {
    if (_mode != 'spread') return page;
    final starts = _spreadStarts;
    for (var i = starts.length - 1; i >= 0; i--) {
      if (page >= starts[i]) return i;
    }
    return 0;
  }

  void _onVerticalScroll() {
    if (_verticalIndexUpdatePending) return;
    _verticalIndexUpdatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verticalIndexUpdatePending = false;
      if (!mounted || !_verticalController.hasClients) return;
      final centerY = MediaQuery.sizeOf(context).height / 2;
      var bestIndex = _index;
      var bestDistance = double.infinity;
      for (var i = 0; i < _verticalPageKeys.length; i++) {
        final renderObject = _verticalPageKeys[i].currentContext
            ?.findRenderObject();
        if (renderObject is! RenderBox || !renderObject.hasSize) continue;
        final top = renderObject.localToGlobal(Offset.zero).dy;
        final bottom = top + renderObject.size.height;
        final distance = centerY < top
            ? top - centerY
            : (centerY > bottom ? centerY - bottom : 0.0);
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIndex = i;
        }
        if (distance == 0) break;
      }
      if (bestIndex == _index) return;
      setState(() {
        _index = bestIndex;
      });
      _prefetch(bestIndex);
      unawaited(_saveState());
    });
  }

  double _estimatedVerticalOffset(int index) {
    final width = MediaQuery.sizeOf(context).width;
    final fallback = MediaQuery.sizeOf(context).height;
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      final size = _dimensions[i];
      offset += size == null || size.$1 <= 0
          ? fallback
          : width * size.$2 / size.$1;
    }
    return offset;
  }

  // ---- Vertical (continuous) zoom -----------------------------------------
  //
  // Same idea as the media viewer's continuous playlist: the pages have their
  // own zoom turned off and one InteractiveViewer around the whole list zooms
  // them all together. "Zoomed" means the list is drawn through a transform,
  // it is not re-laid out, so it keeps scrolling normally underneath it.

  /// How far a pinch may zoom out before it is held there. Whatever it is
  /// pinched to, the view glides back to 1x once the fingers lift.
  static const double _minVerticalZoom = 0.25;

  static double _matrixScale(Matrix4 matrix) {
    final x = matrix.storage[0];
    final y = matrix.storage[1];
    return math.sqrt(x * x + y * y);
  }

  Matrix4 _verticalMatrix(double dx, double dy, double scale) =>
      Matrix4.identity()
        ..translateByDouble(dx, dy, 0.0, 1.0)
        ..scaleByDouble(scale, scale, scale, 1.0);

  /// Writes the transform without [_onVerticalTransformChanged] stepping in.
  void _setVerticalMatrix(Matrix4 matrix) {
    _clampingVertical = true;
    _verticalTransform.value = matrix;
    _clampingVertical = false;
  }

  /// Keeps the zoomed list inside the screen: held at the minimum while
  /// pinching out, and not pannable past its own edges while zoomed in.
  void _onVerticalTransformChanged() {
    if (_clampingVertical || !mounted) return;
    final vw = _verticalViewport.width;
    final vh = _verticalViewport.height;
    if (vw <= 0 || vh <= 0) return;

    final matrix = _verticalTransform.value;
    final s = _matrixScale(matrix);
    if (s <= 0) return;

    if (s < _minVerticalZoom) {
      _setVerticalMatrix(
        _verticalMatrix(
          vw * (1.0 - _minVerticalZoom) / 2.0,
          vh * (1.0 - _minVerticalZoom) / 2.0,
          _minVerticalZoom,
        ),
      );
      return;
    }

    if (s >= 1.0) {
      final scaledW = vw * s;
      final scaledH = vh * s;
      final tx = matrix.storage[12];
      final ty = matrix.storage[13];
      final clampedTx = scaledW > vw
          ? tx.clamp(vw - scaledW, 0.0).toDouble()
          : (vw - scaledW) / 2.0;
      final clampedTy = scaledH > vh
          ? ty.clamp(vh - scaledH, 0.0).toDouble()
          : (vh - scaledH) / 2.0;
      if ((tx - clampedTx).abs() > 0.001 || (ty - clampedTy).abs() > 0.001) {
        _setVerticalMatrix(_verticalMatrix(clampedTx, clampedTy, s));
      }
    }
  }

  void _animateVerticalZoomTo(Matrix4 target) {
    _verticalSnapBackTimer?.cancel();
    _verticalZoomController.stop();
    _verticalZoomAnimation = Matrix4Tween(
      begin: _verticalTransform.value,
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _verticalZoomController,
        curve: Curves.easeOutCubic,
      ),
    );
    _verticalZoomController.forward(from: 0.0).then((_) {
      if (!mounted) return;
      setState(() => _verticalScale = _matrixScale(_verticalTransform.value));
    });
  }

  /// Glides a zoomed-out list back to 1x after [delay] (long enough for the
  /// viewer's own pinch glide to be over, see [pinchInertiaDuration]).
  void _scheduleVerticalSnapBack(Duration delay) {
    _verticalSnapBackTimer?.cancel();
    void settle() {
      if (!mounted) return;
      final s = _matrixScale(_verticalTransform.value);
      if (s < kZoomedOutThreshold) {
        _animateVerticalZoomTo(Matrix4.identity());
      } else {
        // The glide carried the zoom back up on its own: nothing to undo.
        setState(() => _verticalScale = s);
      }
    }

    if (delay == Duration.zero) {
      settle();
    } else {
      _verticalSnapBackTimer = Timer(delay, settle);
    }
  }

  void _handleVerticalDoubleTap(TapDownDetails? details) {
    final scale = _matrixScale(_verticalTransform.value);
    if ((scale - 1.0).abs() > 0.01) {
      // Zoomed in or out: glide back to 1x.
      _animateVerticalZoomTo(Matrix4.identity());
      return;
    }

    const targetScale = 3.0;
    final vw = _verticalViewport.width;
    final vh = _verticalViewport.height;
    if (vw <= 0 || vh <= 0) return;

    // Zoom in around the tapped point, kept inside the screen.
    final position = details?.localPosition ?? Offset(vw / 2, vh / 2);
    final tx = (-position.dx * (targetScale - 1.0))
        .clamp(vw - vw * targetScale, 0.0)
        .toDouble();
    final ty = (-position.dy * (targetScale - 1.0))
        .clamp(vh - vh * targetScale, 0.0)
        .toDouble();
    _animateVerticalZoomTo(_verticalMatrix(tx, ty, targetScale));
  }

  /// Puts the vertical list straight back at 1x.
  void _resetVerticalZoom() {
    _verticalSnapBackTimer?.cancel();
    _verticalZoomController.stop();
    if (_verticalTransform.value.isIdentity() && _verticalScale == 1.0) {
      return;
    }
    _setVerticalMatrix(Matrix4.identity());
    if (mounted) setState(() => _verticalScale = 1.0);
  }

  Widget _buildVerticalReader(BoxConstraints constraints) {
    final viewport = Size(constraints.maxWidth, constraints.maxHeight);
    if (viewport != _verticalViewport) {
      final resized = _verticalViewport != Size.zero;
      _verticalViewport = viewport;
      if (resized && !_verticalTransform.value.isIdentity()) {
        // A zoom is only valid for the screen it was made on.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resetVerticalZoom();
        });
      }
    }

    final list = ValueListenableBuilder<bool>(
      valueListenable: _swipeLocked,
      builder: (context, locked, _) => ListView.builder(
        controller: _verticalController,
        physics: locked
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics(),
        itemCount: widget.pages.length,
        itemBuilder: (context, i) => FutureBuilder<void>(
          future: _ensureLoaded(i),
          builder: (context, _) {
            final size = _dimensions[i];
            final height = size == null || size.$1 <= 0
                ? constraints.maxHeight
                : constraints.maxWidth * size.$2 / size.$1;
            return SizedBox(
              key: _verticalPageKeys[i],
              height: height,
              // Zoom belongs to the whole list (see above), not to a page.
              child: _buildComicPage(
                i,
                imageFit: BoxFit.fitWidth,
                enableZoom: false,
              ),
            );
          },
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTapDown: (details) => _verticalDoubleTapDetails = details,
      onDoubleTap: () => _handleVerticalDoubleTap(_verticalDoubleTapDetails),
      child: InteractiveViewer(
        transformationController: _verticalTransform,
        minScale: _minVerticalZoom,
        maxScale: MediaViewerConstants.maxImageZoom,
        interactionEndFrictionCoefficient: kZoomInteractionEndFriction,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        clipBehavior: Clip.none,
        // One finger scrolls the list; it only pans sideways once zoomed in.
        panEnabled: _verticalScale > 1.01,
        panAxis: PanAxis.free,
        onInteractionStart: (details) {
          // A new touch cancels a pending spring back.
          _verticalSnapBackTimer?.cancel();
          if (details.pointerCount >= 2) _verticalZoomController.stop();
        },
        onInteractionUpdate: (details) {
          _verticalScale = _matrixScale(_verticalTransform.value);
        },
        onInteractionEnd: (details) {
          final s = _matrixScale(_verticalTransform.value);
          setState(() => _verticalScale = s);
          // Pinched out: glide back to 1x instead of settling zoomed out.
          if (s < kZoomedOutThreshold) {
            _scheduleVerticalSnapBack(pinchInertiaDuration(details));
          }
        },
        child: list,
      ),
    );
  }

  void _setMode(String mode) {
    if (_mode == mode) return;
    _resetVerticalZoom();
    setState(() => _mode = mode);
    if (mode == 'vertical') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_verticalController.hasClients) {
          _verticalController.jumpTo(_estimatedVerticalOffset(_index));
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _controller.jumpToPage(_slideForPage(_index));
        }
      });
    }
    unawaited(_saveState());
  }

  Future<void> _toggleBookmark() async {
    setState(() {
      if (_bookmarks.any((b) => b.position == _index)) {
        _bookmarks = _bookmarks
            .where((b) => b.position != _index)
            .toList(growable: false);
      } else {
        _bookmarks = [..._bookmarks, BookReaderBookmark(_index)]
          ..sort((a, b) => a.position.compareTo(b.position));
      }
    });
    await _saveState();
  }

  Widget _carouselThumbnail(
    BuildContext context,
    int index,
    String fileName,
  ) => FutureBuilder<void>(
    future: _ensureLoaded(index),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Icon(Icons.broken_image_outlined));
      }
      final bytes = FullResImageCache.get(_cacheContainer, _cacheKey(index));
      if (bytes == null) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheWidth: 240,
        gaplessPlayback: true,
      );
    },
  );

  void _toggleCarousel([bool? visible]) {
    final next = visible ?? !_carouselVisible;
    if (next == _carouselVisible) return;
    HapticFeedback.selectionClick();
    setState(() => _carouselVisible = next);
    unawaited(_saveState());
  }

  Future<void> _showReaderSettings() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(context.l10n.bookReaderReadingModeTitle),
              trailing: DropdownButton<String>(
                value: _mode,
                items: [
                  DropdownMenuItem(
                    value: 'single',
                    child: Text(context.l10n.comicReaderModeSinglePage),
                  ),
                  DropdownMenuItem(
                    value: 'spread',
                    child: Text(context.l10n.comicReaderModeTwoPageSpread),
                  ),
                  DropdownMenuItem(
                    value: 'vertical',
                    child: Text(
                      context.l10n.playlistScrollVerticalContinuousLabel,
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _setMode(value);
                  setSheetState(() {});
                },
              ),
            ),
            ListTile(
              title: Text(context.l10n.bookReaderTextDirectionLabel),
              trailing: DropdownButton<bool>(
                value: _rtl,
                items: [
                  DropdownMenuItem(
                    value: false,
                    child: Text(context.l10n.comicReadingDirectionLtr),
                  ),
                  DropdownMenuItem(
                    value: true,
                    child: Text(context.l10n.comicReadingDirectionRtl),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _rtl = value);
                  unawaited(_saveState());
                  setSheetState(() {});
                },
              ),
            ),
            SwitchListTile(
              title: Text(context.l10n.thumbnailCarouselTooltip),
              subtitle: Text(context.l10n.comicReaderCarouselScrubberSubtitle),
              value: _carouselVisible,
              onChanged: (value) {
                _toggleCarousel(value);
                setSheetState(() {});
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );

  Widget _pageScrubber(BuildContext context) {
    final total = widget.pages.length;
    final value = total <= 1 ? 0.0 : _index / (total - 1);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xE6121212),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                '${_index + 1}',
                style: const TextStyle(color: Colors.white),
              ),
              Expanded(
                child: Slider(
                  value: _scrubValue ?? value,
                  onChangeStart: total <= 1
                      ? null
                      : (_) => setState(() => _scrubValue = value),
                  onChanged: total <= 1
                      ? null
                      : (v) => setState(() => _scrubValue = v),
                  onChangeEnd: total <= 1
                      ? null
                      : (v) {
                          setState(() => _scrubValue = null);
                          _goTo((v * (total - 1)).round());
                        },
                ),
              ),
              Text('$total', style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBookmarks() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(context.l10n.bookmarkBarSectionHeader)),
            if (_bookmarks.isEmpty)
              ListTile(title: Text(context.l10n.noBookmarksYet)),
            for (final bookmark in _bookmarks)
              ListTile(
                leading: const Icon(Icons.bookmark),
                title: Text(
                  '${bookmark.position + 1} / ${widget.pages.length}',
                ),
                onTap: () => Navigator.of(sheetContext).pop(bookmark.position),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _goTo(picked);
  }

  void _setUiVisible(bool visible) {
    if (_showUi == visible) return;
    setState(() => _showUi = visible);
    SystemChrome.setEnabledSystemUIMode(
      visible ? SystemUiMode.manual : SystemUiMode.immersiveSticky,
      overlays: visible ? SystemUiOverlay.values : null,
    );
  }

  // Swipe-to-next-page versus pinch-zoom: lock the pager the instant a second
  // finger lands (before the zoom recogniser can lose the gesture arena to the
  // pager's drag) and while the page is zoomed. Same rule as the media viewer.
  void _onPointerDown(PointerDownEvent event) {
    _pointers.add(event.pointer);
    _updateSwipeLock();
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    _updateSwipeLock();
  }

  void _onZoomChanged(bool allowSwipe) {
    _zoomLock = !allowSwipe;
    _updateSwipeLock();
  }

  void _updateSwipeLock() {
    final locked = _pointers.length >= 2 || _zoomLock;
    if (_swipeLocked.value == locked) return;
    // Page widgets report zoom from build/didUpdateWidget; notifying listeners
    // then would rebuild an ancestor mid-frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _swipeLocked.value = _pointers.length >= 2 || _zoomLock;
      });
    } else {
      _swipeLocked.value = locked;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    final l10n = context.l10n;
    final total = widget.pages.length;

    if (!_ready) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white54)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _onPointerDown,
                  onPointerUp: _onPointerEnd,
                  onPointerCancel: _onPointerEnd,
                  child: _mode == 'vertical'
                      ? _buildVerticalReader(constraints)
                      : ValueListenableBuilder<bool>(
                          valueListenable: _swipeLocked,
                          builder: (context, locked, _) => Center(
                            child: SizedBox(
                              width: math.max(1.0, constraints.maxWidth.floorToDouble()),
                              height: math.max(1.0, constraints.maxHeight.floorToDouble()),
                              child: PageView.builder(
                                controller: _controller,
                                reverse: _rtl,
                                physics: locked
                                    ? const NeverScrollableScrollPhysics()
                                    : const PageScrollPhysics(),
                                itemCount: _mode == 'spread'
                                    ? _spreadStarts.length
                                    : total,
                                onPageChanged: _onPageChanged,
                                itemBuilder: (context, page) {
                              if (_mode != 'spread') {
                                return _buildComicPage(page);
                              }
                              final first = _spreadStarts[page];
                              final indices = [
                                first,
                                if (first > 0 && first + 1 < total) first + 1,
                              ];
                              return Row(
                                textDirection: _rtl
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                                children: [
                                  for (final index in indices)
                                    Expanded(child: _buildComicPage(index)),
                                  if (indices.length == 1)
                                    const Expanded(child: SizedBox.shrink()),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _FadingBar(
              visible: _showUi,
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    const BackButton(color: Colors.white),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.bookmarkBarSectionHeader,
                      icon: const Icon(
                        Icons.bookmarks_outlined,
                        color: Colors.white,
                      ),
                      onPressed: _showBookmarks,
                    ),
                    IconButton(
                      tooltip: context.l10n.bookmarkAction,
                      icon: Icon(
                        _bookmarks.any((b) => b.position == _index)
                            ? Icons.bookmark
                            : Icons.bookmark_add_outlined,
                        color: Colors.white,
                      ),
                      onPressed: _toggleBookmark,
                    ),
                    IconButton(
                      tooltip: l10n.moreOptionsTooltip,
                      icon: const Icon(Icons.settings, color: Colors.white),
                      onPressed: _showReaderSettings,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _FadingBar(
              visible: _showUi,
              child: _carouselVisible
                  ? PlaylistCarouselOverlay(
                      key: const ValueKey('comic-carousel-visible'),
                      container: _cacheContainer,
                      playlist: widget.pages,
                      currentIndex: _index,
                      thumbnailQuality: ThumbnailQuality.defaultQuality,
                      thumbnailCacheMode: ThumbnailCacheMode.disabled,
                      thumbnailBuilder: _carouselThumbnail,
                      showItemNumbers: true,
                      alwaysShowScrubber: true,
                      backgroundColor: const Color(0xF0121212),
                      onSelect: _goTo,
                    )
                  : _pageScrubber(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComicPage(
    int i, {
    BoxFit imageFit = BoxFit.contain,
    bool enableZoom = true,
  }) => _ComicPage(
        key: ValueKey('${widget.token}_${_mode}_$i'),
        load: () => _ensureLoaded(i),
        cacheKey: _cacheKey(i),
        container: _cacheContainer,
        imageFit: imageFit,
        enableZoom: enableZoom,
        isActive: i == _index || (_mode == 'spread' && i == _index + 1),
        showUi: _showUi,
        onToggleUi: _setUiVisible,
        onEdgeTap: _onEdgeTap,
        onZoomChanged: _onZoomChanged,
      );
}

class _FadingBar extends StatelessWidget {
  final bool visible;
  final Widget child;
  const _FadingBar({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: visible ? 1 : 0,
    duration: const Duration(milliseconds: 180),
    child: IgnorePointer(
      ignoring: !visible,
      child: ColoredBox(color: const Color(0x99000000), child: child),
    ),
  );
}

/// One page: waits until its bytes are in the cache, then shows them with the
/// image viewer's zoomable page widget.
class _ComicPage extends StatefulWidget {
  final Future<void> Function() load;
  final String cacheKey;
  final MountedContainer container;
  final BoxFit imageFit;

  /// Off in vertical mode, where the reader zooms the whole list instead.
  final bool enableZoom;
  final bool isActive;
  final bool showUi;
  final ValueChanged<bool> onToggleUi;
  final ValueChanged<bool> onEdgeTap;
  final ValueChanged<bool> onZoomChanged;

  const _ComicPage({
    super.key,
    required this.load,
    required this.cacheKey,
    required this.container,
    this.imageFit = BoxFit.contain,
    this.enableZoom = true,
    required this.isActive,
    required this.showUi,
    required this.onToggleUi,
    required this.onEdgeTap,
    required this.onZoomChanged,
  });

  @override
  State<_ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends State<_ComicPage> {
  late Future<void> _future = widget.load();

  void _retry() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.comicPageLoadFailed,
                  style: const TextStyle(color: Colors.white70),
                ),
                TextButton(
                  onPressed: _retry,
                  child: Text(context.l10n.retryButton),
                ),
              ],
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          );
        }
        return ImagePageItem(
          fileName: widget.cacheKey,
          prefetchedBytes: null,
          container: widget.container,
          imageFit: widget.imageFit,
          rotationQuarterTurns: 0,
          enableZoom: widget.enableZoom,
          // Pinching a page out springs it back to 1x.
          snapBackOnZoomOut: true,
          showUI: widget.showUi,
          isActive: widget.isActive,
          onToggleUI: widget.onToggleUi,
          onEdgeTap: widget.onEdgeTap,
          onZoomChanged: widget.onZoomChanged,
        );
      },
    );
  }
}
