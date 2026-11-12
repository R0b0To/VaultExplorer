import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';

void main() {
  group('MediaViewerAction.thumbnailCarousel', () {
    bool applicable({
      required bool isImage,
      required bool isAudio,
      required bool isPlaylistMode,
    }) =>
        MediaViewerAction.thumbnailCarousel.isApplicable(
          isImage: isImage,
          isAudio: isAudio,
          isPlaylistMode: isPlaylistMode,
        );

    test('is hidden when there is no playlist to browse', () {
      expect(
        applicable(isImage: true, isAudio: false, isPlaylistMode: false),
        isFalse,
      );
      expect(
        applicable(isImage: false, isAudio: false, isPlaylistMode: false),
        isFalse,
      );
      expect(
        applicable(isImage: false, isAudio: true, isPlaylistMode: false),
        isFalse,
      );
    });

    test('is shown for images, video and audio in a playlist', () {
      expect(
        applicable(isImage: true, isAudio: false, isPlaylistMode: true),
        isTrue,
      );
      expect(
        applicable(isImage: false, isAudio: false, isPlaylistMode: true),
        isTrue,
      );
      expect(
        applicable(isImage: false, isAudio: true, isPlaylistMode: true),
        isTrue,
      );
    });
  });
}
