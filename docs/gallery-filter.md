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
| `gallery_filters.dart` | Filter classes and `GalleryFilterSet` (same kind = OR, different kinds = AND, excluded = always removes; with `matchAllTags` several selected tags are AND instead, set by the Match any / Match all control in the Tags section) |
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

## Choosing the gallery's folders

A gallery opened on a vault or on phone storage scans the whole storage by default. The gallery's options menu has a
**Gallery folders** entry that opens a folder tree: tick the folders to scan (subfolders are included) and apply. The
choice is saved per storage on this device, and the scan then starts from those folders only. Ticking nothing, or
choosing **Scan everything**, goes back to the whole storage. While folders are chosen, the gallery's top is the storage
root, and the partial scan is never stored as the storage's category index.

## Where the metadata index is kept, and what it does while you scroll

The index of what was read from the photos (date taken, place, camera, tags) is kept per source:

- **Vaults**: in `/.vaultexplorer`, inside the vault, as long as thumbnail caching is on and the vault is writable.
- **Phone storage and other plain locations**: in the hidden `.thumbcache` folder, next to the thumbnails, and only when
  that folder is the thumbnail cache chosen for the storage. Clearing the thumbnail cache removes the index too. With
  any other thumbnail setting nothing is written to the storage.
- **Whatever is not saved** (phone storage without the hidden folder) is kept in memory for the session
  (`GalleryMetaMemory.app`), so opening the gallery again does not read every photo again. It is gone when the app is
  closed. An entry is only used while the file's size and date still match.

The list must not move under the finger:

- While the gallery scrolls, the index holds back what it has read and scan progress is kept aside; both are applied
  when the scrolling has been still for a moment.
- When the list changes while the view is not at its top (filter results arrived, a scan ended, a vault was mounted),
  the photo that was first on screen stays where it was (if it was filtered out, the nearest one that remains).
  This is `captureTopItem` / `adoptAnchored` on the layout host for the sectioned grid, list and masonry, and a
  direct offset correction for the plain grid and list (`gallery_anchor.dart`).
- A rescan of what is already shown (refresh, after an operation, a vault mounted) keeps the list on screen until
  the new result is in, instead of blanking it first.
