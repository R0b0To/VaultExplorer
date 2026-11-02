import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';

/// What a drop does with the dragged items.
enum BrowserDropMode { copy, move }

@immutable
class BrowserDragSessionState {
  /// The viewport the active drag started in; null when nothing is dragged.
  final TabId? sourceTabId;

  /// Where the active drag started (global coordinates).
  final Offset? startPosition;

  const BrowserDragSessionState({this.sourceTabId, this.startPosition});

  bool get isActive => sourceTabId != null;

  /// True for every viewport other than the one a drag started in. While a
  /// drag is active those viewports only behave as drop targets.
  bool isLockedFor(TabId tab) => sourceTabId != null && sourceTabId != tab;
}

/// The one drag of browser items that may exist at a time.
///
/// Each tile owns its own long-press recognizer, so without a shared gate two
/// fingers on two tiles (or two fingers on one tile) each start a drag. Tiles
/// ask [tryBegin] before starting; the first one wins and every other attempt
/// is refused until the session ends.
///
/// Flutter only reports a drag's end to a [Draggable] that is still mounted,
/// so a source tile that disappears mid-drag (rotation, tab closed) would
/// leave the session -- and the cross-pane lock -- stuck. A global pointer
/// route therefore also ends it once every finger is up.
class BrowserDragSession extends Notifier<BrowserDragSessionState> {
  /// Latest pointer position of the active drag, for feedback placement. Kept
  /// outside [state] so moving the finger does not rebuild any viewport.
  final ValueNotifier<Offset?> pointer = ValueNotifier<Offset?>(null);

  final Set<int> _downPointers = <int>{};
  bool _routeAttached = false;

  @override
  BrowserDragSessionState build() {
    _attachRoute();
    ref.onDispose(() {
      _detachRoute();
      _downPointers.clear();
      // [pointer] is deliberately not disposed: a rebuilt provider reuses
      // this notifier instance.
      pointer.value = null;
    });
    return const BrowserDragSessionState();
  }

  void _attachRoute() {
    if (_routeAttached) return;
    try {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointerEvent);
      _routeAttached = true;
    } on FlutterError {
      // No gesture binding (plain unit tests): the safety net is unavailable
      // there, everything else still works.
    }
  }

  void _detachRoute() {
    if (!_routeAttached) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointerEvent);
    _routeAttached = false;
  }

  void _onPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      _downPointers.add(event.pointer);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _downPointers.remove(event.pointer);
      if (_downPointers.isEmpty && state.isActive) {
        // After this event has been fully dispatched, so a normal drag end
        // (which ends the session itself) is never pre-empted.
        scheduleMicrotask(end);
      }
    }
  }

  /// Claims the single drag slot for [source]. False when a drag is already
  /// in progress.
  bool tryBegin(TabId source, Offset position) {
    if (state.isActive) return false;
    state = BrowserDragSessionState(
      sourceTabId: source,
      startPosition: position,
    );
    pointer.value = position;
    return true;
  }

  void updatePointer(Offset position) => pointer.value = position;

  /// Releases the slot. Safe to call repeatedly.
  void end() {
    if (!state.isActive) return;
    state = const BrowserDragSessionState();
    pointer.value = null;
  }
}

final browserDragSessionProvider =
    NotifierProvider<BrowserDragSession, BrowserDragSessionState>(
      BrowserDragSession.new,
    );

/// Items a finished drop created in some folders, announced so whichever
/// viewport shows one of those folders can flash them and scroll one into
/// view.
@immutable
class BrowserDropReveal {
  final int volId;

  /// Bumped for every announcement so an identical one still counts as new.
  final int token;

  /// Item names to reveal, by the folder (path inside the volume) they are in.
  final Map<String, Set<String>> namesByDir;

  const BrowserDropReveal({
    required this.volId,
    required this.token,
    required this.namesByDir,
  });
}

class BrowserDropRevealNotifier extends Notifier<BrowserDropReveal?> {
  int _token = 0;

  @override
  BrowserDropReveal? build() => null;

  void publish({
    required int volId,
    required Map<String, Set<String>> namesByDir,
  }) {
    final nonEmpty = {
      for (final e in namesByDir.entries)
        if (e.value.isNotEmpty) e.key: Set<String>.unmodifiable(e.value),
    };
    if (nonEmpty.isEmpty) return;
    state = BrowserDropReveal(
      volId: volId,
      token: ++_token,
      namesByDir: Map.unmodifiable(nonEmpty),
    );
  }
}

final browserDropRevealProvider =
    NotifierProvider<BrowserDropRevealNotifier, BrowserDropReveal?>(
      BrowserDropRevealNotifier.new,
    );
