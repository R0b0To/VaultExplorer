// Splitting a big file (a container image) into numbered parts and joining them back.
//
// Behaviour follows the Kotlin SplitJoinHandlers / SplitPartResolver this replaces on other
// platforms: parts are named "<name>.001", "<name>.002", ... (zero-padded to at least three
// digits); a best-effort manifest.json is written beside them for other tools; joining
// recognises ".NNN" (any digit width) and ".partN" and finds the rest of the sequence by
// name. The stream-level functions (splitStream / joinStreams) work on any source and sink;
// xfer_host.h wraps them for files.
//
// Differences from the Android handlers, both fixes: a failed split or join removes the
// unfinished part / output on *any* failure (the handlers only did so on cancel, leaving a
// truncated file after an I/O error), and the next part is opened only when a byte is
// about to go into it, so an exact multiple of the part size never creates an empty trailing
// part that then has to be deleted.
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "xfer_io.h"

namespace xfer {

// "<displayName>.<index>" with the index zero-padded to at least three digits (1 -> "001").
std::string partName(const std::string& displayName, int index);

// Given the file name of one part, the names of the whole sequence in order. Mirrors
// SplitPartResolver: the sequence always starts at part 1 of the same base name, whichever
// part was picked, and runs while the next name exists (`exists` answers for a file name in
// the picked part's folder). A name that is not ".NNN" / ".partN" shaped, or whose part 1 does
// not exist, yields just `firstName` -- callers still do something sensible with what was
// picked. ".partN" parts are looked up as lower-case ".partN"; digit parts keep the picked
// suffix's width.
std::vector<std::string> resolvePartSequence(const std::string& firstName,
                                             const std::function<bool(const std::string&)>& exists);

// Informational "format" of the manifest, guessed from a file name: "LUKS" or "BITLOCKER" when
// the (ASCII-case-insensitive) name contains it, otherwise "VERACRYPT".
std::string guessFormat(const std::string& displayName);

// {"displayName":...,"format":...,"totalSizeBytes":...,"chunkSizeBytes":...}
std::string manifestJson(const std::string& displayName, const std::string& format, uint64_t totalSizeBytes,
                         uint64_t chunkSizeBytes);

// Creates part `index` (1-based); null when it cannot be created.
using PartOpener = std::function<std::unique_ptr<ByteSink>(int index)>;

// Copies `src` into consecutive parts of `chunkSize` bytes. `totalSize` only feeds progress
// and must be > 0, as must `chunkSize`; an empty source fails. Parts that are complete stay
// when a later one fails or the split is cancelled; the unfinished one is removed.
// `partsWritten` / `error` are optional.
Result splitStream(ByteSource& src, uint64_t totalSize, uint64_t chunkSize, const PartOpener& openPart,
                   Observer* obs, int* partsWritten = nullptr, std::string* error = nullptr);

// Writes every source in order into `out` and closes it. On failure or cancel `out` is discarded.
// `totalSize` (the sum of the parts) only feeds progress.
Result joinStreams(const std::vector<ByteSource*>& parts, uint64_t totalSize, ByteSink& out, Observer* obs,
                   std::string* error = nullptr);

}  // namespace xfer
