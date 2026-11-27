// Native image thumbnails: decode a JPEG / PNG / WebP straight to a small picture and encode it again, in one
// call, with no UI-thread or GPU involvement. Platform-neutral C++17 (no JNI, no Dart, no engine headers), so
// it can be unit-tested on the host (see test/thumb_test.cpp) and reused by any front-end.
//
// Why this exists (desktop): the Flutter route reads the whole file into Dart, copies it three times, decodes it
// through dart:ui and re-encodes the result as PNG through a GPU read-back. Here
//   * a JPEG is decoded at 1/2, 1/4 or 1/8 size straight out of the DCT (libjpeg-turbo scaled IDCT), so a 24 MP
//     photo costs about as much as a 3 MP one; nothing near full size is ever materialised;
//   * a PNG is decoded row by row into a streaming box filter, so memory stays proportional to the OUTPUT size;
//   * a WebP is scaled inside libwebp while decoding;
//   * the source is read through a small read-ahead buffer instead of being loaded whole (JPEG / PNG);
//   * the answer is a small JPEG (or a PNG when the picture really has transparency), which is cheap to encode,
//     to cache, to encrypt and to move between isolates.
//
// The caller supplies the bytes through a [ByteSource]; nothing here touches the file system.
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace veimg {

// Random-access view of the encoded picture. Implementations need not be thread-safe: one source is used by one
// thread at a time.
class ByteSource {
public:
    virtual ~ByteSource() = default;

    // Total size in bytes, or -1 when unknown.
    virtual int64_t size() = 0;

    // Reads up to `len` bytes at `offset`. Returns the number read (0 at the end of the data), or -1 on an I/O error.
    virtual int64_t readAt(int64_t offset, uint8_t* dst, size_t len) = 0;
};

// A source over a block of memory the caller keeps alive.
class MemorySource final : public ByteSource {
public:
    MemorySource(const uint8_t* data, size_t len) : data_(data), len_(len) {}
    int64_t size() override { return static_cast<int64_t>(len_); }
    int64_t readAt(int64_t offset, uint8_t* dst, size_t len) override;

private:
    const uint8_t* data_;
    size_t len_;
};

enum class Status {
    kOk = 0,
    kUnsupported,  // not a format handled here (the caller should fall back to another decoder)
    kFailed,       // corrupt / truncated beyond repair, or an encoder failure
    kTooLarge,     // refused by the size guards in [Options]
    kIoError,      // the source could not be read
    kNoMemory,
};

enum class Format { kUnknown = 0, kJpeg, kPng, kWebp };

// Looks at the first bytes (at least 12 are needed to tell WebP).
Format sniffFormat(const uint8_t* head, size_t len);

struct Options {
    // The thumbnail fits inside targetSize x targetSize; a smaller picture is never enlarged.
    int targetSize = 180;
    // JPEG quality 1..100.
    int quality = 70;
    // Kept for API parity with the Android call. A picture whose pixels are not all opaque is always answered as
    // PNG (alpha kept); an opaque one as JPEG.
    bool preserveAlpha = false;
    // Encoded file size above which the source is refused (kTooLarge).
    uint64_t maxSourceBytes = 256ull << 20;
    // Decoding is refused (kTooLarge) when it would need more than this many bytes of working memory. A baseline
    // JPEG is exempt: it is decoded a row at a time.
    uint64_t maxDecodeBytes = 1ull << 30;
};

struct Thumbnail {
    std::vector<uint8_t> bytes;  // the encoded thumbnail
    bool isPng = false;          // false: JPEG
    int sourceWidth = 0;         // the picture's own size, EXIF orientation applied (what a viewer would show)
    int sourceHeight = 0;
    int width = 0;               // the thumbnail's size
    int height = 0;
    bool hasAlpha = false;       // some pixel is not opaque
    bool isBlank = false;        // flat, near-black or blown-out, a title card, or very low contrast (see below)
};

// Whether a picture is uninformative as a thumbnail: flat colour, near-black or blown-out, a slate that is mostly
// background, or very low contrast. 8x8 samples out of `px` (w x h, `ch` = 3 or 4 bytes per pixel). A port of the
// Android heuristic (VideoThumbnailCoordinator.isLikelyBlankFrame); makeThumbnail() runs it on the finished
// thumbnail, which video thumbnails use to decide whether to try another frame.
bool isLikelyBlank(const uint8_t* px, int w, int h, int ch);

// For decoders that bring their own pixels (video frames): turns an RGB raster (w x h, 3 bytes per pixel) that is
// already the thumbnail's size into a finished [Thumbnail]. `orientation` (EXIF 1..8) is applied first;
// storedW x storedH is the picture's size before it. Runs the blank check and encodes a JPEG.
Status finishThumbnail(std::vector<uint8_t>&& rgb, int w, int h, int orientation, int storedW, int storedH, int quality,
                       Thumbnail& out);

// Decodes [src] and fills [out]. Thread-safe: any number of calls may run at once (they share only the memory
// budget below).
Status makeThumbnail(ByteSource& src, const Options& opt, Thumbnail& out);

// Memory the decoders may hold at once, across threads. A decode that needs a lot (a progressive JPEG, an
// interlaced PNG) waits until it fits; one that could never fit is refused. Default 1.5 GiB.
void setMemoryBudget(uint64_t bytes);

// Size of the thumbnail for a source of w x h: the longest side becomes `target` unless it is already smaller.
void fitWithin(int w, int h, int target, int& outW, int& outH);

}  // namespace veimg
