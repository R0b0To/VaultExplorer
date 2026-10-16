// Document scanner core: edge/quad detection, perspective correction and
// paper-whitening filters. Pure C++17, no third-party dependencies and no JNI,
// so it can be unit-tested on the host (see test/doc_scan_test.cpp).
//
// The pipeline mirrors the one used by OSS Document Scanner (multi-pass
// threshold + edge candidates, convex-quad fitting, angle/area scoring) but is
// self-contained so the app keeps its "every native dependency is built from a
// pinned source" property without pulling in OpenCV.
//
// Everything operates on caller-owned memory; nothing is written to disk.
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace docscan {

struct PointF {
    float x = 0.f;
    float y = 0.f;
};

// Corners in clockwise order starting at the top-left: TL, TR, BR, BL.
struct Quad {
    PointF p[4];
};

struct Detection {
    bool found = false;
    Quad quad{};          // normalised to 0..1 of the analysed frame
    float score = 0.f;    // 0..1, higher is more convincing
};

enum class Filter : int {
    Original = 0,   // untouched perspective-corrected pixels
    Color = 1,      // shadows removed, paper whitened, ink colour kept
    Gray = 2,       // same as Color, but monochrome
    BlackWhite = 3, // near-bitonal, for text documents
};

// Detects the most document-like quadrilateral in an 8-bit luminance frame
// (e.g. the Y plane of a YUV_420_888 preview frame). Fast enough for live use.
Detection detectFromGray(const uint8_t* gray, int width, int height, int rowStride);

// Detects in an RGBA_8888 image (a captured photo). Also tries individual
// colour channels when luminance alone is not convincing, like OSS does.
Detection detectFromRgba(const uint8_t* rgba, int width, int height, int rowStride);

// Rotates normalised frame coordinates clockwise by 0/90/180/270 degrees,
// i.e. maps a point of a raw sensor frame into the upright frame.
PointF rotateNormalized(PointF p, int clockwiseDegrees);

// Orders four arbitrary points clockwise starting from the top-left-most one.
Quad orderCorners(const PointF pts[4]);

// Size of the perspective-corrected output for a normalised quad on a
// srcW x srcH image. Aspect ratio is recovered from the perspective when the
// geometry allows it (falls back to the longest opposite sides). The longer
// side never exceeds maxLongSide.
void outputSize(const Quad& quadNorm, int srcW, int srcH, int maxLongSide,
                int* outW, int* outH);

// Warps the normalised quad of an RGBA image onto an outW x outH rectangle
// (bilinear). dst must hold outW*outH*4 bytes. Returns false on bad input.
bool warpQuad(const uint8_t* src, int srcW, int srcH, int srcStride,
              const Quad& quadNorm, uint8_t* dst, int outW, int outH);

// In-place filter on a tightly packed RGBA image.
void applyFilter(uint8_t* rgba, int width, int height, Filter filter);

}  // namespace docscan
