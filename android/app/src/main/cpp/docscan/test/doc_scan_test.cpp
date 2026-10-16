// Host-side test, no Android toolchain required. From cpp/, all on one line:
//   g++ -std=c++17 -O1 -I. docscan/test/doc_scan_test.cpp docscan/doc_scan.cpp docscan/doc_pdf.cpp -o doc_scan_test && ./doc_scan_test
// (also wired into CMakeLists.txt's `if(NOT ANDROID)` host-test block.)
//
// Builds a synthetic "page on a desk" scene in memory and checks:
//   - quad detection from RGBA and from a strided luma frame, plus no false
//     positives on empty/noisy frames
//   - corner ordering and clockwise frame rotation helpers
//   - output size (incl. the long-side cap) and perspective-warp orientation
//   - the paper-whitening filters (shadow removed, ink kept, B&W near-bitonal)
//   - the PDF writer's structure (header, xref offsets, trailer, page count)
#include "docscan/doc_pdf.h"
#include "docscan/doc_scan.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

// Always evaluated (not assert()): Release builds define NDEBUG.
#define CHECK(cond) do { \
    if (!(cond)) { \
        std::fprintf(stderr, "CHECK FAILED at %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        std::abort(); \
    } \
} while (0)

using namespace docscan;

namespace {

constexpr int kW = 800;
constexpr int kH = 600;

struct Img {
    int w, h;
    std::vector<uint8_t> rgba;
    Img(int w_, int h_) : w(w_), h(h_), rgba(static_cast<size_t>(w_) * h_ * 4, 255) {}
    uint8_t* px(int x, int y) { return &rgba[(static_cast<size_t>(y) * w + x) * 4]; }
    const uint8_t* px(int x, int y) const { return &rgba[(static_cast<size_t>(y) * w + x) * 4]; }
};

// Tiny deterministic noise so the scene isn't perfectly flat.
uint32_t lcg(uint32_t* s) {
    *s = *s * 1664525u + 1013904223u;
    return *s >> 8;
}

bool insideConvex(const float q[4][2], float x, float y) {
    for (int i = 0; i < 4; ++i) {
        const float* a = q[i];
        const float* b = q[(i + 1) % 4];
        if ((b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0]) < 0) return false;
    }
    return true;
}

// Page quad in pixels: TL, TR, BR, BL.
const float kPage[4][2] = {{150, 90}, {660, 120}, {620, 520}, {120, 480}};

// White page with ink lines and a red marker at the page's top-left, on a dark
// desk, lit by a horizontal gradient (shadow on the right).
Img makeScene(float shadowRight = 0.6f) {
    Img img(kW, kH);
    uint32_t seed = 7;
    for (int y = 0; y < kH; ++y) {
        for (int x = 0; x < kW; ++x) {
            const float light = 1.0f - (1.0f - shadowRight) * (static_cast<float>(x) / kW);
            float r = 55, g = 58, b = 62;  // desk
            if (insideConvex(kPage, x + 0.5f, y + 0.5f)) {
                r = 238;
                g = 238;
                b = 232;
                // ink: horizontal lines inside the page, away from the borders
                if ((y % 28) > 17 && x > 190 && x < 590 && y > 160 && y < 440) r = g = b = 40;
                // red marker at the page's top-left corner
                if (x > 175 && x < 235 && y > 110 && y < 150) {
                    r = 220;
                    g = 30;
                    b = 30;
                }
            }
            const int noise = static_cast<int>(lcg(&seed) % 5) - 2;
            uint8_t* p = img.px(x, y);
            p[0] = static_cast<uint8_t>(std::clamp(static_cast<int>(r * light) + noise, 0, 255));
            p[1] = static_cast<uint8_t>(std::clamp(static_cast<int>(g * light) + noise, 0, 255));
            p[2] = static_cast<uint8_t>(std::clamp(static_cast<int>(b * light) + noise, 0, 255));
        }
    }
    return img;
}

double cornerError(const Detection& d, int w, int h) {
    double worst = 0;
    for (int i = 0; i < 4; ++i) {
        const double dx = d.quad.p[i].x * w - kPage[i][0];
        const double dy = d.quad.p[i].y * h - kPage[i][1];
        worst = std::max(worst, std::hypot(dx, dy));
    }
    return worst;
}

void testDetectRgba() {
    const Img img = makeScene();
    const Detection d = detectFromRgba(img.rgba.data(), img.w, img.h, img.w * 4);
    CHECK(d.found);
    CHECK(d.score > 0.4f);
    // Sub-pixel: the coarse 480 px detection alone is ~3.7 px off here, so this
    // bound fails if the refinement stage regresses or is skipped.
    CHECK(cornerError(d, img.w, img.h) < 0.5);
}

void testDetectGrayStrided() {
    const Img img = makeScene();
    const int stride = img.w + 8;  // real camera planes have padded rows
    std::vector<uint8_t> luma(static_cast<size_t>(stride) * img.h, 0);
    for (int y = 0; y < img.h; ++y)
        for (int x = 0; x < img.w; ++x) {
            const uint8_t* p = img.px(x, y);
            luma[static_cast<size_t>(y) * stride + x] = static_cast<uint8_t>((77 * p[0] + 150 * p[1] + 29 * p[2]) >> 8);
        }
    const Detection d = detectFromGray(luma.data(), img.w, img.h, stride);
    CHECK(d.found);
    CHECK(cornerError(d, img.w, img.h) < 12.0);  // live path is coarser (no refinement)
}

void testNoFalsePositives() {
    Img flat(kW, kH);
    for (size_t i = 0; i < flat.rgba.size(); i += 4) flat.rgba[i] = flat.rgba[i + 1] = flat.rgba[i + 2] = 128;
    CHECK(!detectFromRgba(flat.rgba.data(), kW, kH, kW * 4).found);

    Img noisy(kW, kH);
    uint32_t seed = 99;
    for (size_t i = 0; i < noisy.rgba.size(); i += 4)
        noisy.rgba[i] = noisy.rgba[i + 1] = noisy.rgba[i + 2] = static_cast<uint8_t>(110 + lcg(&seed) % 40);
    CHECK(!detectFromRgba(noisy.rgba.data(), kW, kH, kW * 4).found);

    // A bright, textured desk with dark corners and no page at all. Padding the
    // frame creates a strong artificial edge at its border; if that counted as
    // edge support, the lit area would be reported as a ~98%-of-frame document.
    Img desk(kW, kH);
    seed = 5;
    for (int y = 0; y < kH; ++y)
        for (int x = 0; x < kW; ++x) {
            const double nx = (x - kW / 2.0) / (kW / 2.0), ny = (y - kH / 2.0) / (kH / 2.0);
            const double r = std::pow(std::sqrt(nx * nx + ny * ny) / std::sqrt(2.0), 4.0);
            double v = (205 + 9 * std::sin(x / 31.0) + 5.4 * std::sin(y / 23.0)) * (1.0 - 0.45 * r);
            v += static_cast<int>(lcg(&seed) % 5) - 2;
            uint8_t* px = desk.px(x, y);
            px[0] = px[1] = px[2] = static_cast<uint8_t>(std::clamp(v, 0.0, 255.0));
        }
    CHECK(!detectFromRgba(desk.rgba.data(), kW, kH, kW * 4).found);

    // Degenerate inputs must not crash.
    CHECK(!detectFromRgba(nullptr, kW, kH, kW * 4).found);
    uint8_t tiny[4] = {0, 0, 0, 255};
    CHECK(!detectFromRgba(tiny, 1, 1, 4).found);
    CHECK(!detectFromGray(nullptr, kW, kH, kW).found);
}

void testRotateNormalized() {
    const PointF p{0.2f, 0.7f};
    PointF q = rotateNormalized(p, 90);
    CHECK(std::fabs(q.x - 0.3f) < 1e-6f && std::fabs(q.y - 0.2f) < 1e-6f);
    q = rotateNormalized(p, 180);
    CHECK(std::fabs(q.x - 0.8f) < 1e-6f && std::fabs(q.y - 0.3f) < 1e-6f);
    q = rotateNormalized(p, 270);
    CHECK(std::fabs(q.x - 0.7f) < 1e-6f && std::fabs(q.y - 0.8f) < 1e-6f);
    // Four quarter turns are the identity; negative angles wrap.
    q = p;
    for (int i = 0; i < 4; ++i) q = rotateNormalized(q, 90);
    CHECK(std::fabs(q.x - p.x) < 1e-5f && std::fabs(q.y - p.y) < 1e-5f);
    q = rotateNormalized(p, -90);
    const PointF r = rotateNormalized(p, 270);
    CHECK(q.x == r.x && q.y == r.y);
    // A raw-frame top-left corner of a 90-degree sensor lands top-right.
    q = rotateNormalized({0.f, 0.f}, 90);
    CHECK(q.x == 1.f && q.y == 0.f);
}

void testOrderCorners() {
    const PointF shuffled[4] = {{0.9f, 0.9f}, {0.1f, 0.1f}, {0.1f, 0.8f}, {0.9f, 0.2f}};
    const Quad q = orderCorners(shuffled);
    CHECK(q.p[0].x == 0.1f && q.p[0].y == 0.1f);  // TL
    CHECK(q.p[1].x == 0.9f && q.p[1].y == 0.2f);  // TR
    CHECK(q.p[2].x == 0.9f && q.p[2].y == 0.9f);  // BR
    CHECK(q.p[3].x == 0.1f && q.p[3].y == 0.8f);  // BL
}

Quad pageQuadNorm() {
    Quad q;
    for (int i = 0; i < 4; ++i) {
        q.p[i].x = kPage[i][0] / kW;
        q.p[i].y = kPage[i][1] / kH;
    }
    return q;
}

void testOutputSize() {
    // Fronto-parallel rectangle: sizes are the side lengths.
    Quad rect;
    rect.p[0] = {0.1f, 0.1f};
    rect.p[1] = {0.6f, 0.1f};
    rect.p[2] = {0.6f, 0.9f};
    rect.p[3] = {0.1f, 0.9f};
    int w = 0, h = 0;
    outputSize(rect, 1000, 1000, 4000, &w, &h);
    CHECK(std::abs(w - 500) <= 2 && std::abs(h - 800) <= 2);
    // Long side is capped, aspect preserved.
    outputSize(rect, 1000, 1000, 400, &w, &h);
    CHECK(h == 400 && std::abs(w - 250) <= 2);
    // Perspective quad gives a plausible page size, never zero.
    outputSize(pageQuadNorm(), kW, kH, 4000, &w, &h);
    CHECK(w > 100 && h > 100 && w < 2000 && h < 2000);
}

// Projects an A4 page (210 x 297) tilted in 3D through a pinhole camera whose
// principal point is the image centre, i.e. the geometry outputSize() assumes.
Quad projectTiltedPage(int w, int h, double f, double rx, double ry, double rz, double dist) {
    const double hw = 105.0, hh = 148.5;
    const double pts[4][3] = {{-hw, -hh, 0}, {hw, -hh, 0}, {hw, hh, 0}, {-hw, hh, 0}};
    const double cx = std::cos(rx), sx = std::sin(rx), cy = std::cos(ry), sy = std::sin(ry);
    const double cz = std::cos(rz), sz = std::sin(rz);
    Quad q;
    for (int i = 0; i < 4; ++i) {
        double x = pts[i][0], y = pts[i][1], z = pts[i][2];
        double y1 = cx * y - sx * z, z1 = sx * y + cx * z;       // about x
        double x2 = cy * x + sy * z1, z2 = -sy * x + cy * z1;    // about y
        double x3 = cz * x2 - sz * y1, y3 = sz * x2 + cz * y1;   // about z
        z2 += dist;
        q.p[i].x = static_cast<float>((f * x3 / z2 + w / 2.0) / w);
        q.p[i].y = static_cast<float>((f * y3 / z2 + h / 2.0) / h);
    }
    return q;
}

void testAspectRecovery() {
    const double kTrue = 210.0 / 297.0;
    const double poses[3][3] = {{0.55, 0.30, 0.08}, {-0.45, 0.35, -0.10}, {0.62, -0.25, 0.05}};
    for (const auto& pose : poses) {
        const Quad q = projectTiltedPage(kW, kH, 900.0, pose[0], pose[1], pose[2], 520.0);
        for (int i = 0; i < 4; ++i) CHECK(q.p[i].x > 0.f && q.p[i].x < 1.f && q.p[i].y > 0.f && q.p[i].y < 1.f);
        int w = 0, h = 0;
        outputSize(q, kW, kH, 4000, &w, &h);
        const double ratio = static_cast<double>(std::min(w, h)) / std::max(w, h);
        CHECK(std::fabs(ratio / kTrue - 1.0) < 0.02);  // within 2% of the true A4 aspect
        CHECK(h > w);                                    // upright portrait page stays portrait
    }
}

void testWarpOrientationAndContent() {
    const Img img = makeScene(1.0f);  // no shadow, to test geometry only
    const Quad q = pageQuadNorm();
    int ow = 0, oh = 0;
    outputSize(q, img.w, img.h, 1000, &ow, &oh);
    std::vector<uint8_t> out(static_cast<size_t>(ow) * oh * 4);
    CHECK(warpQuad(img.rgba.data(), img.w, img.h, img.w * 4, q, out.data(), ow, oh));
    auto at = [&](int x, int y) { return &out[(static_cast<size_t>(y) * ow + x) * 4]; };

    // The red marker sits at the page's top-left: it must land top-left.
    const uint8_t* tl = at(ow / 12, oh / 14);
    CHECK(tl[0] > 150 && tl[1] < 90 && tl[2] < 90);
    // The other corners are paper, not desk: the quad was mapped tightly.
    const int m = 4;
    const uint8_t* corners[3] = {at(ow - 1 - m, m), at(ow - 1 - m, oh - 1 - m), at(m, oh - 1 - m)};
    for (const uint8_t* c : corners) CHECK(c[0] > 200 && c[1] > 200);
    CHECK(at(m, m)[0] > 150);  // top-left corner pixel is paper/marker, not desk
    // Bad input is rejected instead of crashing.
    CHECK(!warpQuad(nullptr, 10, 10, 40, q, out.data(), ow, oh));
    CHECK(!warpQuad(img.rgba.data(), img.w, img.h, img.w * 4, q, out.data(), 0, oh));
}

double lumaAt(const std::vector<uint8_t>& im, int w, int x, int y) {
    const uint8_t* p = &im[(static_cast<size_t>(y) * w + x) * 4];
    return 0.3 * p[0] + 0.59 * p[1] + 0.11 * p[2];
}

void testFilters() {
    const Img img = makeScene(0.55f);  // pronounced shadow to the right
    const Quad q = pageQuadNorm();
    int ow = 0, oh = 0;
    outputSize(q, img.w, img.h, 800, &ow, &oh);
    std::vector<uint8_t> base(static_cast<size_t>(ow) * oh * 4);
    CHECK(warpQuad(img.rgba.data(), img.w, img.h, img.w * 4, q, base.data(), ow, oh));

    // Original is a no-op.
    std::vector<uint8_t> orig = base;
    applyFilter(orig.data(), ow, oh, Filter::Original);
    CHECK(orig == base);

    // Blank margin points (no ink): left side is lit, right side is in shadow.
    const double leftBefore = lumaAt(base, ow, ow / 12, oh * 2 / 3);
    const double rightBefore = lumaAt(base, ow, ow - ow / 12, oh * 2 / 3);
    CHECK(leftBefore - rightBefore > 40);  // the shadow really is there

    for (Filter f : {Filter::Color, Filter::Gray, Filter::BlackWhite}) {
        std::vector<uint8_t> v = base;
        applyFilter(v.data(), ow, oh, f);
        const double left = lumaAt(v, ow, ow / 12, oh * 2 / 3);
        const double right = lumaAt(v, ow, ow - ow / 12, oh * 2 / 3);
        CHECK(left > 242 && right > 242);  // paper is white on both sides now
        CHECK(std::fabs(left - right) < 8);  // ...and evenly so: the shadow is gone
        if (f == Filter::Color) {
            // Every channel, not just luma, is normalised.
            const uint8_t* pr = &v[(static_cast<size_t>(oh * 2 / 3) * ow + (ow - ow / 12)) * 4];
            CHECK(pr[0] > 242 && pr[1] > 242 && pr[2] > 242);
        }
        // Ink survives: a point on an ink line is dark.
        bool foundInk = false;
        for (int y = oh / 4; y < oh * 3 / 4 && !foundInk; ++y)
            if (lumaAt(v, ow, ow / 2, y) < 90) foundInk = true;
        CHECK(foundInk);
        // Alpha stays opaque.
        CHECK(v[3] == 255 && v[v.size() - 1] == 255);
    }

    // Gray/B&W are monochrome; B&W is nearly bitonal.
    std::vector<uint8_t> gray = base, bw = base;
    applyFilter(gray.data(), ow, oh, Filter::Gray);
    applyFilter(bw.data(), ow, oh, Filter::BlackWhite);
    size_t mono = 0, extreme = 0, total = static_cast<size_t>(ow) * oh;
    for (size_t i = 0; i < total; ++i) {
        mono += (gray[i * 4] == gray[i * 4 + 1] && gray[i * 4 + 1] == gray[i * 4 + 2]);
        extreme += (bw[i * 4] < 25 || bw[i * 4] > 230);
    }
    CHECK(mono == total);
    CHECK(extreme > total * 9 / 10);
}

size_t countOf(const std::string& hay, const std::string& needle) {
    size_t n = 0;
    for (size_t pos = hay.find(needle); pos != std::string::npos; pos = hay.find(needle, pos + 1)) ++n;
    return n;
}

// Smallest thing readJpegInfo accepts: SOI, an APP0 and a DHT marker to skip,
// then a frame header (SOF `sof`) for w x h with `comps` components, then EOI.
std::vector<uint8_t> fakeJpeg(int w, int h, int comps, size_t padding = 0, uint8_t sof = 0xC0) {
    std::vector<uint8_t> j = {0xFF, 0xD8};
    const uint8_t app0[] = {0xFF, 0xE0, 0x00, 0x06, 'J', 'F', 'I', 'F'};
    j.insert(j.end(), app0, app0 + sizeof(app0));
    // A DHT marker (0xFFC4) sits among the 0xC0..0xCF markers but is NOT a frame header.
    const uint8_t dht[] = {0xFF, 0xC4, 0x00, 0x04, 0x00, 0x00};
    j.insert(j.end(), dht, dht + sizeof(dht));
    const size_t len = 8 + 3 * static_cast<size_t>(comps);
    j.push_back(0xFF);
    j.push_back(sof);
    j.push_back(static_cast<uint8_t>(len >> 8));
    j.push_back(static_cast<uint8_t>(len));
    j.push_back(8);  // precision
    j.push_back(static_cast<uint8_t>(h >> 8));
    j.push_back(static_cast<uint8_t>(h));
    j.push_back(static_cast<uint8_t>(w >> 8));
    j.push_back(static_cast<uint8_t>(w));
    j.push_back(static_cast<uint8_t>(comps));
    for (int c = 0; c < comps; ++c) {
        j.push_back(static_cast<uint8_t>(c + 1));
        j.push_back(0x11);
        j.push_back(0);
    }
    j.insert(j.end(), padding, 0x5A);  // stand-in for entropy-coded data
    j.push_back(0xFF);
    j.push_back(0xD9);
    return j;
}

void testJpegInfo() {
    int w = 0, h = 0, c = 0;
    std::vector<uint8_t> rgb = fakeJpeg(1600, 900, 3);
    CHECK(readJpegInfo(rgb.data(), rgb.size(), &w, &h, &c));
    CHECK(w == 1600 && h == 900 && c == 3);
    std::vector<uint8_t> gray = fakeJpeg(321, 654, 1);
    CHECK(readJpegInfo(gray.data(), gray.size(), &w, &h, &c));
    CHECK(w == 321 && h == 654 && c == 1);
    std::vector<uint8_t> progressive = fakeJpeg(800, 600, 3, 0, 0xC2);
    CHECK(readJpegInfo(progressive.data(), progressive.size(), &w, &h, &c));

    // Not embeddable: wrong signature (PNG), CMYK, arithmetic coding, lossless,
    // truncated mid-header, zero size, garbage, null.
    const uint8_t png[] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0};
    CHECK(!readJpegInfo(png, sizeof(png), &w, &h, &c));
    std::vector<uint8_t> cmyk = fakeJpeg(100, 100, 4);
    CHECK(!readJpegInfo(cmyk.data(), cmyk.size(), &w, &h, &c));
    std::vector<uint8_t> arith = fakeJpeg(100, 100, 3, 0, 0xC9);
    CHECK(!readJpegInfo(arith.data(), arith.size(), &w, &h, &c));
    std::vector<uint8_t> lossless = fakeJpeg(100, 100, 3, 0, 0xC3);
    CHECK(!readJpegInfo(lossless.data(), lossless.size(), &w, &h, &c));
    std::vector<uint8_t> cut(rgb.begin(), rgb.begin() + 20);
    CHECK(!readJpegInfo(cut.data(), cut.size(), &w, &h, &c));
    std::vector<uint8_t> zero = fakeJpeg(0, 50, 3);
    CHECK(!readJpegInfo(zero.data(), zero.size(), &w, &h, &c));
    const uint8_t junk[] = {0xFF, 0xD8, 0x12, 0x34, 0x56, 0x78};
    CHECK(!readJpegInfo(junk, sizeof(junk), &w, &h, &c));
    CHECK(!readJpegInfo(nullptr, 0, &w, &h, &c));
}

void testPdf() {
    CHECK(buildPdf({}).empty());
    PdfPage bad;  // null jpeg
    CHECK(buildPdf({bad}).empty());
    const uint8_t png[] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0};
    PdfPage notJpeg{png, sizeof(png)};
    CHECK(buildPdf({notJpeg}).empty());

    // Page sizes come from the JPEG headers (the caller can't pass wrong ones).
    std::vector<uint8_t> j1 = fakeJpeg(1000, 1414, 3, 40);
    std::vector<uint8_t> j2 = fakeJpeg(1600, 900, 1, 3000);
    PdfPage p1{j1.data(), j1.size()};
    PdfPage p2{j2.data(), j2.size()};
    CHECK(buildPdf({p1, notJpeg}).empty());  // one bad page rejects the whole document
    const std::vector<uint8_t> pdf = buildPdf({p1, p2});
    CHECK(pdf.size() > 100);
    const std::string s(pdf.begin(), pdf.end());

    CHECK(s.compare(0, 8, "%PDF-1.4") == 0);
    CHECK(s.rfind("%%EOF\n") == s.size() - 6);
    CHECK(countOf(s, "/Type /Page ") == 2);
    CHECK(s.find("/Count 2") != std::string::npos);
    CHECK(s.find("/Filter /DCTDecode") != std::string::npos);
    CHECK(s.find("/Width 1000 /Height 1414 /ColorSpace /DeviceRGB") != std::string::npos);
    CHECK(s.find("/Width 1600 /Height 900 /ColorSpace /DeviceGray") != std::string::npos);
    // No identifying metadata.
    CHECK(s.find("/Info") == std::string::npos && s.find("/Producer") == std::string::npos &&
          s.find("/CreationDate") == std::string::npos && s.find("/Author") == std::string::npos);
    // Landscape page: long side 842, short side proportional (900/1600*842 = 473.62).
    CHECK(s.find("/MediaBox [0 0 842.00 473.63]") != std::string::npos ||
          s.find("/MediaBox [0 0 842.00 473.62]") != std::string::npos);
    CHECK(s.find("/MediaBox [0 0 595.47 842.00]") != std::string::npos);

    // Every xref entry points exactly at "<id> 0 obj".
    const size_t startx = s.rfind("startxref\n");
    CHECK(startx != std::string::npos);
    const size_t xrefPos = static_cast<size_t>(std::strtoull(s.c_str() + startx + 10, nullptr, 10));
    CHECK(s.compare(xrefPos, 5, "xref\n") == 0);
    const int objects = 2 + 2 * 3;
    CHECK(s.find("0 " + std::to_string(objects + 1) + "\n", xrefPos) != std::string::npos);
    const size_t table = s.find("0000000000 65535 f \n", xrefPos);
    CHECK(table != std::string::npos);
    for (int id = 1; id <= objects; ++id) {
        const size_t entry = table + 20 * static_cast<size_t>(id);
        const size_t off = static_cast<size_t>(std::strtoull(s.c_str() + entry, nullptr, 10));
        const std::string want = std::to_string(id) + " 0 obj\n";
        CHECK(s.compare(off, want.size(), want) == 0);
    }
    // The first JPEG is embedded byte-for-byte.
    const std::string j1s(j1.begin(), j1.end());
    CHECK(s.find(j1s) != std::string::npos);
}

}  // namespace

int main() {
    testDetectRgba();
    testDetectGrayStrided();
    testNoFalsePositives();
    testRotateNormalized();
    testOrderCorners();
    testOutputSize();
    testAspectRecovery();
    testWarpOrientationAndContent();
    testFilters();
    testJpegInfo();
    testPdf();
    std::puts("doc_scan_test: all checks passed");
    return 0;
}
