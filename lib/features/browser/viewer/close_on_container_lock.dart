import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

/// Closes a viewer that is a route of its own once the vault it shows is gone.
///
/// Locking a vault wipes its session, but a text or Markdown screen keeps the
/// decrypted text it loaded (and an archive preview its plaintext staging
/// file) for as long as it stays open. The browser's tab host only closes
/// *tabs* ([BrowserTabsHost] -> closeByVolId), not pushed viewer routes, so
/// these screens have to close themselves.
///
/// The route is removed with [NavigatorState.removeRoute], not popped, after
/// anything above it (a dialog, another screen) has been popped: that does not
/// consult a [PopScope], so an unsaved-changes prompt cannot keep the plaintext
/// on screen. Nothing could be saved into a locked vault anyway. This is the
/// same sequence the video editor uses when its vault is locked.
///
/// "Gone" is the same pair of events the tab host reacts to: the vault being
/// locked, or its USB drive being detached.
mixin CloseOnContainerLock<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  VaultEngineEvents? _lockEvents;

  /// The volume whose lock should close this screen.
  int get watchedVolId;

  /// Call from `initState`, after `super.initState()`.
  void startClosingOnContainerLock() {
    final events = ref.read(vaultEngineEventsProvider);
    _lockEvents = events;
    events.addContainerLockedListener(_onWatchedVolumeGone);
    events.addUsbContainerDetachedListener(_onWatchedVolumeGone);
  }

  /// Call from `dispose`, before `super.dispose()`.
  void stopClosingOnContainerLock() {
    _lockEvents?.removeContainerLockedListener(_onWatchedVolumeGone);
    _lockEvents?.removeUsbContainerDetachedListener(_onWatchedVolumeGone);
    _lockEvents = null;
  }

  void _onWatchedVolumeGone(int volId) {
    if (volId != watchedVolId || !mounted) return;
    final route = ModalRoute.of(context);
    final navigator = Navigator.maybeOf(context);
    if (route == null || navigator == null) return;
    _closeRoute(navigator, route);
  }
}

/// Closes [route] and everything above it. Runs at once when no frame is being
/// built (an idle app, or one in the background where no frame is scheduled
/// at all), otherwise right after the current frame.
void _closeRoute(NavigatorState navigator, Route<dynamic> route) {
  void close() {
    // popUntil only stops at [route] while it is on the stack, so it has to be
    // checked first: otherwise it would pop every route down to the root.
    if (!navigator.mounted || !route.isActive) return;
    navigator.popUntil((candidate) => candidate == route);
    if (route.isActive) navigator.removeRoute(route);
  }

  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.idle ||
      phase == SchedulerPhase.postFrameCallbacks) {
    close();
  } else {
    WidgetsBinding.instance.addPostFrameCallback((_) => close());
  }
}

/// Pushes [route] and removes it again if volume [volId] is locked (or its USB
/// drive detached) while it is open. Completes when the route is gone, however
/// it went, so callers can keep their cleanup (deleting a plaintext staging
/// file) after the `await`.
///
/// For viewers that show a copy of something from a vault under a different
/// container -- an archive entry is previewed through a throw-away local
/// container -- so the screen itself cannot tell which vault it came from.
Future<T?> pushClosingWhenVolumeGone<T>(
  BuildContext context,
  VaultEngineEvents events,
  int volId,
  Route<T> route,
) {
  final navigator = Navigator.of(context);
  void onGone(int goneVolId) {
    if (goneVolId != volId) return;
    _closeRoute(navigator, route);
  }

  events.addContainerLockedListener(onGone);
  events.addUsbContainerDetachedListener(onGone);
  return navigator.push<T>(route).whenComplete(() {
    events.removeContainerLockedListener(onGone);
    events.removeUsbContainerDetachedListener(onGone);
  });
}
