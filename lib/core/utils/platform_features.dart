import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Which optional features the current platform can offer.
///
/// The app was written for Android first. Several features sit directly on
/// Android-only mechanisms (Quick Settings tiles, foreground services, the
/// activity-alias used for Mask Mode, SAF, USB host mode, ...). On the Linux /
/// Windows desktop builds those have no counterpart, so their UI is hidden
/// there instead of being shown and failing.
///
/// Every getter is `true` on Android and `false` on desktop unless noted. UI
/// code should ask for the *feature* it is about to show rather than testing
/// the platform, so that a feature can later be ported (flip one getter) or
/// hidden on another platform without touching every call site.
///
/// This only decides what is *shown*. The code behind a hidden feature is left
/// in place, and Android behaviour is unchanged.
abstract final class PlatformFeatures {
  /// Test hook: pretend to be desktop (`true`) or Android (`false`). `null`
  /// uses the real platform.
  @visibleForTesting
  static bool? debugIsDesktopOverride;

  /// Linux, Windows or macOS.
  static bool get isDesktop {
    final override = debugIsDesktopOverride;
    if (override != null) return override;
    if (kIsWeb) return false;
    return Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  }

  static bool get isAndroid => !isDesktop;

  /// Windows can host custom caption controls alongside the browser tabs.
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// Icon for the device's own storage ("Local storage"): a phone on Android,
  /// a computer on desktop.
  static IconData get localStorageIcon =>
      isDesktop ? Icons.computer_rounded : Icons.phone_android_rounded;

  // ── Security & privacy ────────────────────────────────────────────────────

  /// Mask Mode: swaps the launcher identity (activity alias, icon and label)
  /// for a decoy file manager.
  static bool get maskMode => isAndroid;

  /// Panic responder: panic tiers, the panic Quick Settings tile, "wipe on
  /// reboot", the PanicKit (Guardian Project) trigger intents and the duress
  /// credentials that fire a panic.
  static bool get panicResponder => isAndroid;

  /// Quick Capture: capture straight into a vault from its Quick Settings
  /// tile or launcher shortcut without opening the app.
  static bool get quickCapture => isAndroid;

  /// FLAG_SECURE / recents-snapshot blocking. There is no desktop equivalent,
  /// so the toggle would do nothing.
  static bool get screenshotBlocking => isAndroid;

  /// Locking when the device screen turns off (ACTION_SCREEN_OFF). Desktop
  /// sessions have no such event.
  static bool get lockOnScreenOff => isAndroid;

  /// Caching a derived vault key in the Android Keystore.
  static bool get derivedKeyCache => isAndroid;

  // ── Vault & storage integration ───────────────────────────────────────────

  /// Per-vault automation: Tasker / broadcast intents that unlock, lock or
  /// open a vault from other apps.
  static bool get automation => isAndroid;

  /// Foreground service + notification that keeps unlocked vaults alive while
  /// the app is in the background.
  static bool get backgroundService => isAndroid;

  /// WorkManager / AlarmManager based scheduled sync and exact-alarm
  /// auto-close while the app is not running.
  static bool get backgroundScheduling => isAndroid;

  /// USB mass-storage devices opened through Android's USB host API.
  static bool get usbHost => isAndroid;

  /// "All files access" / legacy storage permission.
  static bool get storagePermission => isAndroid;

  /// Android's share sheet as an entry point (ACTION_SEND / SEND_MULTIPLE).
  static bool get shareTarget => isAndroid;

  /// The "Key Storage & System Access" settings page. Everything on it is one
  /// of the Android-only items above, so the page itself is hidden when none of
  /// them is available.
  static bool get storageIntegrationSettings =>
      storagePermission || backgroundService || usbHost || shareTarget;

  // ── Appearance / behaviour ────────────────────────────────────────────────

  /// Android 13+ predictive back gesture animations.
  static bool get predictiveBack => isAndroid;

  /// The in-app viewer for the Android `logcat` buffer.
  static bool get logcat => isAndroid;

  // ── Media & capture ───────────────────────────────────────────────────────

  /// Camera photo/video capture and the document scanner.
  static bool get camera => isAndroid;

  /// Microphone voice recorder.
  static bool get audioRecorder => isAndroid;
}
