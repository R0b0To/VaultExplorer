import 'package:vaultexplorer/features/settings/search/settings_search_text.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Resolves a user-facing string from the active localizations. Every
/// searchable string goes through one of these so search follows the app
/// language (and picks up new translations) with no extra bookkeeping.
typedef SettingsText = String Function(AppLocalizations l10n);

/// The top-level hubs of the settings screen (one per hub tile / sidebar item).
enum SettingsHub {
  security,
  storage,
  fileHandling,
  fileManager,
  appearance,
  advanced,
  about;

  /// The hub's title exactly as the hub tile shows it.
  String label(AppLocalizations l10n) => switch (this) {
        SettingsHub.security => l10n.sectionSecurityPrivacy,
        SettingsHub.storage => l10n.sectionKeyStorageIntegration,
        SettingsHub.fileHandling => l10n.sectionVaultFileHandling,
        SettingsHub.fileManager => l10n.fileManagerSettingsTitle,
        SettingsHub.appearance => l10n.sectionAppearanceInterface,
        SettingsHub.advanced =>
          '${l10n.sectionBackupRestore} & ${l10n.sectionDebug}',
        SettingsHub.about => l10n.aboutAppTitle,
      };
}

/// A screen a search result can open: either a hub itself or a sub-screen
/// reached from one of the hubs.
enum SettingsDestination {
  security(SettingsHub.security, isHub: true),
  storage(SettingsHub.storage, isHub: true),
  fileHandling(SettingsHub.fileHandling, isHub: true),
  fileManager(SettingsHub.fileManager, isHub: true),
  appearance(SettingsHub.appearance, isHub: true),
  advanced(SettingsHub.advanced, isHub: true),
  about(SettingsHub.about, isHub: true),
  emergency(SettingsHub.security),
  quickCapture(SettingsHub.security),
  authenticator(SettingsHub.security),
  appSkin(SettingsHub.appearance),
  fileManagerSkin(SettingsHub.fileManager),
  mediaPlayer(SettingsHub.fileManager),
  logcat(SettingsHub.advanced);

  const SettingsDestination(this.hub, {this.isHub = false});

  /// The hub this destination lives under (itself, for hub destinations).
  final SettingsHub hub;

  /// True when the destination is a hub screen rather than a sub-screen.
  final bool isHub;

  /// The destination's screen title, used in result breadcrumbs.
  String label(AppLocalizations l10n) => switch (this) {
        SettingsDestination.emergency => l10n.emergencyPanicTitle,
        SettingsDestination.quickCapture => l10n.quickCaptureSettingsTitle,
        SettingsDestination.authenticator => l10n.authenticatorSettingsTitle,
        SettingsDestination.appSkin => l10n.skinAppSkin,
        SettingsDestination.fileManagerSkin => l10n.fileSkinScreenTitle,
        SettingsDestination.mediaPlayer => l10n.mediaPlayerControlsTitle,
        SettingsDestination.logcat => l10n.logcatTitle,
        _ => hub.label(l10n),
      };
}

/// One searchable setting, declared once in the registry.
///
/// [title] must be the exact string the setting's row renders: the target
/// screen locates the row by finding that text on screen. [section] is the
/// header text the row sits under; it both disambiguates rows that share a
/// title (the two "Auto-lock timeout" pickers) and is shown in the result's
/// breadcrumb. [fallback] is the text to scroll to instead when the row is
/// conditionally hidden (it defaults to [section]).
class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.id,
    required this.destination,
    required this.title,
    this.section,
    this.fallback,
    this.details = const [],
    this.keywords = const [],
    this.scrollTo = true,
    this.minSdk,
  });

  /// Stable identifier, e.g. `security.master_password`. Never shown.
  final String id;

  final SettingsDestination destination;
  final SettingsText title;
  final SettingsText? section;
  final SettingsText? fallback;

  /// Extra searchable text (subtitles, option names). Matches here rank below
  /// title matches.
  final List<SettingsText> details;

  /// Extra English search terms and synonyms ("fingerprint", "dark mode").
  final List<String> keywords;

  /// False for entries that just open [destination] without scrolling to a row.
  final bool scrollTo;

  /// Hide the entry below this Android SDK level (the row isn't shown there).
  final int? minSdk;

  ResolvedSettingsEntry resolve(AppLocalizations l10n) {
    final resolvedTitle = title(l10n);
    final resolvedSection = section?.call(l10n);

    final crumbs = <String>[destination.hub.label(l10n)];
    if (!destination.isHub) {
      final screen = destination.label(l10n);
      if (screen != resolvedTitle && screen != crumbs.last) crumbs.add(screen);
    }
    if (resolvedSection != null &&
        resolvedSection != resolvedTitle &&
        resolvedSection != crumbs.last) {
      crumbs.add(resolvedSection);
    }

    return ResolvedSettingsEntry.create(
      entry: this,
      title: resolvedTitle,
      section: resolvedSection,
      fallback: fallback?.call(l10n) ?? resolvedSection,
      details: [for (final d in details) d(l10n)],
      keywords: keywords,
      breadcrumb: crumbs,
    );
  }
}

/// A [SettingsSearchEntry] with all its text resolved for the active language,
/// plus the normalised copies the matcher compares against.
class ResolvedSettingsEntry {
  const ResolvedSettingsEntry._({
    required this.entry,
    required this.title,
    required this.section,
    required this.fallback,
    required this.breadcrumb,
    required this.normTitle,
    required this.normPath,
    required this.normKeywords,
    required this.normDetails,
  });

  factory ResolvedSettingsEntry.create({
    required SettingsSearchEntry entry,
    required String title,
    required List<String> breadcrumb,
    String? section,
    String? fallback,
    List<String> details = const [],
    List<String> keywords = const [],
  }) {
    return ResolvedSettingsEntry._(
      entry: entry,
      title: title,
      section: section,
      fallback: fallback,
      breadcrumb: breadcrumb,
      normTitle: normalizeSearchText(title),
      normPath: normalizeSearchText(breadcrumb.join(' ')),
      normKeywords: normalizeSearchText(keywords.join(' ')),
      normDetails: normalizeSearchText(details.join(' ')),
    );
  }

  final SettingsSearchEntry entry;
  final String title;
  final String? section;
  final String? fallback;

  /// Hub › screen › section, as shown under the result title.
  final List<String> breadcrumb;

  final String normTitle;
  final String normPath;
  final String normKeywords;
  final String normDetails;

  String get id => entry.id;
  SettingsDestination get destination => entry.destination;
  bool get scrollTo => entry.scrollTo;
}
