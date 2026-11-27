import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';
import 'package:vaultexplorer/features/browser/controllers/bookmark_navigation_request.dart';

void main() {
  const downloads = VaultBookmark('Users/me/Downloads', isDir: true);

  late ProviderContainer container;
  late BookmarkNavigationRequests requests;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    requests = container.read(bookmarkNavigationRequestsProvider.notifier);
  });

  group('peek', () {
    test('shows the pending request for that vault and leaves it pending', () {
      requests.request(7, downloads);

      final peeked = requests.peek(7);

      expect(peeked, isNotNull);
      expect(peeked!.bookmark, same(downloads));
      expect(requests.peek(7), same(peeked));
      expect(container.read(bookmarkNavigationRequestsProvider), same(peeked));
    });

    test('is null when nothing is pending', () {
      expect(requests.peek(7), isNull);
    });

    test('is null for another vault, and does not disturb the request', () {
      requests.request(7, downloads);

      expect(requests.peek(8), isNull);
      expect(requests.peek(7), isNotNull);
    });

    test('leaves the request for take to hand over', () {
      requests.request(7, downloads);

      requests.peek(7);
      final taken = requests.take(7);

      expect(taken, isNotNull);
      expect(taken!.bookmark, same(downloads));
      expect(requests.peek(7), isNull);
    });
  });

  test('a request expires once its lifetime has passed', () {
    final start = DateTime(2026, 1, 1);
    final request = BookmarkNavigationRequest(
      volId: 7,
      bookmark: downloads,
      requestedAt: start,
    );

    expect(
      request.isExpiredAt(start.add(BookmarkNavigationRequest.lifetime)),
      isFalse,
    );
    expect(
      request.isExpiredAt(
        start
            .add(BookmarkNavigationRequest.lifetime)
            .add(const Duration(seconds: 1)),
      ),
      isTrue,
    );
  });
}
