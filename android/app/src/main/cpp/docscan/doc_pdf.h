// Minimal PDF writer for scanned pages: each page is one JPEG embedded as-is
// (DCTDecode), so no re-encoding happens and the output stays small. Built in
// memory only. No document info (author, dates, producer) is written, to avoid
// leaking anything about the device or the time of the scan.
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace docscan {

struct PdfPage {
    const uint8_t* jpeg = nullptr;  // baseline/progressive 8-bit gray or RGB JPEG
    size_t jpegSize = 0;
};

// Reads size and channel count from a JPEG's SOF header. Only plain 8-bit
// gray/RGB DCT JPEGs (baseline, extended sequential, progressive) qualify, as
// those are what PDF's DCTDecode takes verbatim. Returns false otherwise.
bool readJpegInfo(const uint8_t* data, size_t size, int* width, int* height, int* components);

// Page size follows the image aspect with the long side fixed to A4's 842 pt;
// dimensions come from the JPEG itself, never from the caller. Returns an empty
// vector when pages is empty or any page is not an embeddable JPEG.
std::vector<uint8_t> buildPdf(const std::vector<PdfPage>& pages);

}  // namespace docscan
