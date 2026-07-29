#pragma once

#include <cstdint>
#include <string>

// Shared encoder for the directory-entry wire format described in
// docs/architecture.md §5.3 (ADR-003). All three backends (fat_backend.cpp,
// ntfs_backend.cpp, ext_backend.cpp) push entries onto their `results`
// vector through this function instead of hand-building the "[DIR] "
// prefixed string each used to build separately, so the format lives in
// exactly one place on the C++ side.
//
// Wire layout: "<F|D>|<sizeBytes>|<mtimeUnixSecs>|<name>"
//   - Field 1 is an explicit type tag, never inferred from the name.
//   - Field 4 (name) is the remainder of the string after the third '|',
//     so a name that itself contains '|' (legal on ext2/3/4) is preserved
//     exactly -- callers must not attempt to further split it.
//   - `name` is passed through byte-for-byte: this function never
//     validates, trims, or otherwise alters it. Name legality is decided
//     before a name is written to a volume (see
//     lib/core/filesystem/name_validation.dart /
//     FilesystemNameValidator.kt), not when it's read back for display.
inline std::string encodeDirEntryWire(const std::string& name, bool isDir,
                                       uint64_t sizeBytes, uint64_t mtimeUnixSecs) {
    std::string out;
    out.reserve(name.size() + 24);
    out += (isDir ? 'D' : 'F');
    out += '|';
    out += std::to_string(isDir ? 0 : sizeBytes);
    out += '|';
    out += std::to_string(mtimeUnixSecs);
    out += '|';
    out += name;
    return out;
}
