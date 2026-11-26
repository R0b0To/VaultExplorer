import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

const _kLogTag = 'RememberedAppCapture';

/// Asks the native open-with chooser to report which app the person picks for
/// a file of extension [ext], and saves it as that extension's remembered app
/// (`'package:<name>'`).
///
/// Returns the request id to pass to the native open call, or null when [ext]
/// is empty (nothing to remember it under). The pick is matched by that id, so
/// only the open that asked to remember can save anything.
///
/// Everything the saved preference needs is read from [ref] up front: the pick
/// arrives later, after the person has left for another app, possibly once the
/// widget that started the open is gone -- and a `ref` must not be touched
/// then. The settings controller itself is `keepAlive`.
String? armRememberedAppCapture(WidgetRef ref, String ext) {
  final cleanExt = ext.toLowerCase().replaceFirst(RegExp(r'^\.+'), '').trim();
  if (cleanExt.isEmpty) return null;
  final events = ref.read(vaultEngineEventsProvider);
  final settings = ref.read(appSettingsControllerProvider.notifier);
  return events.expectAppSelection((pkg) async {
    try {
      await settings.updateSettings(
        (s) => s.copyWith(
          extensionPreferences: {
            ...s.extensionPreferences,
            cleanExt: 'package:$pkg',
          },
        ),
      );
    } catch (e) {
      VeLog.e(_kLogTag, 'Could not remember $pkg for .$cleanExt', e);
    }
  });
}
