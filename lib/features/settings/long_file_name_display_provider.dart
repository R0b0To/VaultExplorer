import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

/// The app-wide "Long File Names" setting from File manager settings, for
/// names shown outside the file manager (vault cards on the dashboard and
/// vault rows in the side drawer).
///
/// The setting lives in the shared toolbar config, which every settings
/// provider instance publishes to, so a change in File manager settings
/// reaches these lists immediately.
final longFileNameDisplayModeProvider =
    Provider.autoDispose<LongFileNameDisplayMode>(
      (ref) => ref.watch(
        fileManagerToolbarSettingsProvider(
          null,
        ).select((s) => s.config.longFileNameDisplayMode),
      ),
    );
