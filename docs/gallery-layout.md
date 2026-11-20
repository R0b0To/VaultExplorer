# Gallery layout (masonry / mosaic and date-grouped grids)

How the file explorer's masonry view (and the date-grouped uniform grid) lays out
thousands of thumbnails.

## Pieces

| File | Role |
|---|---|
| `lib/features/browser/gallery/gallery_layout.dart` | Pure-Dart geometry engine. Items with aspect ratios + sections with optional headers in, one rectangle per child out, plus the scroll queries a sliver needs. No Flutter imports, unit-tested (`test/features/browser/gallery/`). |
| `lib/features/browser/gallery/gallery_sliver.dart` | `GallerySliverGrid`: one `SliverGrid` for all sections (headers included) fed by the engine, with same-pass scroll anchoring. |
| `lib/features/browser/gallery/gallery_ratio_prefetcher.dart` | Learns image aspect ratios before their tiles exist, nearest-to-the-viewport first. |
| `lib/data/services/media_index/` | The persisted media index: `MediaPathHash` (64-bit path hash), `MediaIndex` (sorted typed arrays, 28 bytes an entry), `MediaIndexCodec` (checksummed file format), `MediaIndexService` (load, batched background save), `VaultMediaIndexStorage` (reads/writes `/.vaultexplorer/media_index.bin`). |
| `lib/data/services/media_aspect_ratio_cache.dart` | Session-only, name-keyed ratio store the media viewer also reads. |
| `probeImageDimensions` (Kotlin `ThumbnailHandlers`, Dart `VaultFileIoApi`) | Header-only size probe for a batch of images. No pixel decode, no thumbnail, nothing written anywhere by the probe itself. |

## Flows

`GalleryFlow.rows` is the justified "mosaic": every tile in a row has the same
height and a width proportional to its picture's aspect ratio, so rows fill the
width and nothing is cropped. `GalleryFlow.columns` is the column ("Pinterest")
masonry; with a constant ratio it is a uniform grid (the date-grouped grid view
uses it that way). `FileMasonryView._flow` selects the flow.

In `rows`, the column count (the pinch-to-zoom setting) sets the *target row
height* (the height a cell has in a grid with that many columns), so changing
layout keeps the scale.

## Why it is built this way

* **Exact geometry, no estimates.** The scroll extent is exact and a jump to the
  middle of a 40,000-item folder is a binary search (laying out 40k items takes
  a few ms). Dragging the fast-scroll handle no longer fights a changing extent.
* **One sliver.** A sliver per date group makes the viewport lay out every group
  on every scrolled frame and build at least one tile (and start one thumbnail
  load) in each group even when it is far off screen
  (flutter/flutter#49027).
* **Ratios are known before tiles are built.** a vault has no media database, so the app keeps its own
  index, *inside the vault*:
  * `/.vaultexplorer/media_index.bin`, next to `marks.json` and the sync files:
    encrypted with the vault, carried with it to another device, readable only
    while it is unlocked. A folder opened a second time (or on another phone) is
    laid out correctly on the first frame.
  * An entry stores the file's size and modified time next to its width/height
    and is ignored when either differs, so an edited or replaced picture is
    measured again.
  * Entries that are missing are measured by `probeImageDimensions` (headers
    only, 32 files per native task), nearest to the viewport first, continuously
    as the user scrolls; videos and book covers learn theirs from their
    thumbnail. Everything measured is added to the index and saved in the
    background a few seconds later (never later than 20 s after the first
    change), and before a vault is locked (`VaultLifecycleApi.lockContainer`).
  * File format: 16-byte header (`VXMI`, version, count, CRC-32) followed by
    five parallel arrays sorted by hash. A damaged or unknown file simply means
    "no index"; the next save replaces it. 200,000 photos are about 5.6 MB and
    encode/decode in tens of milliseconds (in a background isolate above 20k
    entries).
  * Not persisted: phone/external storage (memory only, no hidden folder is
    dropped into a user's files), read-only vaults (an existing index is read,
    nothing is written), and containers whose thumbnail cache mode is
    "disabled" (same: read, never written).
* **Nothing waits for the scroll to stop.** Sizes arrive while the user is
  flinging, and what is on screen is correct as soon as it is known:
  * While scrolling, the layout is recomputed from the top row on screen
    *downwards* (`GalleryLayoutModel.recomputeFrom`); everything above keeps
    its exact position. Tiles on screen take their right shape immediately,
    nothing visible moves vertically, and no scroll correction is needed (a
    fling would overwrite one on its next tick).
  * Rows above the screen are briefly out of date (`hasStalePrefix`); they are
    refreshed by the next full reflow, which runs as soon as the scroll ends
    and is adopted with an *anchor*: `GallerySliverGrid` returns a
    `scrollOffsetCorrection` from its own layout pass so the tile at the top of
    the screen stays exactly where it was. If the user scrolls back up first,
    the top row moves up with them and the next reflow refreshes those rows.
  * Pinch-to-zoom uses the same anchoring, at the pinch's focal point.
  * Measuring (`GalleryRatioPrefetcher` with `follow: true`) is a continuous
    loop that re-reads the viewport before every batch, not something started
    when a scroll ends.

## Scrolling fast (the scroll handle, flings)

Dragging the handle across thousands of items replaces the whole screen on
every frame, which is what made the old pass-by look like a rolling-shutter
smear. Three things keep it smooth without making anything wait for the scroll
to *stop*:

* **A speed verdict, not a "settled" signal.** `FastScrollbar` feeds every
  scroll-offset change (fingers, flings, and the handle's own `jumpTo`s) to
  `ScrollSpeedTracker`, which measures speed in viewport heights per second:
  *fast* above 2.5, no longer fast below 1.2 (hysteresis, so it cannot flicker).
  Everything below resumes the moment the speed drops under that, long before the
  scroll ends. Set `ScrollSpeedTracker.enterScreensPerSecond` to infinity to
  switch the whole mechanism off.
* **Thumbnails.** While the verdict is "fast", a tile that has not asked for its
  thumbnail yet does not create a loader (`ScrollSpeedScope`, read by
  `AsyncThumbnail`); one whose bytes are already in memory is shown anyway, and
  a tile that has already asked keeps loading. When the speed drops, the tiles
  on screen are rebuilt once and load.
* **Layout.** A held handle counts as scrolling (`jumpTo` fires its start and
  end notifications inside one call, so the notification-based flag never saw
  it, and anchored corrections used to fight the handle). While the handle is
  held the layout is frozen above the top row (see above), and reflows are
  postponed while the verdict is "fast".

## Privacy

The probe reads a few KB per file through the normal decrypting stream and
writes nothing. The media index holds only a hash of each path, the file's size
and modified time, and its pixel dimensions; it is stored inside the encrypted
vault (never on host storage), and the in-memory copy is dropped when the vault
locks. "Thumbnail cache: disabled" containers are never written to.
