# Gallery filter

Gallery mode (scoped `CategoryContentView` with `FileCategory.gallery`):
filter by type, date, tag, place, camera, orientation, rating, file size, folder, or "missing"
(no location / tags / camera / date taken), and section the grid by day, month, year, folder,
type, place or camera. The search box also matches tags, camera and place.

Code: `lib/features/browser/gallery/filter/`

| File | Role |
| --- | --- |
| `gallery_meta.dart` | Per-photo facts: date taken, GPS, camera, XMP keywords, rating, pixel size |
| `gallery_meta_parser.dart` | Pure reader of EXIF + XMP (JPEG, PNG, WebP). Never throws |
| `gallery_meta_index.dart` | Background reader + cache; stored in `/.vaultexplorer/gallery_meta.json` inside the vault |
| `gallery_filters.dart` | Filter classes and `GalleryFilterSet` (same kind = OR, different kinds = AND, excluded = always removes) |
| `gallery_places.dart` | Offline nearest-city lookup (`GalleryPlaceResolver`) and the coordinate fallback |
| `gallery_facets.dart` | Choices (with counts) offered by the sheet |
| `gallery_grouping.dart` | `GalleryGrouper`: sections + `arrange` so each section is one run of the list |
| `gallery_filter_controller.dart`, `gallery_filter_sheet.dart` | State, bottom sheet and the active-filter bar |

Rules worth keeping:

- Photo details are read lazily (first 160 KB of each file) and only once something needs them: the filter
  sheet was opened, a filter or place/camera grouping is on, or a search was typed. Stored details are
  loaded at once.
- Phone storage and vaults with thumbnail caching disabled never get the index file written.
- Places are the nearest city within 25 km, from the bundled `assets/geo/cities.bin` (GeoNames, cities of
  5000+ people, ~1.4 MB, ~0.85 MB inside the APK). Farther from any city a photo falls back to its
  coordinate cell (0.1 degrees), so it is not filed under an unrelated town. The list loads lazily the
  first time places are needed. Rebuild it with `scripts/build_gazetteer.py`;
- HEIC/AVIF/TIFF/RAW and videos are not parsed (no tags/places/camera for them; they fall back to file date).

Localization: every visible string is an ARB key (`gallery*`, 45 keys, ten translations). Add them with
`dart run scripts/update_l10n_keys.dart` and then `flutter gen-l10n`. The filter logic stays free of
generated code: it receives a `GalleryFilterLabels` that the UI builds from the translations
(`gallery_filter_l10n.dart`); tests use the English defaults.
