import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

import 'gallery_filter_labels.dart';

extension GalleryFilterLabelsContext on BuildContext {
  /// The gallery filter's words in the app's language.
  GalleryFilterLabels get galleryFilterLabels {
    final l = l10n;
    return GalleryFilterLabels(
      locale: Localizations.localeOf(this).toString(),
      photos: l.galleryTypePhotos,
      videos: l.galleryTypeVideos,
      animated: l.galleryTypeAnimated,
      landscape: l.galleryOrientationLandscape,
      portrait: l.galleryOrientationPortrait,
      square: l.galleryOrientationSquare,
      sizeSmall: l.gallerySizeSmall,
      sizeMedium: l.gallerySizeMedium,
      sizeLarge: l.gallerySizeLarge,
      noLocation: l.galleryMissingLocation,
      noTags: l.galleryMissingTags,
      noCameraInfo: l.galleryMissingCamera,
      noDateTaken: l.galleryMissingDateTaken,
      placeHintCity: l.galleryPlaceHintCity,
      placeHintCoordinates: l.galleryPlaceHintCoordinates,
    );
  }
}
