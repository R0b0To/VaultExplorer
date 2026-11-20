import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/listing_job.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';

MountedContainer _testContainer() => MountedContainer(
  volId: 1,
  uri: 'file:///vault1.hc',
  displayName: 'Vault 1',
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000000,
  freeSpace: 500000,
  containerFormat: 'veracrypt',
);

/// One listing in flight, driven by the test.
class _FakeListing {
  _FakeListing(this.path, this._onPartial);

  final String path;
  final void Function(List<RawEntry>)? _onPartial;
  final Completer<ParsedDirectoryListing?> completer =
      Completer<ParsedDirectoryListing?>();
  bool cancelled = false;

  static List<RawEntry> _parse(List<String> wire) => RawEntry.parseAll(wire);

  void partial(List<String> wire) => _onPartial?.call(_parse(wire));

  void finish(List<String> wire) => completer.complete(
    ParsedDirectoryListing(_parse(wire), preSortedByNameAsc: true),
  );

  void fail() => completer.complete(null);
}

class _FakeFileIo extends VaultFileIoApi {
  _FakeFileIo() : super(const MethodChannel('test/progressive-listing'));

  final List<_FakeListing> listings = <_FakeListing>[];

  @override
  ListingJob<ParsedDirectoryListing> startDirectoryListingForBrowser(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
    void Function(List<RawEntry> partial)? onPartial,
  }) {
    final listing = _FakeListing(dirPath, onPartial);
    listings.add(listing);
    return ListingJob<ParsedDirectoryListing>(listing.completer.future, () {
      listing.cancelled = true;
      if (!listing.completer.isCompleted) listing.completer.complete(null);
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tab = TabId(1);
  const big = RawEntry(name: 'Big', isDir: true, sizeBytes: 0, modifiedSecs: 0);
  late _FakeFileIo io;
  late ProviderContainer container;

  FileBrowserNavigation notifier() =>
      container.read(fileBrowserNavigationProvider(tab).notifier);
  FileBrowserNavigationState state() =>
      container.read(fileBrowserNavigationProvider(tab));

  ProviderContainer makeContainer() => ProviderContainer(
    overrides: [vaultFileIoApiProvider.overrideWith((ref) => io)],
  );

  setUp(() {
    io = _FakeFileIo();
    container = makeContainer();
    // Keep the notifier alive for the whole test.
    container.listen(fileBrowserNavigationProvider(tab), (_, _) {});
    notifier().initRoot(rootLabel: 'Device');
  });

  tearDown(() => container.dispose());

  group('progressive listing in the navigation controller', () {
    test('the first part of a big folder is shown while the rest is read', () async {
      notifier().enterDirectory(big, newPath: 'Big');
      final load = notifier().loadDirectoryContents(_testContainer(), 'Big');

      expect(state().currentItems, isEmpty);
      expect(state().isLoading, isTrue);
      expect(state().isListingPartial, isFalse);

      io.listings.single.partial(['D|0|1|Aa', 'F|1|1|a1.jpg', 'F|1|1|a2.jpg']);
      expect(state().currentItems.map((e) => e.name), ['Aa', 'a1.jpg', 'a2.jpg']);
      expect(state().preSortedByNameAsc, isTrue);
      // Still "loading": reveals and scroll-to wait for the finished listing.
      expect(state().isLoading, isTrue);
      expect(state().isListingPartial, isTrue);

      io.listings.single.partial([
        'D|0|1|Aa',
        'D|0|1|Bb',
        'F|1|1|a1.jpg',
        'F|1|1|a2.jpg',
        'F|1|1|a3.jpg',
      ]);
      expect(state().currentItems, hasLength(5));

      io.listings.single.finish([
        'D|0|1|Aa',
        'D|0|1|Bb',
        'F|1|1|a1.jpg',
        'F|1|1|a2.jpg',
        'F|1|1|a3.jpg',
        'F|1|1|a4.jpg',
      ]);
      await load;
      expect(state().currentItems, hasLength(6));
      expect(state().isLoading, isFalse);
      expect(state().isListingPartial, isFalse);
      expect(state().needsRefresh, isFalse);
    });

    test('a folder already showing its contents ignores partials', () async {
      notifier().enterDirectory(big, newPath: 'Big');
      final first = notifier().loadDirectoryContents(_testContainer(), 'Big');
      io.listings.last.finish(['F|1|1|a.jpg', 'F|1|1|b.jpg', 'F|1|1|c.jpg']);
      await first;
      final shown = state().currentItems;
      expect(shown, hasLength(3));

      // A refresh: its smaller early snapshot must not replace the full list.
      final refresh = notifier().loadDirectoryContents(
        _testContainer(),
        'Big',
        refresh: true,
      );
      io.listings.last.partial(['F|1|1|a.jpg']);
      expect(identical(state().currentItems, shown), isTrue);
      expect(state().isListingPartial, isFalse);

      io.listings.last.finish(['F|1|1|a.jpg', 'F|1|1|b.jpg', 'F|1|1|c.jpg']);
      await refresh;
      expect(state().currentItems, hasLength(3));
    });

    test('a newer load stops the one still reading', () async {
      notifier().enterDirectory(big, newPath: 'Big');
      final slow = notifier().loadDirectoryContents(_testContainer(), 'Big');
      final reading = io.listings.single;
      expect(reading.cancelled, isFalse);

      notifier().navigateUp();
      final parent = notifier().loadDirectoryContents(_testContainer(), '');
      expect(reading.cancelled, isTrue);

      io.listings.last.finish(['D|0|1|Big']);
      await parent;
      await slow; // the cancelled load ends quietly
      expect(state().currentItems.map((e) => e.name), ['Big']);
      expect(state().isListingPartial, isFalse);
    });

    test('a partial for a folder the user has already left is ignored', () async {
      notifier().enterDirectory(big, newPath: 'Big');
      unawaited(notifier().loadDirectoryContents(_testContainer(), 'Big'));
      final reading = io.listings.single;

      notifier().navigateUp();
      reading.partial(['F|1|1|late.jpg']);

      expect(state().currentDirPath, '');
      expect(state().currentItems.any((e) => e.name == 'late.jpg'), isFalse);
      expect(state().isListingPartial, isFalse);
    });

    test('a listing that fails after a partial clears the progress state', () async {
      notifier().enterDirectory(big, newPath: 'Big');
      final load = notifier().loadDirectoryContents(_testContainer(), 'Big');
      io.listings.single.partial(['F|1|1|a.jpg', 'F|1|1|b.jpg']);
      expect(state().isListingPartial, isTrue);

      io.listings.single.fail();
      await load;
      expect(state().isListingPartial, isFalse);
      expect(state().isLoading, isFalse);
      expect(state().needsRefresh, isTrue);
      expect(state().currentItems, isEmpty);
    });

    test('a failed listing is not remembered, so the folder is not partial next time', () async {
      notifier().enterDirectory(big, newPath: 'Big');
      final load = notifier().loadDirectoryContents(_testContainer(), 'Big');
      io.listings.single.partial(['F|1|1|a.jpg']);
      io.listings.single.fail();
      await load;

      notifier().navigateUp();
      notifier().enterDirectory(big, newPath: 'Big');
      // Nothing cached to show, so it starts empty and loading again.
      expect(state().currentItems, isEmpty);
      expect(state().isLoading, isTrue);
    });

    test('removing items stops the read that was in flight', () async {
      notifier().enterDirectory(big, newPath: 'Big');
      unawaited(notifier().loadDirectoryContents(_testContainer(), 'Big'));
      final reading = io.listings.single;
      reading.partial(['F|1|1|a.jpg', 'F|1|1|b.jpg']);

      notifier().removeItemsByName({'a.jpg'});

      expect(reading.cancelled, isTrue);
      expect(state().currentItems.map((e) => e.name), ['b.jpg']);
      expect(state().isListingPartial, isFalse);
    });

    test('leaving the screen stops the read', () async {
      notifier().enterDirectory(big, newPath: 'Big');
      unawaited(notifier().loadDirectoryContents(_testContainer(), 'Big'));
      final reading = io.listings.single;

      container.dispose();
      expect(reading.cancelled, isTrue);

      // tearDown disposes again; make that a fresh, harmless container.
      container = makeContainer();
    });
  });
}
