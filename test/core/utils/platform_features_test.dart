import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';

void main() {
  tearDown(() => PlatformFeatures.debugIsDesktopOverride = null);

  test('Android-only features are hidden on desktop', () {
    PlatformFeatures.debugIsDesktopOverride = true;

    expect(PlatformFeatures.isDesktop, isTrue);
    expect(PlatformFeatures.maskMode, isFalse);
    expect(PlatformFeatures.panicResponder, isFalse);
    expect(PlatformFeatures.quickCapture, isFalse);
    expect(PlatformFeatures.automation, isFalse);
    expect(PlatformFeatures.screenshotBlocking, isFalse);
    expect(PlatformFeatures.lockOnScreenOff, isFalse);
    expect(PlatformFeatures.derivedKeyCache, isFalse);
    expect(PlatformFeatures.backgroundService, isFalse);
    expect(PlatformFeatures.backgroundScheduling, isFalse);
    expect(PlatformFeatures.usbHost, isFalse);
    // ...but an encrypted disk can still be mounted on desktop, straight from the OS.
    expect(PlatformFeatures.driveMount, isTrue);
    expect(PlatformFeatures.camera, isFalse);
    expect(PlatformFeatures.audioRecorder, isFalse);
    expect(PlatformFeatures.logcat, isFalse);
    // The storage page is hidden once every item on it is unavailable.
    expect(PlatformFeatures.storageIntegrationSettings, isFalse);
  });

  test('everything stays available on Android', () {
    PlatformFeatures.debugIsDesktopOverride = false;

    expect(PlatformFeatures.isAndroid, isTrue);
    expect(PlatformFeatures.maskMode, isTrue);
    expect(PlatformFeatures.panicResponder, isTrue);
    expect(PlatformFeatures.automation, isTrue);
    expect(PlatformFeatures.usbHost, isTrue);
    expect(PlatformFeatures.driveMount, isTrue);
    expect(PlatformFeatures.storageIntegrationSettings, isTrue);
  });
}
