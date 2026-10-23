// "Go to this bookmark", handed from wherever it was tapped (the navigation
// drawer) to the file browser that shows the bookmark's vault.
//
// A request rather than a method call because the drawer has no handle on a
// browser: there may be several tabs, the vault may not be open in any of
// them yet, and the drawer is built in more than one place. The drawer sets
// the request, then asks for the vault to be opened exactly as a tap on the
// vault itself would; the browser that ends up showing that vault takes the
// request and navigates. A tab that is already open does so immediately, so
// its history and state are kept; a tab opened for the occasion does so once
// it has finished loading.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';

class BookmarkNavigationRequest {
  /// How long a request stays valid. If the vault never opened (the unlock was
  /// cancelled, say), a stale request must not hijack a later, unrelated open.
  static const Duration lifetime = Duration(seconds: 10);

  final int volId;
  final VaultBookmark bookmark;
  final DateTime requestedAt;

  BookmarkNavigationRequest({
    required this.volId,
    required this.bookmark,
    DateTime? requestedAt,
  }) : requestedAt = requestedAt ?? DateTime.now();

  bool isExpiredAt(DateTime now) => now.difference(requestedAt) > lifetime;
}

class BookmarkNavigationRequests extends Notifier<BookmarkNavigationRequest?> {
  @override
  BookmarkNavigationRequest? build() => null;

  void request(int volId, VaultBookmark bookmark) {
    state = BookmarkNavigationRequest(volId: volId, bookmark: bookmark);
  }

  /// Hands the pending request to the browser of [volId] and clears it.
  /// Returns null when there is none for that vault, or it has expired.
  BookmarkNavigationRequest? take(int volId) {
    final pending = state;
    if (pending == null) return null;
    if (pending.isExpiredAt(DateTime.now())) {
      state = null;
      return null;
    }
    if (pending.volId != volId) return null;
    state = null;
    return pending;
  }
}

/// Not autoDispose: the request is set before the browser that will take it
/// exists, so nothing is watching it yet at that moment.
final bookmarkNavigationRequestsProvider =
    NotifierProvider<BookmarkNavigationRequests, BookmarkNavigationRequest?>(
      BookmarkNavigationRequests.new,
    );
