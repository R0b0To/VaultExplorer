import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Convenience accessor for the generated [AppLocalizations] class.
///
/// Usage: `context.l10n.someKey` anywhere a [BuildContext] is available.
extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => Localizations.of<AppLocalizations>(this, AppLocalizations)!;
}
