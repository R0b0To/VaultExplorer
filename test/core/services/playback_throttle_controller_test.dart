import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';

class _RecordingFileIoApi extends VaultFileIoApi {
  _RecordingFileIoApi() : super(const MethodChannel('test/playback-throttle'));

  final activeValues = <bool>[];

  @override
  Future<void> setPlaybackActive(bool active) async {
    activeValues.add(active);
  }
}

void main() {
  test('sends playback state through its configured file I/O API', () async {
    final fileIoApi = _RecordingFileIoApi();
    PlaybackThrottleController.configure(fileIoApi);
    PlaybackThrottleController.isPlaybackActive.value = false;

    await PlaybackThrottleController.setActive(true);
    await PlaybackThrottleController.setActive(true);
    await PlaybackThrottleController.setActive(false);

    expect(fileIoApi.activeValues, [true, true, false]);
    expect(PlaybackThrottleController.isPlaybackActive.value, isFalse);
  });
}
