import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/image_page_item.dart';

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
  final String token;

  /// Archive entry names in reading order (see `comicPageNames`).
  final List<String> pages;

  const ComicReaderScreen({
    super.key,
    required this.container,
    required this.title,
    required this.token,
    required this.pages,
  });

  @override
  ConsumerState<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends ConsumerState<ComicReaderScreen> {
  late final VaultBookApi _api;
  late final VaultEngineEvents _events;
  bool _locked = false;
  final PageController _controller = PageController();

  /// Page bytes live in the shared in-memory image cache under this throwaway
  /// container identity, so they never collide with real vault files.
  late final MountedContainer _cacheContainer = buildLocalStorageContainer(
    rootPath: '',
    displayName: widget.title,
    readOnly: true,
  );

  final Map<int, Future<void>> _inFlight = {};
  final ValueNotifier<bool> _swipeLocked = ValueNotifier<bool>(false);
  final Set<int> _pointers = <int>{};
  bool _zoomLock = false;

  int _index = 0;
  double? _dragValue;
  bool _showUi = true;
  bool _rtl = false;

  @override
  void initState() {
    super.initState();
    _api = ref.read(vaultBookApiProvider);
    _events = ref.read(vaultEngineEventsProvider);
    _events.addContainerLockedListener(_onContainerLocked);
    _prefetch(0);
  }

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
    _controller.dispose();
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
  }

  void _prefetch(int center) {
    for (final i in [center, center + 1, center - 1, center + 2]) {
      if (i < 0 || i >= widget.pages.length) continue;
      unawaited(_ensureLoaded(i).catchError((Object _) {}));
    }
  }

  void _onPageChanged(int i) {
    setState(() {
      _index = i;
      _dragValue = null;
    });
    // A new page always starts un-zoomed.
    _zoomLock = false;
    _updateSwipeLock();
    _prefetch(i);
  }

  void _goTo(int i) {
    if (i < 0 || i >= widget.pages.length || !_controller.hasClients) return;
    unawaited(
      _controller.animateToPage(
        i,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// [rightEdge] true = the viewer's right tap zone. Reading right to left
  /// the next page is on the left, so the zones swap meaning.
  void _onEdgeTap(bool rightEdge) {
    final forward = _rtl ? !rightEdge : rightEdge;
    _goTo(_index + (forward ? 1 : -1));
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
      return const Scaffold(backgroundColor: Colors.black, body: SizedBox.expand());
    }
    final l10n = context.l10n;
    final total = widget.pages.length;
    final shown = (_dragValue ?? _index.toDouble()).round().clamp(0, total - 1);
    // A one-page comic still needs a valid (if disabled) slider range.
    final sliderMax = total > 1 ? (total - 1).toDouble() : 1.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onPointerDown,
              onPointerUp: _onPointerEnd,
              onPointerCancel: _onPointerEnd,
              child: ValueListenableBuilder<bool>(
                valueListenable: _swipeLocked,
                builder: (context, locked, _) => PageView.builder(
                  controller: _controller,
                  reverse: _rtl,
                  physics: locked
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: total,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, i) => _ComicPage(
                    key: ValueKey('${widget.token}_$i'),
                    load: () => _ensureLoaded(i),
                    cacheKey: _cacheKey(i),
                    container: _cacheContainer,
                    isActive: i == _index,
                    showUi: _showUi,
                    onToggleUi: _setUiVisible,
                    onEdgeTap: _onEdgeTap,
                    onZoomChanged: _onZoomChanged,
                  ),
                ),
              ),
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
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      tooltip: _rtl
                          ? l10n.comicReadingDirectionRtl
                          : l10n.comicReadingDirectionLtr,
                      icon: Icon(
                        _rtl ? Icons.format_textdirection_r_to_l : Icons.format_textdirection_l_to_r,
                        color: Colors.white,
                      ),
                      onPressed: () => setState(() => _rtl = !_rtl),
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
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        // The slider runs the same way the pages do.
                        child: Directionality(
                          textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
                          child: Slider(
                            min: 0,
                            max: sliderMax,
                            divisions: total > 1 ? total - 1 : null,
                            value: shown.toDouble().clamp(0.0, sliderMax),
                            onChanged: total > 1 ? (v) => setState(() => _dragValue = v) : null,
                            onChangeEnd: (v) {
                              setState(() => _dragValue = null);
                              _goTo(v.round());
                            },
                          ),
                        ),
                      ),
                      Text(
                        '${shown + 1} / $total',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
                const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                const SizedBox(height: 12),
                Text(
                  context.l10n.comicPageLoadFailed,
                  style: const TextStyle(color: Colors.white70),
                ),
                TextButton(onPressed: _retry, child: Text(context.l10n.retryButton)),
              ],
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: Colors.white54));
        }
        return ImagePageItem(
          fileName: widget.cacheKey,
          prefetchedBytes: null,
          container: widget.container,
          imageFit: BoxFit.contain,
          rotationQuarterTurns: 0,
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
