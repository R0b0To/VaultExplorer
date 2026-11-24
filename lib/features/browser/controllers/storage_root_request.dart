// "Go back to the root of this storage", handed from the navigation drawer to
// the file browser that is already showing it.
//
// Tapping the storage you are already inside used to do nothing. Like the
// bookmark request (see bookmark_navigation_request.dart) this is a request
// rather than a method call, because the drawer has no handle on a browser:
// there may be several tabs and the drawer is built in more than one place.
// The browser of that storage in front takes the request and jumps to its
// root, which keeps the folders it came through as forward history.
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StorageRootRequest {
  /// Short: the browser is already open, so a request nobody took belongs to
  /// a tap that went nowhere and must not fire on a later, unrelated open.
  static const Duration lifetime = Duration(seconds: 3);

  final int volId;
  final DateTime requestedAt;

  StorageRootRequest({required this.volId, DateTime? requestedAt})
    : requestedAt = requestedAt ?? DateTime.now();

  bool isExpiredAt(DateTime now) => now.difference(requestedAt) > lifetime;
}

class StorageRootRequests extends Notifier<StorageRootRequest?> {
  @override
  StorageRootRequest? build() => null;

  void request(int volId) {
    state = StorageRootRequest(volId: volId);
  }

  /// Hands the pending request to the browser of [volId] and clears it.
  /// Returns false when there is none for that storage, or it has expired.
  bool take(int volId) {
    final pending = state;
    if (pending == null) return false;
    if (pending.isExpiredAt(DateTime.now())) {
      state = null;
      return false;
    }
    if (pending.volId != volId) return false;
    state = null;
    return true;
  }
}

final storageRootRequestsProvider =
    NotifierProvider<StorageRootRequests, StorageRootRequest?>(
      StorageRootRequests.new,
    );
