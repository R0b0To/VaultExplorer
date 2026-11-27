// Host-side test for imaging/thumb.cpp, no Android toolchain required. From cpp/, all on one line:
//   g++ -std=c++17 -O2 -I. imaging/test/thumb_test.cpp imaging/thumb.cpp -ljpeg -lpng -lwebp -lz -lpthread -o thumb_test && ./thumb_test
// (also wired into CMakeLists.txt's desktop block as `thumb_test`.)  `./thumb_test bench` prints timings.
//
// The fixtures are made here, with the libraries' own ENCODERS (not the code under test), from a synthetic
// picture whose four quadrants have known colours:
//   - every format at several sizes: output dimensions, true source size, colours, JPEG vs PNG output
//   - baseline, progressive, grayscale JPEG; the 8 EXIF orientations in both byte orders (checked against an
//     independent forward mapping of the quadrants)
//   - PNG: RGB, RGBA with real transparency (kept, PNG out), RGBA that is fully opaque (JPEG out), gray, palette,
//     interlaced, 16-bit
//   - WebP: lossy, lossless, with alpha
//   - failures: garbage, empty, truncated JPEG / PNG / WebP, size guards, a source whose reads fail
//   - many threads at once (run it under ASan / TSan to check the shared memory budget)
#include "imaging/thumb.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <csetjmp>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include <jpeglib.h>  // after <cstdio>: it needs FILE
#include <png.h>
#include <webp/encode.h>

// Always evaluated (not assert()): Release builds define NDEBUG.
#define CHECK(cond) do { \
    if (!(cond)) { \
        std::fprintf(stderr, "CHECK FAILED at %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        std::abort(); \
    } \
} while (0)

using namespace veimg;

namespace {

struct Rgb {
    int r, g, b;
};
const Rgb kTL{220, 30, 30}, kTR{30, 200, 30}, kBL{30, 30, 220}, kBR{230, 230, 30};

// w x h RGBA; four flat quadrants plus a little noise (so JPEG / PNG have real work to do).
std::vector<uint8_t> scene(int w, int h, uint8_t alpha = 255, int noise = 10) {
    std::vector<uint8_t> px(static_cast<size_t>(w) * h * 4);
    uint32_t seed = 12345;
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const Rgb& c = y < h / 2 ? (x < w / 2 ? kTL : kTR) : (x < w / 2 ? kBL : kBR);
            seed = seed * 1664525u + 1013904223u;
            const int n = noise ? static_cast<int>((seed >> 24) % (2 * noise + 1)) - noise : 0;
            uint8_t* p = &px[(static_cast<size_t>(y) * w + x) * 4];
            p[0] = static_cast<uint8_t>(std::clamp(c.r + n, 0, 255));
            p[1] = static_cast<uint8_t>(std::clamp(c.g + n, 0, 255));
            p[2] = static_cast<uint8_t>(std::clamp(c.b + n, 0, 255));
            p[3] = alpha;
        }
    }
    return px;
}

std::vector<uint8_t> toRgb(const std::vector<uint8_t>& rgba) {
    std::vector<uint8_t> rgb(rgba.size() / 4 * 3);
    for (size_t i = 0, o = 0; i < rgba.size(); i += 4, o += 3) {
        rgb[o] = rgba[i];
        rgb[o + 1] = rgba[i + 1];
        rgb[o + 2] = rgba[i + 2];
    }
    return rgb;
}

// ── fixture encoders ─────────────────────────────────────────────────────

struct JErr {
    jpeg_error_mgr pub;
    std::jmp_buf jb;
};
void jErrExit(j_common_ptr c) { std::longjmp(reinterpret_cast<JErr*>(c->err)->jb, 1); }

std::vector<uint8_t> exifApp1(int orientation, bool littleEndian) {
    std::vector<uint8_t> d = {'E', 'x', 'i', 'f', 0, 0};
    auto put16 = [&](uint32_t v) {
        if (littleEndian) { d.push_back(v & 0xFF); d.push_back((v >> 8) & 0xFF); }
        else { d.push_back((v >> 8) & 0xFF); d.push_back(v & 0xFF); }
    };
    auto put32 = [&](uint32_t v) {
        if (littleEndian) for (int i = 0; i < 4; ++i) d.push_back((v >> (8 * i)) & 0xFF);
        else for (int i = 3; i >= 0; --i) d.push_back((v >> (8 * i)) & 0xFF);
    };
    d.push_back(littleEndian ? 'I' : 'M');
    d.push_back(littleEndian ? 'I' : 'M');
    put16(42);
    put32(8);
    put16(1);       // one entry
    put16(0x0112);  // Orientation
    put16(3);       // SHORT
    put32(1);
    put16(static_cast<uint32_t>(orientation));
    put16(0);
    put32(0);       // no next IFD
    return d;
}

std::vector<uint8_t> makeJpeg(const std::vector<uint8_t>& rgb, int w, int h, int quality = 90, bool progressive = false,
                              bool gray = false, int orientation = 0, bool le = false, int h2v1 = 0) {
    jpeg_compress_struct ci;
    JErr err;
    std::memset(&ci, 0, sizeof(ci));
    ci.err = jpeg_std_error(&err.pub);
    err.pub.error_exit = jErrExit;
    CHECK(!setjmp(err.jb));
    jpeg_create_compress(&ci);
    unsigned char* mem = nullptr;
    unsigned long len = 0;
    jpeg_mem_dest(&ci, &mem, &len);
    ci.image_width = w;
    ci.image_height = h;
    ci.input_components = gray ? 1 : 3;
    ci.in_color_space = gray ? JCS_GRAYSCALE : JCS_RGB;
    jpeg_set_defaults(&ci);
    jpeg_set_quality(&ci, quality, TRUE);
    if (progressive) jpeg_simple_progression(&ci);
    if (h2v1 && !gray) { ci.comp_info[0].h_samp_factor = 2; ci.comp_info[0].v_samp_factor = 1; }
    jpeg_start_compress(&ci, TRUE);
    if (orientation) {
        const auto app1 = exifApp1(orientation, le);
        jpeg_write_marker(&ci, JPEG_APP0 + 1, app1.data(), static_cast<unsigned>(app1.size()));
    }
    std::vector<uint8_t> grayRow(static_cast<size_t>(w));
    while (ci.next_scanline < ci.image_height) {
        const uint8_t* row = &rgb[static_cast<size_t>(ci.next_scanline) * w * 3];
        if (gray) {
            for (int x = 0; x < w; ++x) grayRow[x] = static_cast<uint8_t>((row[x * 3] * 3 + row[x * 3 + 1] * 6 + row[x * 3 + 2]) / 10);
            row = grayRow.data();
        }
        JSAMPROW rp = const_cast<uint8_t*>(row);
        jpeg_write_scanlines(&ci, &rp, 1);
    }
    jpeg_finish_compress(&ci);
    std::vector<uint8_t> out(mem, mem + len);
    jpeg_destroy_compress(&ci);
    std::free(mem);
    return out;
}

void pngWriteCb(png_structp p, png_bytep d, size_t n) {
    auto* v = static_cast<std::vector<uint8_t>*>(png_get_io_ptr(p));
    v->insert(v->end(), d, d + n);
}
void pngFlushCb(png_structp) {}

enum class PngKind { kRgb, kRgba, kGray, kPalette, kRgb16 };

std::vector<uint8_t> makePng(const std::vector<uint8_t>& rgba, int w, int h, PngKind kind, bool interlaced = false) {
    std::vector<uint8_t> out;
    png_structp p = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, nullptr, nullptr);
    png_infop info = png_create_info_struct(p);
    CHECK(!setjmp(png_jmpbuf(p)));
    png_set_write_fn(p, &out, pngWriteCb, pngFlushCb);
    int type = PNG_COLOR_TYPE_RGB, depth = 8, bpp = 3;
    switch (kind) {
        case PngKind::kRgb: break;
        case PngKind::kRgba: type = PNG_COLOR_TYPE_RGB_ALPHA; bpp = 4; break;
        case PngKind::kGray: type = PNG_COLOR_TYPE_GRAY; bpp = 1; break;
        case PngKind::kPalette: type = PNG_COLOR_TYPE_PALETTE; bpp = 1; break;
        case PngKind::kRgb16: type = PNG_COLOR_TYPE_RGB; depth = 16; bpp = 6; break;
    }
    png_set_IHDR(p, info, w, h, depth, type, interlaced ? PNG_INTERLACE_ADAM7 : PNG_INTERLACE_NONE,
                 PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
    if (kind == PngKind::kPalette) {
        auto c8 = [](const Rgb& c) { return png_color{static_cast<png_byte>(c.r), static_cast<png_byte>(c.g), static_cast<png_byte>(c.b)}; };
        png_color pal[4] = {c8(kTL), c8(kTR), c8(kBL), c8(kBR)};
        png_set_PLTE(p, info, pal, 4);
    }
    png_write_info(p, info);
    const int passes = interlaced ? png_set_interlace_handling(p) : 1;
    std::vector<uint8_t> row(static_cast<size_t>(w) * bpp);
    for (int pass = 0; pass < passes; ++pass) {
        for (int y = 0; y < h; ++y) {
            const uint8_t* s = &rgba[static_cast<size_t>(y) * w * 4];
            for (int x = 0; x < w; ++x) {
                const uint8_t* px = s + x * 4;
                switch (kind) {
                    case PngKind::kRgb: row[x * 3] = px[0]; row[x * 3 + 1] = px[1]; row[x * 3 + 2] = px[2]; break;
                    case PngKind::kRgba: std::memcpy(&row[x * 4], px, 4); break;
                    case PngKind::kGray: row[x] = static_cast<uint8_t>((px[0] * 3 + px[1] * 6 + px[2]) / 10); break;
                    case PngKind::kPalette: row[x] = static_cast<uint8_t>(y < h / 2 ? (x < w / 2 ? 0 : 1) : (x < w / 2 ? 2 : 3)); break;
                    case PngKind::kRgb16:
                        for (int c = 0; c < 3; ++c) { row[x * 6 + c * 2] = px[c]; row[x * 6 + c * 2 + 1] = px[c]; }
                        break;
                }
            }
            png_write_row(p, row.data());
        }
    }
    png_write_end(p, nullptr);
    png_destroy_write_struct(&p, &info);
    return out;
}

std::vector<uint8_t> makeWebp(const std::vector<uint8_t>& rgba, int w, int h, bool lossless, bool alpha) {
    WebPConfig cfg;
    CHECK(WebPConfigInit(&cfg));
    cfg.lossless = lossless ? 1 : 0;
    cfg.quality = lossless ? 20.f : 85.f;
    cfg.exact = 1;  // keep colour under transparent pixels
    WebPPicture pic;
    CHECK(WebPPictureInit(&pic));
    pic.width = w;
    pic.height = h;
    pic.use_argb = lossless ? 1 : 0;
    CHECK(WebPPictureAlloc(&pic));
    if (alpha) CHECK(WebPPictureImportRGBA(&pic, rgba.data(), w * 4));
    else CHECK(WebPPictureImportRGB(&pic, toRgb(rgba).data(), w * 3));
    WebPMemoryWriter mw;
    WebPMemoryWriterInit(&mw);
    pic.writer = WebPMemoryWrite;
    pic.custom_ptr = &mw;
    CHECK(WebPEncode(&cfg, &pic));
    std::vector<uint8_t> out(mw.mem, mw.mem + mw.size);
    WebPMemoryWriterClear(&mw);
    WebPPictureFree(&pic);
    return out;
}

// ── output decoding (also libraries' own decoders) ────────────────────────

struct Decoded {
    int w = 0, h = 0, ch = 0;
    std::vector<uint8_t> px;  // RGB or RGBA
};

Decoded decodeJpegOut(const std::vector<uint8_t>& jpg) {
    Decoded d;
    jpeg_decompress_struct ci;
    JErr err;
    std::memset(&ci, 0, sizeof(ci));
    ci.err = jpeg_std_error(&err.pub);
    err.pub.error_exit = jErrExit;
    CHECK(!setjmp(err.jb));
    jpeg_create_decompress(&ci);
    jpeg_mem_src(&ci, jpg.data(), jpg.size());
    CHECK(jpeg_read_header(&ci, TRUE) == JPEG_HEADER_OK);
    ci.out_color_space = JCS_RGB;
    jpeg_start_decompress(&ci);
    d.w = ci.output_width;
    d.h = ci.output_height;
    d.ch = 3;
    d.px.resize(static_cast<size_t>(d.w) * d.h * 3);
    while (ci.output_scanline < ci.output_height) {
        JSAMPROW rp = &d.px[static_cast<size_t>(ci.output_scanline) * d.w * 3];
        jpeg_read_scanlines(&ci, &rp, 1);
    }
    jpeg_finish_decompress(&ci);
    jpeg_destroy_decompress(&ci);
    return d;
}

Decoded decodePngOut(const std::vector<uint8_t>& data) {
    Decoded d;
    png_image img;
    std::memset(&img, 0, sizeof(img));
    img.version = PNG_IMAGE_VERSION;
    CHECK(png_image_begin_read_from_memory(&img, data.data(), data.size()));
    img.format = PNG_FORMAT_RGBA;
    d.w = img.width;
    d.h = img.height;
    d.ch = 4;
    d.px.resize(PNG_IMAGE_SIZE(img));
    CHECK(png_image_finish_read(&img, nullptr, d.px.data(), 0, nullptr));
    return d;
}

Decoded decodeOut(const Thumbnail& t) { return t.isPng ? decodePngOut(t.bytes) : decodeJpegOut(t.bytes); }

// ── checks ────────────────────────────────────────────────────────────────

bool near(const uint8_t* p, const Rgb& c, int tol) {
    return std::abs(p[0] - c.r) <= tol && std::abs(p[1] - c.g) <= tol && std::abs(p[2] - c.b) <= tol;
}

// Colour at the centre of displayed quadrant (qx, qy in {0,1}).
const uint8_t* quadrant(const Decoded& d, int qx, int qy) {
    const int x = d.w / 4 + qx * (d.w / 2), y = d.h / 4 + qy * (d.h / 2);
    return &d.px[(static_cast<size_t>(y) * d.w + x) * d.ch];
}

Thumbnail run(const std::vector<uint8_t>& data, int target = 180, int quality = 80, Status expect = Status::kOk) {
    MemorySource src(data.data(), data.size());
    Options opt;
    opt.targetSize = target;
    opt.quality = quality;
    Thumbnail t;
    const Status st = makeThumbnail(src, opt, t);
    if (st != expect) std::fprintf(stderr, "status %d, expected %d\n", static_cast<int>(st), static_cast<int>(expect));
    CHECK(st == expect);
    return t;
}

void checkFits(const Thumbnail& t, int srcW, int srcH, int target) {
    int ew, eh;
    fitWithin(srcW, srcH, target, ew, eh);
    CHECK(t.width == ew && t.height == eh);
    CHECK(std::max(t.width, t.height) <= std::max(target, 1));
    const Decoded d = decodeOut(t);
    CHECK(d.w == t.width && d.h == t.height);
}

void checkQuadrants(const Thumbnail& t, int tol = 28) {
    const Decoded d = decodeOut(t);
    CHECK(near(quadrant(d, 0, 0), kTL, tol));
    CHECK(near(quadrant(d, 1, 0), kTR, tol));
    CHECK(near(quadrant(d, 0, 1), kBL, tol));
    CHECK(near(quadrant(d, 1, 1), kBR, tol));
}

// Forward mapping of a stored pixel to its displayed position (EXIF spec), independent of the code under test.
void forward(int o, int w, int h, int x, int y, int& ox, int& oy) {
    switch (o) {
        case 1: ox = x; oy = y; break;
        case 2: ox = w - 1 - x; oy = y; break;
        case 3: ox = w - 1 - x; oy = h - 1 - y; break;
        case 4: ox = x; oy = h - 1 - y; break;
        case 5: ox = y; oy = x; break;
        case 6: ox = h - 1 - y; oy = x; break;
        case 7: ox = h - 1 - y; oy = w - 1 - x; break;
        default: ox = y; oy = w - 1 - x; break;
    }
}

// ── tests ─────────────────────────────────────────────────────────────────

int g_checks = 0;
#define SECTION(name) std::printf("  %s\n", name)

void testJpegSizes() {
    SECTION("jpeg: sizes, scaling and colours");
    for (const auto& s : std::vector<std::pair<int, int>>{{1, 1}, {7, 5}, {64, 48}, {180, 120}, {181, 90}, {640, 480}, {1000, 3000}, {2000, 1999}, {4000, 3000}}) {
        const auto rgba = scene(s.first, s.second);
        const auto jpg = makeJpeg(toRgb(rgba), s.first, s.second);
        for (int target : {64, 180, 360, 2048}) {
            const Thumbnail t = run(jpg, target);
            CHECK(!t.isPng && !t.hasAlpha);
            CHECK(t.sourceWidth == s.first && t.sourceHeight == s.second);
            checkFits(t, s.first, s.second, target);
            if (std::min(t.width, t.height) >= 8) checkQuadrants(t);
            ++g_checks;
        }
    }
}

void testJpegVariants() {
    SECTION("jpeg: progressive, grayscale, 4:2:2, quality");
    const int w = 1200, h = 800;
    const auto rgb = toRgb(scene(w, h));
    const Thumbnail prog = run(makeJpeg(rgb, w, h, 85, true));
    CHECK(prog.width == 180 && prog.height == 120);
    checkQuadrants(prog);
    const Thumbnail gray = run(makeJpeg(rgb, w, h, 90, false, true));
    const Decoded g = decodeOut(gray);
    CHECK(g.w == 180 && g.h == 120);
    CHECK(std::abs(g.px[0] - g.px[1]) < 6 && std::abs(g.px[1] - g.px[2]) < 6);  // really gray
    const Thumbnail h2 = run(makeJpeg(rgb, w, h, 90, false, false, 0, false, 1));
    checkQuadrants(h2);
    const Thumbnail lo = run(makeJpeg(rgb, w, h), 180, 20), hi = run(makeJpeg(rgb, w, h), 180, 95);
    CHECK(lo.bytes.size() < hi.bytes.size());
    g_checks += 5;
}

void testOrientation() {
    SECTION("jpeg: EXIF orientation 1..8, both byte orders");
    const int w = 800, h = 400;  // stored landscape: sideways orientations swap the shape
    const auto rgb = toRgb(scene(w, h));
    const struct { int qx, qy; const Rgb* c; } quads[4] = {{0, 0, &kTL}, {1, 0, &kTR}, {0, 1, &kBL}, {1, 1, &kBR}};
    for (int le = 0; le < 2; ++le) {
        for (int o = 1; o <= 8; ++o) {
            const Thumbnail t = run(makeJpeg(rgb, w, h, 90, false, false, o, le != 0), 200);
            const bool sideways = o >= 5;
            CHECK(t.sourceWidth == (sideways ? h : w) && t.sourceHeight == (sideways ? w : h));
            CHECK(t.width == (sideways ? 100 : 200) && t.height == (sideways ? 200 : 100));
            const Decoded d = decodeOut(t);
            for (const auto& q : quads) {
                int ox, oy;
                forward(o, w, h, q.qx ? 3 * w / 4 : w / 4, q.qy ? 3 * h / 4 : h / 4, ox, oy);
                const int dw = sideways ? h : w, dh = sideways ? w : h;
                CHECK(near(quadrant(d, ox >= dw / 2, oy >= dh / 2), *q.c, 28));
            }
            ++g_checks;
        }
    }
}

void testPng() {
    SECTION("png: kinds, alpha, interlacing, 16-bit");
    const int w = 900, h = 600;
    const auto rgba = scene(w, h);
    for (PngKind k : {PngKind::kRgb, PngKind::kRgba, PngKind::kPalette, PngKind::kRgb16}) {
        for (bool il : {false, true}) {
            const Thumbnail t = run(makePng(rgba, w, h, k, il));
            CHECK(!t.isPng);  // nothing transparent: answered as JPEG
            CHECK(t.sourceWidth == w && t.sourceHeight == h);
            checkFits(t, w, h, 180);
            checkQuadrants(t);
            ++g_checks;
        }
    }
    const Thumbnail gray = run(makePng(rgba, w, h, PngKind::kGray));
    const Decoded g = decodeOut(gray);
    CHECK(g.w == 180 && g.h == 120 && std::abs(g.px[0] - g.px[1]) < 4);

    // Half transparent top, opaque bottom: PNG out, alpha kept, colour not darkened by the transparent rows.
    std::vector<uint8_t> a = scene(w, h, 255, 0);
    for (int y = 0; y < h / 2; ++y)
        for (int x = 0; x < w; ++x) a[(static_cast<size_t>(y) * w + x) * 4 + 3] = 0;
    const Thumbnail ta = run(makePng(a, w, h, PngKind::kRgba, false));
    CHECK(ta.isPng && ta.hasAlpha);
    const Decoded da = decodePngOut(ta.bytes);
    CHECK(da.px[3] == 0);                                              // top row transparent
    CHECK(da.px[(static_cast<size_t>(da.h - 1) * da.w) * 4 + 3] == 255);  // bottom row opaque
    CHECK(near(&da.px[(static_cast<size_t>(da.h * 3 / 4) * da.w + da.w / 4) * 4], kBL, 6));
    // A soft edge (alpha ramp) must not bleed black: the middle of a 50% red area stays red.
    std::vector<uint8_t> half = scene(w, h, 128, 0);
    for (size_t i = 0; i < half.size(); i += 4) { half[i] = 200; half[i + 1] = 40; half[i + 2] = 40; }
    const Thumbnail th = run(makePng(half, w, h, PngKind::kRgba, true));
    CHECK(th.isPng);
    const Decoded dh = decodePngOut(th.bytes);
    CHECK(near(&dh.px[(static_cast<size_t>(dh.h / 2) * dh.w + dh.w / 2) * 4], Rgb{200, 40, 40}, 4));
    CHECK(std::abs(dh.px[(static_cast<size_t>(dh.h / 2) * dh.w + dh.w / 2) * 4 + 3] - 128) <= 2);
    g_checks += 6;
}

void testWebp() {
    SECTION("webp: lossy, lossless, alpha");
    const int w = 1000, h = 700;
    const auto rgba = scene(w, h, 255, 6);
    for (bool lossless : {false, true}) {
        const Thumbnail t = run(makeWebp(rgba, w, h, lossless, false));
        CHECK(!t.isPng && t.sourceWidth == w && t.sourceHeight == h);
        checkFits(t, w, h, 180);
        checkQuadrants(t);
        ++g_checks;
    }
    std::vector<uint8_t> a = scene(w, h, 255, 0);
    for (int y = 0; y < h / 2; ++y)
        for (int x = 0; x < w; ++x) a[(static_cast<size_t>(y) * w + x) * 4 + 3] = 0;
    const Thumbnail ta = run(makeWebp(a, w, h, true, true));
    CHECK(ta.isPng && ta.hasAlpha);
    const Thumbnail opaqueAlpha = run(makeWebp(scene(w, h), w, h, true, true));
    CHECK(!opaqueAlpha.isPng);  // has an alpha plane, but every pixel opaque
    const Thumbnail small = run(makeWebp(scene(100, 60), 100, 60, false, false));  // smaller than the target
    CHECK(small.width == 100 && small.height == 60);
    g_checks += 4;
}

void testFailures() {
    SECTION("failures and guards");
    const int w = 800, h = 600;
    const auto rgba = scene(w, h);
    const auto jpg = makeJpeg(toRgb(rgba), w, h);
    const auto png = makePng(rgba, w, h, PngKind::kRgb);
    const auto webp = makeWebp(rgba, w, h, false, false);

    std::vector<uint8_t> garbage(5000);
    for (size_t i = 0; i < garbage.size(); ++i) garbage[i] = static_cast<uint8_t>(i * 37 + 11);
    run(garbage, 180, 80, Status::kUnsupported);
    run({}, 180, 80, Status::kFailed);
    run(std::vector<uint8_t>{0xFF, 0xD8, 0xFF}, 180, 80, Status::kFailed);  // a JPEG header, nothing else

    // A GIF is not ours: the caller falls back to another decoder.
    const std::vector<uint8_t> gif = {'G', 'I', 'F', '8', '9', 'a', 1, 0, 1, 0, 0, 0, 0, ';'};
    run(gif, 180, 80, Status::kUnsupported);

    // Truncated JPEG: the rows that exist come out (like every viewer); cut inside the header it fails.
    const std::vector<uint8_t> cut(jpg.begin(), jpg.begin() + jpg.size() * 6 / 10);
    const Thumbnail partial = run(cut);
    CHECK(partial.width == 180 && partial.height == 135);
    run(std::vector<uint8_t>(jpg.begin(), jpg.begin() + 100), 180, 80, Status::kFailed);
    run(std::vector<uint8_t>(png.begin(), png.begin() + png.size() / 2), 180, 80, Status::kFailed);
    run(std::vector<uint8_t>(png.begin(), png.begin() + 20), 180, 80, Status::kFailed);
    run(std::vector<uint8_t>(webp.begin(), webp.begin() + webp.size() / 2), 180, 80, Status::kFailed);

    // Corrupt bytes in the middle of the entropy-coded data: libjpeg conceals, we still answer.
    std::vector<uint8_t> bad = jpg;
    for (size_t i = bad.size() / 2; i < bad.size() / 2 + 200; ++i) bad[i] ^= 0x5A;
    const MemorySource dummy(bad.data(), bad.size());
    (void)dummy;
    {
        MemorySource src(bad.data(), bad.size());
        Options opt;
        Thumbnail t;
        const Status st = makeThumbnail(src, opt, t);
        CHECK(st == Status::kOk || st == Status::kFailed);
    }

    // Guards.
    {
        MemorySource src(jpg.data(), jpg.size());
        Options opt;
        opt.maxSourceBytes = jpg.size() - 1;
        Thumbnail t;
        CHECK(makeThumbnail(src, opt, t) == Status::kTooLarge);
    }
    {
        const auto prog = makeJpeg(toRgb(rgba), w, h, 85, true);
        MemorySource src(prog.data(), prog.size());
        Options opt;
        opt.maxDecodeBytes = 1000;  // far below the coefficient memory of a progressive JPEG
        Thumbnail t;
        CHECK(makeThumbnail(src, opt, t) == Status::kTooLarge);
        MemorySource src2(jpg.data(), jpg.size());  // baseline JPEG is exempt: it streams
        CHECK(makeThumbnail(src2, opt, t) == Status::kOk);
        const auto il = makePng(rgba, w, h, PngKind::kRgb, true);
        MemorySource src3(il.data(), il.size());
        CHECK(makeThumbnail(src3, opt, t) == Status::kTooLarge);  // interlaced PNG needs the whole image
        const auto flat = makePng(rgba, w, h, PngKind::kRgb, false);
        MemorySource src4(flat.data(), flat.size());
        CHECK(makeThumbnail(src4, opt, t) == Status::kOk);        // plain PNG streams
    }

    // A source that fails to read.
    struct Failing : ByteSource {
        const std::vector<uint8_t>& d;
        int64_t failAfter;
        explicit Failing(const std::vector<uint8_t>& data, int64_t after) : d(data), failAfter(after) {}
        int64_t size() override { return static_cast<int64_t>(d.size()); }
        int64_t readAt(int64_t off, uint8_t* dst, size_t len) override {
            if (off >= failAfter) return -1;
            if (static_cast<size_t>(off) >= d.size()) return 0;
            const size_t n = std::min({len, d.size() - static_cast<size_t>(off), static_cast<size_t>(failAfter - off)});
            std::memcpy(dst, d.data() + off, n);
            return static_cast<int64_t>(n);
        }
    };
    for (const auto* data : {&jpg, &png, &webp}) {
        Failing f(*data, static_cast<int64_t>(data->size() / 3 + 1));
        Options opt;
        Thumbnail t;
        const Status st = makeThumbnail(f, opt, t);
        CHECK(st == Status::kIoError);
        Failing first(*data, 0);
        CHECK(makeThumbnail(first, opt, t) == Status::kIoError);
    }
    g_checks += 20;
}

void testThreads() {
    SECTION("many threads at once, shared memory budget");
    const int w = 1500, h = 1000;
    const auto rgba = scene(w, h);
    const std::vector<std::vector<uint8_t>> files = {
        makeJpeg(toRgb(rgba), w, h), makeJpeg(toRgb(rgba), w, h, 85, true),
        makePng(rgba, w, h, PngKind::kRgb, true), makePng(rgba, w, h, PngKind::kRgba, false),
        makeWebp(rgba, w, h, false, false), makeWebp(rgba, w, h, true, true)};
    setMemoryBudget(24ull << 20);  // small, so heavy decodes really have to take turns
    std::atomic<int> bad{0};
    std::vector<std::thread> pool;
    for (int t = 0; t < 8; ++t) {
        pool.emplace_back([&, t] {
            for (int i = 0; i < 24; ++i) {
                const auto& f = files[(t + i) % files.size()];
                MemorySource src(f.data(), f.size());
                Options opt;
                Thumbnail th;
                if (makeThumbnail(src, opt, th) != Status::kOk || th.width != 180 || th.height != 120) ++bad;
            }
        });
    }
    for (auto& t : pool) t.join();
    CHECK(bad == 0);
    setMemoryBudget(1536ull << 20);
    g_checks += 1;
}

void testFit() {
    SECTION("fitWithin");
    int w, h;
    fitWithin(4000, 3000, 180, w, h); CHECK(w == 180 && h == 135);
    fitWithin(3000, 4000, 180, w, h); CHECK(w == 135 && h == 180);
    fitWithin(100, 50, 180, w, h);    CHECK(w == 100 && h == 50);   // never enlarged
    fitWithin(10000, 1, 180, w, h);   CHECK(w == 180 && h == 1);    // never zero
    fitWithin(5, 5, 0, w, h);         CHECK(w == 1 && h == 1);
    g_checks += 5;
}

// ── benchmark ─────────────────────────────────────────────────────────────

double ms(std::chrono::steady_clock::time_point a) {
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - a).count();
}

void bench() {
    std::printf("benchmark (single thread, this machine, -O2)\n");
    struct Case { const char* name; int w, h; };
    for (const Case c : {Case{"6000x4000 (24 MP)", 6000, 4000}, Case{"4000x3000 (12 MP)", 4000, 3000}, Case{"1920x1080", 1920, 1080}}) {
        const auto rgba = scene(c.w, c.h, 255, 14);
        const auto rgb = toRgb(rgba);
        struct F { const char* n; std::vector<uint8_t> d; };
        std::vector<F> files;
        files.push_back({"jpeg baseline q90", makeJpeg(rgb, c.w, c.h, 90)});
        files.push_back({"jpeg progressive", makeJpeg(rgb, c.w, c.h, 85, true)});
        files.push_back({"png", makePng(rgba, c.w, c.h, PngKind::kRgb)});
        files.push_back({"webp lossy", makeWebp(rgba, c.w, c.h, false, false)});
        std::printf("%s\n", c.name);
        for (const F& f : files) {
            MemorySource src(f.d.data(), f.d.size());
            Options opt;
            Thumbnail t;
            makeThumbnail(src, opt, t);  // warm up
            const int reps = c.w >= 4000 ? 5 : 15;
            const auto t0 = std::chrono::steady_clock::now();
            for (int i = 0; i < reps; ++i) makeThumbnail(src, opt, t);
            std::printf("  %-18s file %6.1f MB  ->  %6.1f ms per 180px thumbnail (%zu bytes out)\n", f.n,
                        f.d.size() / 1e6, ms(t0) / reps, t.bytes.size());
        }
    }
}

}  // namespace

int main(int argc, char** argv) {
    if (argc > 1 && std::string(argv[1]) == "bench") {
        bench();
        return 0;
    }
    std::printf("thumb_test\n");
    testFit();
    testJpegSizes();
    testJpegVariants();
    testOrientation();
    testPng();
    testWebp();
    testFailures();
    testThreads();
    std::printf("%d groups of checks passed\n", g_checks);
    return 0;
}
