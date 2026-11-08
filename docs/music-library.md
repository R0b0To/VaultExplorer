# Music mode

Music mode turns the file manager into a music library: **Albums**, **Artists**,
**Genres**, **Folders** and **Tracks**, with search and sorting, next to the normal **Files** listing.

It is off by default and **per location** (a vault, phone storage, external storage).
Nothing is indexed until you turn it on.

## Using it

1. Press the **Music mode** toolbar button in the file manager (also in the **More**
   menu; movable or hideable like any toolbar action).
2. Choose what to include: **Everything in this location**, or **Only some folders**
   (folder picker). Phone and external storage start on "Only some folders", because
   their root is everything on the device.
3. The file toolbar is replaced by a **music strip at the bottom**:
   `Tracks | Albums | Artists | Genres | Folders`,
   the selected music mode icon, a spinner while a scan runs, and a menu (scan for
   changes, re-read all tags, music folders, delete saved index, turn off). Dragging
   the pills does not open the side drawer.
4. Tap the selected music mode icon to turn music mode off and return to the file
   listing. Reopening music mode starts on Tracks. System back follows normal browser
   navigation and does not switch to Files.
5. Each list has a draggable scrollbar. Search is an icon in the slim header row of each
   view; the header also holds play, shuffle and sort.

### Several locations at once

Every location with music mode on feeds **one merged library** (`MusicHub`): the same
album split between a vault and the phone is one album, an artist's tracks from both
appear together, and search, sorting and covers cover everything. A location is indexed
once however many tabs show it, and dropped from memory when the last tab holding it
closes or the vault locks.

Playback is limited by the viewer, which plays from one location at a time. When a list
mixes locations, a play or shuffle plays the tracks in the starting track's location (for
shuffle, the location of a randomly chosen track, so locations come up in proportion to
their size), in list order, and says so. Playing across locations without a break needs a
per-track location in the viewer's playlist; it is not part of this change.

### Playing

Play and shuffle are available from the header of Albums, Artists, Genres and Tracks (they
start whatever list is shown, in its order), from each album tile, from each artist and
genre row, and from every album/artist/genre screen. Library playback starts in the
**mini player**. Tap it or drag it up to open the music player.

### Folders

The **Folders** tab lists every folder that directly holds audio files, and nothing else:
folders that only contain other folders are left out, so it shows where the music is rather
than a copy of the file tree. Each row shows the folder name, where it sits, and its track
count, with play and shuffle buttons; tapping opens the folder's tracks. Files that sit in the
root of a location are listed under the location's name. It can be searched and sorted by name,
track count or recently added.

### Mini player and music player

While music plays without a viewer open, a bar above the music strip (or at the bottom of
album, artist, genre and folder screens) shows the track (tags and cover from the library when
the file is in it) with previous, play/pause and next. It follows
`BackgroundPlaybackHost.activeSession`, so it disappears when the music stops or a viewer takes
over.

Tapping the bar or dragging it up opens the **music player**, which grows out of the bar
(`NowPlayingPanel`): one animation drives everything, so the thumbnail becomes the big cover,
the play button travels to the middle of the controls, and the panel follows the finger. Drag it
down, press Back, or tap the chevron to return to the bar. The player has the waveform seek bar,
shuffle, previous, play/pause, next and repeat (off / all / one), a queue list (tap a track to
jump to it), and a menu with *Open in media player* (equalizer, A-B loop and the rest of the
viewer) and *Stop playback*. Swiping the cover or the bar sideways skips a track; dragging the bar
down stops playback.

Shuffle keeps the playing track and shuffles the rest of the queue; turning it off restores the
previous order. Repeat applies to music started from the library only.

Details worth knowing:

- **The drag is followed, not triggered.** While a finger drags the bar up, the player lives in
  the root overlay, not on a route: pushing a route would cancel the gesture. Let go open and it
  moves onto a route (so Back minimizes it) from exactly where it was, in the same frame.
- **Previous and next are shared elements**, like the play button: they sit either side of it in
  the bar and in the full player and travel between the two, so they never disappear.
- **Skipping never blinks the play button.** `BackgroundPlaybackHost.playing` ignores the new
  track's "not playing yet" reports until it really plays. Skipping always plays.
- **Progress glides.** The player reports its position a few times a second; `PositionExtrapolator`
  adds the time since the last report (at the playback speed), so the bar in the mini player and
  the waveform advance every frame instead of in steps. It never moves backwards on a late report
  and stops estimating if the player stalls.
- **Dragging the bar down squishes it** towards the music strip as a preview that letting go closes
  playback; give up the drag and it springs back.
- **The music strip stays** in folder, album, artist and genre screens; picking a view returns to
  the library on it.
- **Library pages slide** towards the side of the new tab instead of cutting.

### Waveform seek bar

In the media player, music uses its waveform as the timeline (tap or drag to seek; an A-B
loop is drawn and clamps the position). It uses the audio editor's envelope extractor on
the file being played. The ordinary slider shows until the waveform is ready, and stays for
files over 25 minutes (audiobooks) or ones that cannot be decoded.

### Covers by hand

The app has no internet, so a missing cover can be set by hand: open an album or artist,
menu > **Choose a cover image**, and pick an image from the location's own files (the
picker starts in the album's folder). The image is shrunk to at most 512 px and saved with
the location (see below); **Remove custom cover** undoes it. A hand-chosen cover wins over
the cover embedded in the files.

## Where things are saved

Titles, artists, folder names and cover images describe private content, so they follow
the same rule as the bookmarks (`VaultMarksStore`):

| Location | Config, index and custom covers |
| --- | --- |
| Writable vault | Inside the vault: `/.vaultexplorer/music.json`, `music-index.bin`, `music-covers.bin`. The vault encrypts them; they travel with it and are unreadable while it is locked. |
| Phone / external storage | The app's private storage, AES-GCM encrypted with the same Keystore-backed key as the thumbnail cache. Nothing is written into your folders. |
| Read-only vault | Same as phone storage (nothing can be written into the vault). |

The index is saved after every scan **and periodically during a long first scan** (every
1,500 new tracks or 45 s), so an interrupted first scan resumes instead of starting over.
Re-opening shows the saved index immediately and only re-reads files whose size or modified
time changed. This does **not** depend on the thumbnail cache setting.

Embedded cover art is read on demand into a bounded memory-only cache and is never saved.
The in-memory index and covers are dropped when the last tab holding a location closes or
the vault locks.

## How indexing works

1. **Walk** the chosen folders (listing only; hidden entries are skipped).
2. **Diff** against the saved index by `path + size + modified time`.
3. **Read tags** only for new or changed files, with header-driven readers
   (`lib/features/library/tags/`): a few KB per file, never the audio, embedded pictures
   skipped over. An MP3 with an ID3v2 tag and a Xing header costs one read. Formats: MP3
   (ID3v2.2/2.3/2.4, ID3v1, Xing/VBRI), FLAC, Ogg Vorbis, Opus, MP4/M4A/M4B, WAV. Other
   audio is indexed by file name.
4. **Group** into albums / artists / genres in memory (`LibraryIndex`).

A scan that was cancelled, hit a limit, or could not list a folder **never removes** tracks
from the index. A damaged or tampered saved file is ignored and rebuilt.

## Playback queue pinning

Every library queue is opened with `startingFolder: libraryQueueFolder`, a dot-folder that
holds none of the queue's files, so the viewer treats the queue as already spanning folders
and its "Current folder / All" toggle cannot replace an album with whatever else lives next to
it. `test/features/library/library_queue_test.dart` pins this to the real `PlaylistController`.

## Sorting

Albums by title, artist, year, recently added; artists by name or track count; tracks by
title, artist, album, length, recently added; each reversible. Entries with no value for the
criterion always sort last. Sort choices are per visit and are not saved.

## Known limits

- Building the groups and sorting run on the UI isolate: roughly 0.3 to 0.6 s per rebuild at
  30,000 tracks on a desktop VM, more on a phone.
- Changing tags without changing size or modified time needs *Re-read all tags*.
- *Clear thumbnail cache* does not clear library indexes; use *Delete saved index*.
- The waveform is decoded while the track plays, which costs some CPU for a few seconds.
- Strings are English-only until translated.

## Tests

`test/features/library/` runs on plain Dart except `library_queue_test.dart` (needs
`flutter test`): tag readers against real ffmpeg/mutagen fixtures
(`test/fixtures/audio_tags/`), grouping, merging, search and sorting, the scanner, codecs and
their damage handling, the store's location rules, the controller (checkpoints, resume, folder
scope), the hub (merging, sharing, detaching), per-container music mode state, the cover cache,
and the waveform reduction.
