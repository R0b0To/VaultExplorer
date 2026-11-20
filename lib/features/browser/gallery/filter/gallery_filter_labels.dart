/// The words the gallery filter's logic needs (filter chip names, section
/// names, the placeholders of unknown groups), handed in by the UI so this
/// code stays free of widgets and of the generated localizations.
///
/// The defaults are English, so tests and anything without a context can use
/// `const GalleryFilterLabels()`. The app builds the translated one with
/// `context.galleryFilterLabels` (see `gallery_filter_l10n.dart`).
class GalleryFilterLabels {
  const GalleryFilterLabels({
    this.locale = 'en',
    this.photos = 'Photos',
    this.videos = 'Videos',
    this.animated = 'Animated',
    this.raw = 'RAW',
    this.landscape = 'Landscape',
    this.portrait = 'Portrait',
    this.square = 'Square',
    this.sizeSmall = 'Under 1 MB',
    this.sizeMedium = '1 – 10 MB',
    this.sizeLarge = 'Over 10 MB',
    this.noLocation = 'No location',
    this.noTags = 'No tags',
    this.noCameraInfo = 'No camera info',
    this.noDateTaken = 'No date taken',
    this.placeHintCity = _cityHintEnglish,
    this.placeHintCoordinates = _coordinatesHintEnglish,
  });

  /// Language tag for dates (`en`, `de`, `pt_BR`...).
  final String locale;
  final String photos;
  final String videos;
  final String animated;
  final String raw;
  final String landscape;
  final String portrait;
  final String square;
  final String sizeSmall;
  final String sizeMedium;
  final String sizeLarge;
  final String noLocation;
  final String noTags;
  final String noCameraInfo;
  final String noDateTaken;

  /// Tooltip of a place that is a city; the argument is the search radius in km.
  final String Function(int km) placeHintCity;

  /// Tooltip of a place that is bare coordinates.
  final String Function(int km) placeHintCoordinates;
}

String _cityHintEnglish(int km) => 'Nearest city, within $km km';

String _coordinatesHintEnglish(int km) =>
    'No city within $km km: grouped by coordinates';
