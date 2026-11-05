#pragma once
// Pure offset arithmetic for the VeraCrypt header areas, kept free of I/O and
// crypto so it can be unit-tested on the host (containers/test/vc_geometry_test.cpp).
//
// Layout of a VeraCrypt file container / partition of total size V
// (A = TC_VOLUME_HEADER_GROUP_SIZE = 128 KiB, h = TC_VOLUME_HEADER_SIZE = 64 KiB):
//
//   [0, h)        primary header, normal volume
//   [h, 2h)       primary header, hidden volume
//   [A, V-A)      data area of the normal (outer) volume
//   [V-A, V-h)    backup header, normal volume
//   [V-h, V)      backup header, hidden volume
//
// A hidden volume's data lives inside the outer data area and ends at V-A.
// Note that a header's volume-size field is the size of the DATA area
// (V - 2A for a normal volume), so it must not be used as if it were the
// container size when locating the backup header.
#include <cstdint>
#include "crypto/vc_header_layout.h"

namespace vcgeom {

// Container-relative offset of the backup copy of the normal (hiddenSlot ==
// false) or hidden (hiddenSlot == true) header. Like VeraCrypt itself this is
// addressed from the END of the container. False when the container is too
// small to hold two header groups.
inline bool backupHeaderOffset(uint64_t containerSize, bool hiddenSlot, uint64_t* out) {
    if (out == nullptr || containerSize < 2 * TC_VOLUME_HEADER_GROUP_SIZE) return false;
    *out = containerSize - (hiddenSlot ? TC_VOLUME_HEADER_SIZE : TC_VOLUME_HEADER_GROUP_SIZE);
    return true;
}

// True when a full header written at headerOffset stays clear of the data
// area [dataStart, dataStart + dataLength). Overflowing ranges count as
// overlapping so callers fail closed.
inline bool headerClearOfDataArea(uint64_t headerOffset, uint64_t dataStart, uint64_t dataLength) {
    const uint64_t headerEnd = headerOffset + VC_FULL_HEADER_SIZE;
    const uint64_t dataEnd = dataStart + dataLength;
    if (headerEnd < headerOffset || dataEnd < dataStart) return false;
    return headerEnd <= dataStart || headerOffset >= dataEnd;
}

// Absolute byte range [*outStart, *outEnd) that an outer-volume write must
// not touch to keep a hidden volume intact, in the same coordinate space as
// the outer volume's data offset (container- or device-absolute).
//
// hiddenStart/hiddenLength are the hidden header's encrypted-area start
// (relative to the container's byte 0) and length. The range is validated
// against the container the outer volume implies (base = outerDataOffset - A,
// end = outerDataOffset + outerDataLength + A): the hidden data has to start
// after the primary header group and end inside the container.
inline bool hiddenProtectedRange(uint64_t outerDataOffset, uint64_t outerDataLength,
                                 uint64_t hiddenStart, uint64_t hiddenLength,
                                 uint64_t* outStart, uint64_t* outEnd) {
    if (outStart == nullptr || outEnd == nullptr) return false;
    if (outerDataOffset < VC_DATA_AREA_OFFSET) return false;
    if (hiddenLength == 0 || hiddenStart < VC_DATA_AREA_OFFSET) return false;

    const uint64_t base = outerDataOffset - VC_DATA_AREA_OFFSET;
    const uint64_t outerDataEnd = outerDataOffset + outerDataLength;
    if (outerDataEnd < outerDataOffset) return false;
    const uint64_t containerEnd = outerDataEnd + VC_DATA_AREA_OFFSET;
    if (containerEnd < outerDataEnd) return false;

    const uint64_t relEnd = hiddenStart + hiddenLength;
    if (relEnd < hiddenStart) return false;
    const uint64_t absStart = base + hiddenStart;
    const uint64_t absEnd = base + relEnd;
    if (absStart < base || absEnd < absStart) return false;
    if (absEnd > containerEnd) return false;

    *outStart = absStart;
    *outEnd = absEnd;
    return true;
}

}  // namespace vcgeom
