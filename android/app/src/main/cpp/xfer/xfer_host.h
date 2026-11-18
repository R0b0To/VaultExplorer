// Host-filesystem front end of the transfer helpers: files and folders on the machine the
// program runs on (a desktop's disks, or app-private storage on Android), via
// std::filesystem. Paths cross the API as std::filesystem::path; the part and manifest names
// that xfer_split.h works with are UTF-8 strings and converted here.
//
// Not used for Android's SAF "content://" locations -- those are streams the Kotlin side
// provides, which plug into the stream-level API of xfer_split.h / xfer_hash.h instead.
#pragma once

#include <filesystem>
#include <memory>
#include <string>

#include "xfer_hash.h"
#include "xfer_io.h"
#include "xfer_split.h"

namespace xfer {

std::filesystem::path pathFromUtf8(const std::string& utf8);
std::string utf8FromPath(const std::filesystem::path& p);

// Sequential reader of a regular file; null (and `error`) when it cannot be opened. `size`, if
// given, receives the file size.
std::unique_ptr<ByteSource> openFileSource(const std::filesystem::path& file, std::string* error = nullptr,
                                           uint64_t* size = nullptr);

// Creates (or truncates) `file`. Its discard() removes it again; a missing parent folder is an
// error, not created.
std::unique_ptr<ByteSink> createFileSink(const std::filesystem::path& file, std::string* error = nullptr);

// Hashes a file in one pass over `algos`.
Result hashFile(const std::filesystem::path& file, const std::vector<HashAlgo>& algos, Observer* obs,
                std::vector<Digest>& out, std::string* error = nullptr);

struct SplitSummary {
    std::string displayName;   // the source's file name, as used for the part names
    uint64_t totalSize = 0;
    int parts = 0;
};

// Splits `source` into "<name>.001", "<name>.002", ... of `chunkSize` bytes inside `destDir`
// (created if missing) and writes manifest.json beside them, best effort. See xfer_split.h
// for what stays behind on failure.
Result splitFile(const std::filesystem::path& source, const std::filesystem::path& destDir, uint64_t chunkSize,
                 Observer* obs, SplitSummary* summary = nullptr, std::string* error = nullptr);

// Joins the part sequence `firstPart` belongs to (see resolvePartSequence) into `output`. The
// output may not be one of the parts. A single picked file that is not part of any sequence is
// copied as is. Removes `output` again if the join fails or is cancelled.
Result joinFiles(const std::filesystem::path& firstPart, const std::filesystem::path& output, Observer* obs,
                 std::string* error = nullptr);

}  // namespace xfer
