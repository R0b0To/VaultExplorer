import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// How a [FileCategory] looks wherever it is listed (drawer, settings).
///
/// The names reuse the file manager's type-filter labels, so a category and
/// the filter it is built on are always called the same thing.
extension FileCategoryPresentation on FileCategory {
  String label(AppLocalizations l10n) => switch (this) {
    FileCategory.images => l10n.filterImagesOption,
    FileCategory.videos => l10n.filterVideosOption,
    FileCategory.audio => l10n.filterAudioOption,
    FileCategory.documents => l10n.filterDocumentsOption,
    FileCategory.gallery => l10n.galleryModeAction,
  };

  IconData get icon => switch (this) {
    FileCategory.images => Icons.image_rounded,
    FileCategory.videos => Icons.movie_rounded,
    FileCategory.audio => Icons.audiotrack_rounded,
    FileCategory.documents => Icons.description_rounded,
    FileCategory.gallery => Icons.photo_library_rounded,
  };
}
