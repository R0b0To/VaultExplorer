/// Barrel file for the app's small, generic, cross-feature widgets.
///
/// This used to be one large "kitchen sink" file. Each widget now lives in
/// its own focused file under core/widgets/<category>/ — this barrel exists
/// so existing call sites can keep a single import while the app is
/// migrated incrementally to importing the specific widget file it needs.
library;

export 'package:vaultexplorer/core/widgets/layout/section_label.dart';
export 'package:vaultexplorer/core/widgets/layout/settings_toggle_row.dart';
export 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
export 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
export 'package:vaultexplorer/core/widgets/feedback/app_empty_state.dart';
export 'package:vaultexplorer/core/widgets/sheets/app_bottom_sheet.dart';
export 'package:vaultexplorer/core/widgets/sheets/sheet_option_tile.dart';
export 'package:vaultexplorer/core/widgets/inputs/password_visibility_toggle.dart';
export 'package:vaultexplorer/core/widgets/cards/app_card.dart';
export 'package:vaultexplorer/core/widgets/animation/staggered_entrance.dart';
export 'package:vaultexplorer/core/widgets/crypto_forms/keyfiles_picker.dart';
export 'package:vaultexplorer/core/widgets/crypto_forms/advanced_params_panel.dart';
