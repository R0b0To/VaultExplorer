# xfer -- hashing and split/join, in portable C++

Byte-level helpers with no platform types: no JNI, Android or Flutter. A source or sink is
whatever the host has -- a host file, a vault file (`volman/vm_xfer.h`), an Android
`InputStream` bridged over JNI.

```
xfer_io.h       ByteSource / ByteSink / Observer / Result
xfer_hash.*     MD5, SHA-1, SHA-256, SHA-512, several in one pass (mbedtls)          (xfer_core)
xfer_split.*    part names, sequence resolution, manifest, splitStream / joinStreams  (xfer_core)
xfer_host.*     std::filesystem front end: hashFile, splitFile, joinFiles             (xfer_host)
test/           known-answer vectors (hashlib), stream-level and real-file tests
```

`xfer_core` is pure and is what `volman_core` links. `xfer_host` is the front end a desktop
program calls and is left out of the Android build (`EXCLUDE_FROM_ALL`).

```cpp
std::vector<xfer::Digest> d;
xfer::hashFile("disk.hc", {xfer::HashAlgo::Sha256, xfer::HashAlgo::Md5}, &observer, d);   // d[0].hex()

xfer::splitFile("disk.hc", "out/", 1024 * 1024 * 1024, &observer);    // out/disk.hc.001, .002, ..., manifest.json
xfer::joinFiles("out/disk.hc.002", "disk-joined.hc", &observer);      // any picked part finds the sequence
```

## Behaviour (matches the Kotlin handlers this replaces on other platforms)

- Algorithm wire names are exactly `MD5`, `SHA-1`, `SHA-256`, `SHA-512`; digests are lowercase hex.
- Parts are `<name>.001`, `.002`, ... (at least three digits). Joining recognises `.NNN` (any
  width, kept) and `.partN`, always starts at part 1 and stops at the first gap; a name that is not
  part-shaped, or whose part 1 is missing, is treated as the single file picked.
- `manifest.json` (`displayName`, `format`, `totalSizeBytes`, `chunkSizeBytes`) is written beside
  the parts, best effort -- a failure there is not a failure of the split. `format` is guessed from
  the name: `LUKS`, `BITLOCKER`, else `VERACRYPT`.

## Two deliberate differences (fixes)

- A failed split or join removes the unfinished part / output on **any** failure. The Android
  handlers did so only on cancel and left a truncated file after an I/O error. Parts that were
  completed stay.
- The next part is opened only when a byte is about to go into it, so an exact multiple of the part
  size never creates an empty trailing part that then has to be deleted.

## Not here, on purpose

Import/export naming policy (case folding, "name (1)" collisions, the free-space margin) is already
decided on the Dart side and mirrored in Kotlin; Dart is the portable layer, so moving a third copy
into C++ would add drift, not portability. What belongs here is policy-free byte logic.
