import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';

void main() {
  group('FileManagerToolbarConfig autoStartPlaylistMode', () {
    test('defaults to false in defaults() factory', () {
      final config = FileManagerToolbarConfig.defaults();
      expect(config.autoStartPlaylistMode, isFalse);
    });

    test('defaults to false when unassigned in constructor', () {
      final config = const FileManagerToolbarConfig(
        order: [],
        hidden: {},
      );
      expect(config.autoStartPlaylistMode, isFalse);
    });

    test('copyWith updates autoStartPlaylistMode', () {
      final config = FileManagerToolbarConfig.defaults();
      final updated = config.copyWith(autoStartPlaylistMode: true);
      expect(updated.autoStartPlaylistMode, isTrue);

      final reset = updated.copyWith(autoStartPlaylistMode: false);
      expect(reset.autoStartPlaylistMode, isFalse);
    });

    test('serializes and deserializes autoStartPlaylistMode correctly in JSON', () {
      final config = FileManagerToolbarConfig.defaults().copyWith(
        autoStartPlaylistMode: true,
      );
      final json = config.toJson();
      expect(json['autoStartPlaylistMode'], isTrue);

      final restored = FileManagerToolbarConfig.fromJson(json);
      expect(restored.autoStartPlaylistMode, isTrue);
    });

    test('fromJson falls back to false when key is missing', () {
      final json = <String, dynamic>{
        'showBreadcrumbBar': true,
      };
      final config = FileManagerToolbarConfig.fromJson(json);
      expect(config.autoStartPlaylistMode, isFalse);
    });
  });
}
