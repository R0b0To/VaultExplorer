import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';

void main() {
  group('FileCategory', () {
    test('fromFilterKey resolves standard filters', () {
      expect(FileCategory.fromFilterKey('image'), FileCategory.images);
      expect(FileCategory.fromFilterKey('video'), FileCategory.videos);
      expect(FileCategory.fromFilterKey('audio'), FileCategory.audio);
      expect(FileCategory.fromFilterKey('document'), FileCategory.documents);
      expect(FileCategory.fromFilterKey('secure'), isNull);
      expect(FileCategory.fromFilterKey(null), isNull);
      expect(FileCategory.fromFilterKey('unknown'), isNull);
    });

    test('fromStorageKey resolves name keys', () {
      expect(FileCategory.fromStorageKey('images'), FileCategory.images);
      expect(FileCategory.fromStorageKey('videos'), FileCategory.videos);
      expect(FileCategory.fromStorageKey('audio'), FileCategory.audio);
      expect(FileCategory.fromStorageKey('documents'), FileCategory.documents);
      expect(FileCategory.fromStorageKey(null), isNull);
      expect(FileCategory.fromStorageKey('unknown'), isNull);
    });

    test('orderedFrom preserves custom order and appends missing', () {
      final order = FileCategory.orderedFrom(['documents', 'images']);
      expect(order, [
        FileCategory.documents,
        FileCategory.images,
        FileCategory.videos,
        FileCategory.audio,
      ]);
    });
  });
}
