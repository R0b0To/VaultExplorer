// See thumb.h. The structure of this file:
//
//   1. small helpers (memory budget, buffered reader, format sniffing, sizes)
//   2. BoxResampler: exact-area downscale that takes the picture one row at a time
//   3. EXIF orientation (read + apply)
//   4. one decoder per format, each producing a small raster:  decodeJpeg / decodePng / decodeWebp
//   5. the two encoders and makeThumbnail()
//
// libjpeg and libpng report errors with longjmp. Every function that setjmp()s keeps ALL its state in one job
// object created before the setjmp and touches nothing else afterwards except to return, which is the pattern the
// libraries document for C++ callers.
#include "thumb.h"

#include <algorithm>
#include <cmath>
#include <condition_variable>
#include <csetjmp>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>

#include <jerror.h>
#include <jpeglib.h>
#include <png.h>
#include <webp/decode.h>

namespace veimg {

// ───────────────────────── 1. helpers ─────────────────────────

int64_t MemorySource::readAt(int64_t offset, uint8_t* dst, size_t len) {
    if (offset < 0) return -1;
    if (static_cast<uint64_t>(offset) >= len_) return 0;
    const size_t n = std::min(len, len_ - static_cast<size_t>(offset));
    std::memcpy(dst, data_ + offset, n);
    return static_cast<int64_t>(n);
}

Format sniffFormat(const uint8_t* h, size_t n) {
    if (n >= 3 && h[0] == 0xFF && h[1] == 0xD8 && h[2] == 0xFF) return Format::kJpeg;
    static const uint8_t kPng[8] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
    if (n >= 8 && std::memcmp(h, kPng, 8) == 0) return Format::kPng;
    if (n >= 12 && std::memcmp(h, "RIFF", 4) == 0 && std::memcmp(h + 8, "WEBP", 4) == 0) return Format::kWebp;
    return Format::kUnknown;
}

void fitWithin(int w, int h, int target, int& ow, int& oh) {
    if (target < 1) target = 1;
    const int longest = std::max(w, h);
    if (longest <= target) {
        ow = w;
        oh = h;
        return;
    }
    const double s = static_cast<double>(target) / longest;
    ow = std::max(1, static_cast<int>(std::lround(w * s)));
    oh = std::max(1, static_cast<int>(std::lround(h * s)));
    if (w >= h) ow = target; else oh = target;  // the longest side is exactly the target
}

namespace {

// Memory the decoders hold at once. Typical thumbnails need a few MiB and pass straight through; a big
// progressive JPEG or interlaced PNG waits its turn instead of several of them exhausting the machine together.
class MemoryBudget {
public:
    static MemoryBudget& get() {
        static MemoryBudget b;
        return b;
    }
    void setLimit(uint64_t bytes) {
        std::lock_guard<std::mutex> lock(mu_);
        limit_ = bytes;
        cv_.notify_all();
    }
    bool acquire(uint64_t bytes) {
        std::unique_lock<std::mutex> lock(mu_);
        if (bytes > limit_) return false;
        cv_.wait(lock, [&] { return used_ + bytes <= limit_; });
        used_ += bytes;
        return true;
    }
    void release(uint64_t bytes) {
        std::lock_guard<std::mutex> lock(mu_);
        used_ -= bytes;
        cv_.notify_all();
    }

private:
    std::mutex mu_;
    std::condition_variable cv_;
    uint64_t used_ = 0;
    uint64_t limit_ = 1536ull << 20;
};

// Held by a decode job (a member, so it is released by the job's destructor even when a library longjmps out).
class Permit {
public:
    Permit() = default;
    ~Permit() {
        if (held_) MemoryBudget::get().release(bytes_);
    }
    Permit(const Permit&) = delete;
    Permit& operator=(const Permit&) = delete;

    // Waits until `bytes` fit in the budget. False (nothing held) when they never could.
    bool acquire(uint64_t bytes) {
        if (held_) return true;
        held_ = MemoryBudget::get().acquire(bytes);
        bytes_ = bytes;
        return held_;
    }

private:
    uint64_t bytes_ = 0;
    bool held_ = false;
};

// Sequential read-ahead over a ByteSource, for decoders that ask for a few bytes at a time (libpng).
class Reader {
public:
    explicit Reader(ByteSource& s, size_t cap = 256 * 1024) : src_(s), buf_(cap) {}

    // Copies up to n bytes; fewer only at the end of the data or after an I/O error.
    size_t read(uint8_t* dst, size_t n) {
        size_t done = 0;
        while (done < n) {
            if (pos_ >= bufStart_ && pos_ < bufStart_ + static_cast<int64_t>(bufLen_)) {
                const size_t off = static_cast<size_t>(pos_ - bufStart_);
                const size_t take = std::min(n - done, bufLen_ - off);
                std::memcpy(dst + done, buf_.data() + off, take);
                done += take;
                pos_ += static_cast<int64_t>(take);
                continue;
            }
            if (n - done >= buf_.size()) {  // a big request: straight into the caller's memory
                const int64_t got = src_.readAt(pos_, dst + done, n - done);
                if (got < 0) { ioError_ = true; break; }
                if (got == 0) break;
                done += static_cast<size_t>(got);
                pos_ += got;
                continue;
            }
            const int64_t got = src_.readAt(pos_, buf_.data(), buf_.size());
            if (got < 0) { ioError_ = true; break; }
            if (got == 0) break;
            bufStart_ = pos_;
            bufLen_ = static_cast<size_t>(got);
        }
        return done;
    }
    bool ioError() const { return ioError_; }

private:
    ByteSource& src_;
    std::vector<uint8_t> buf_;
    int64_t bufStart_ = 0;
    size_t bufLen_ = 0;
    int64_t pos_ = 0;
    bool ioError_ = false;
};

// The small picture a decoder hands over: 3 (RGB) or 4 (RGBA, straight alpha) channels, 8 bits each.
struct Raster {
    std::vector<uint8_t> px;
    int w = 0, h = 0, ch = 3;
    int storedW = 0, storedH = 0;  // size of the picture as stored (before EXIF orientation)
    int orientation = 1;           // EXIF, 1..8
    bool hasAlpha = false;
};

inline int ceilDiv(int a, int b) { return (a + b - 1) / b; }

// ───────────────────────── 2. BoxResampler ─────────────────────────
//
// Exact area averaging: every output pixel is the mean of the source rectangle it covers, partial pixels at the
// edges weighted by their overlap (the "box" filter, which is what a good thumbnailer wants when shrinking).
// Rows arrive top to bottom and are folded into two running output rows, so nothing close to the full picture is
// ever held. Alpha is averaged premultiplied so a transparent edge does not bleed its (arbitrary) colour.
//
// Integer geometry: along one axis, source pixel i covers [i*dst, (i+1)*dst) and destination pixel j covers
// [j*src, (j+1)*src) in the same units, so overlaps are exact integers and the weights of one destination
// pixel add up to exactly 1. Only shrinking (or keeping) the size is supported.
class BoxResampler {
public:
    BoxResampler(int srcW, int srcH, int dstW, int dstH, int ch)
        : srcW_(srcW), srcH_(srcH), dstW_(dstW), dstH_(dstH), ch_(ch) {
        out_.resize(static_cast<size_t>(dstW) * dstH * ch);
        identity_ = (srcW == dstW && srcH == dstH);
        if (identity_) return;
        spans_.resize(dstW);
        weights_.reserve(static_cast<size_t>(srcW) + dstW);
        for (int x = 0; x < dstW; ++x) {
            const int64_t lo = static_cast<int64_t>(x) * srcW, hi = lo + srcW;
            const int first = static_cast<int>(lo / dstW);
            const int last = static_cast<int>((hi - 1) / dstW);
            spans_[x] = {first, last - first + 1, static_cast<int>(weights_.size())};
            for (int i = first; i <= last; ++i) {
                const int64_t a = std::max<int64_t>(static_cast<int64_t>(i) * dstW, lo);
                const int64_t b = std::min<int64_t>(static_cast<int64_t>(i + 1) * dstW, hi);
                weights_.push_back(static_cast<float>(b - a) / static_cast<float>(srcW));
            }
        }
        hrow_.resize(static_cast<size_t>(dstW) * ch);
        acc_[0].assign(static_cast<size_t>(dstW) * ch, 0.f);
        acc_[1].assign(static_cast<size_t>(dstW) * ch, 0.f);
    }

    void addRow(const uint8_t* row) {
        if (identity_) {
            if (nextRow_ < dstH_) std::memcpy(out_.data() + static_cast<size_t>(nextRow_) * dstW_ * ch_, row, static_cast<size_t>(dstW_) * ch_);
            if (ch_ == 4) {
                for (int x = 0; x < dstW_; ++x) minAlpha_ = std::min<int>(minAlpha_, row[x * 4 + 3]);
            }
            ++nextRow_;
            return;
        }
        if (ch_ == 4) hpass<4>(row); else hpass<3>(row);

        const int64_t y = nextRow_;
        const int64_t top = y * dstH_, bottom = top + dstH_;  // this source row, in vertical units
        const int jFirst = static_cast<int>(top / srcH_);
        const int jLast = static_cast<int>((bottom - 1) / srcH_);
        for (int j = jFirst; j <= jLast; ++j) {
            const int64_t a = std::max<int64_t>(top, static_cast<int64_t>(j) * srcH_);
            const int64_t b = std::min<int64_t>(bottom, static_cast<int64_t>(j + 1) * srcH_);
            const float w = static_cast<float>(b - a) / static_cast<float>(srcH_);
            std::vector<float>& acc = acc_[j - jBase_ == 0 ? 0 : 1];
            const size_t n = acc.size();
            for (size_t k = 0; k < n; ++k) acc[k] += w * hrow_[k];
        }
        if (bottom >= static_cast<int64_t>(jBase_ + 1) * srcH_) {  // destination row jBase_ is complete
            emit(acc_[0], jBase_);
            acc_[0].swap(acc_[1]);
            std::fill(acc_[1].begin(), acc_[1].end(), 0.f);
            ++jBase_;
        }
        ++nextRow_;
    }

    // Valid once all srcH rows have been added.
    std::vector<uint8_t>& out() { return out_; }
    int minAlpha() const { return minAlpha_; }

private:
    struct Span {
        int first, count, wOff;
    };

    template <int CH>
    void hpass(const uint8_t* row) {
        float* o = hrow_.data();
        for (int x = 0; x < dstW_; ++x, o += CH) {
            const Span& sp = spans_[x];
            const float* wt = weights_.data() + sp.wOff;
            const uint8_t* p = row + static_cast<size_t>(sp.first) * CH;
            float s0 = 0.f, s1 = 0.f, s2 = 0.f, s3 = 0.f;
            for (int k = 0; k < sp.count; ++k, p += CH) {
                const float w = wt[k];
                if constexpr (CH == 4) {
                    if (p[3] < minAlpha_) minAlpha_ = p[3];
                    const float wa = w * static_cast<float>(p[3]) * (1.f / 255.f);
                    s0 += p[0] * wa;
                    s1 += p[1] * wa;
                    s2 += p[2] * wa;
                    s3 += w * static_cast<float>(p[3]);
                } else {
                    s0 += p[0] * w;
                    s1 += p[1] * w;
                    s2 += p[2] * w;
                }
            }
            o[0] = s0;
            o[1] = s1;
            o[2] = s2;
            if constexpr (CH == 4) o[3] = s3;
        }
    }

    static uint8_t clamp8(float v) { return v <= 0.f ? 0 : (v >= 255.f ? 255 : static_cast<uint8_t>(v + 0.5f)); }

    void emit(const std::vector<float>& acc, int dstRow) {
        if (dstRow >= dstH_) return;
        uint8_t* o = out_.data() + static_cast<size_t>(dstRow) * dstW_ * ch_;
        const float* a = acc.data();
        if (ch_ == 3) {
            for (int i = 0; i < dstW_ * 3; ++i) o[i] = clamp8(a[i]);
            return;
        }
        for (int x = 0; x < dstW_; ++x, a += 4, o += 4) {
            const float alpha = a[3];
            if (alpha < 0.001f) {
                o[0] = o[1] = o[2] = o[3] = 0;
                continue;
            }
            const float k = 255.f / alpha;  // premultiplied -> straight
            o[0] = clamp8(a[0] * k);
            o[1] = clamp8(a[1] * k);
            o[2] = clamp8(a[2] * k);
            o[3] = clamp8(alpha);
        }
    }

    int srcW_, srcH_, dstW_, dstH_, ch_;
    bool identity_ = false;
    std::vector<Span> spans_;
    std::vector<float> weights_;
    std::vector<float> hrow_;
    std::vector<float> acc_[2];
    std::vector<uint8_t> out_;
    int nextRow_ = 0;
    int jBase_ = 0;
    int minAlpha_ = 255;
};

// ───────────────────────── 3. EXIF orientation ─────────────────────────

// `p` points at an APP1 payload. Returns the Orientation tag (1..8), or 1 when there is none.
int exifOrientation(const uint8_t* p, size_t n) {
    if (n < 14 || std::memcmp(p, "Exif\0\0", 6) != 0) return 1;
    const uint8_t* t = p + 6;
    const size_t tn = n - 6;
    const bool le = (t[0] == 'I' && t[1] == 'I');
    if (!le && !(t[0] == 'M' && t[1] == 'M')) return 1;
    auto u16 = [&](size_t o) -> uint32_t {
        return le ? (t[o] | (t[o + 1] << 8)) : ((t[o] << 8) | t[o + 1]);
    };
    auto u32 = [&](size_t o) -> uint32_t {
        return le ? (static_cast<uint32_t>(t[o]) | (static_cast<uint32_t>(t[o + 1]) << 8) |
                     (static_cast<uint32_t>(t[o + 2]) << 16) | (static_cast<uint32_t>(t[o + 3]) << 24))
                  : ((static_cast<uint32_t>(t[o]) << 24) | (static_cast<uint32_t>(t[o + 1]) << 16) |
                     (static_cast<uint32_t>(t[o + 2]) << 8) | static_cast<uint32_t>(t[o + 3]));
    };
    if (tn < 8 || u16(2) != 42) return 1;
    const size_t ifd = u32(4);
    if (ifd > tn || tn - ifd < 2) return 1;
    const size_t count = std::min<size_t>(u16(ifd), 512);
    for (size_t i = 0; i < count; ++i) {
        const size_t e = ifd + 2 + i * 12;
        if (e + 12 > tn) break;
        if (u16(e) == 0x0112) {
            if (u16(e + 2) != 3 || u32(e + 4) != 1) return 1;  // must be one SHORT
            const uint32_t v = u16(e + 8);
            return (v >= 1 && v <= 8) ? static_cast<int>(v) : 1;
        }
    }
    return 1;
}

// Rotates / mirrors `r` so that it shows the way the picture is meant to be seen. Cheap: it runs on the small
// raster, after scaling.
void applyOrientation(Raster& r) {
    if (r.orientation <= 1 || r.orientation > 8) return;
    const int w = r.w, h = r.h, ch = r.ch;
    const bool swap = r.orientation >= 5;
    const int nw = swap ? h : w, nh = swap ? w : h;
    std::vector<uint8_t> out(r.px.size());
    for (int y = 0; y < nh; ++y) {
        for (int x = 0; x < nw; ++x) {
            int sx = x, sy = y;  // where this displayed pixel comes from in the stored picture
            switch (r.orientation) {
                case 2: sx = w - 1 - x; sy = y; break;
                case 3: sx = w - 1 - x; sy = h - 1 - y; break;
                case 4: sx = x; sy = h - 1 - y; break;
                case 5: sx = y; sy = x; break;
                case 6: sx = y; sy = h - 1 - x; break;
                case 7: sx = w - 1 - y; sy = h - 1 - x; break;
                case 8: sx = w - 1 - y; sy = x; break;
                default: break;
            }
            std::memcpy(&out[(static_cast<size_t>(y) * nw + x) * ch], &r.px[(static_cast<size_t>(sy) * w + sx) * ch], ch);
        }
    }
    r.px.swap(out);
    r.w = nw;
    r.h = nh;
}

// ───────────────────────── 4a. JPEG ─────────────────────────

struct JpegSrc {
    jpeg_source_mgr pub{};
    ByteSource* src = nullptr;
    int64_t pos = 0;  // file offset of the next byte to fetch
    std::vector<uint8_t> buf;
    bool ioError = false;
    bool sawEof = false;
};

struct JpegErr {
    jpeg_error_mgr pub;
    std::jmp_buf jb;
};

void jpegErrorExit(j_common_ptr c) { std::longjmp(reinterpret_cast<JpegErr*>(c->err)->jb, 1); }
void jpegEmit(j_common_ptr, int) {}
void jpegOutput(j_common_ptr) {}

void jpegSrcInit(j_decompress_ptr) {}
boolean jpegSrcFill(j_decompress_ptr cinfo) {
    auto* s = reinterpret_cast<JpegSrc*>(cinfo->src);
    const int64_t n = s->src->readAt(s->pos, s->buf.data(), s->buf.size());
    if (n < 0) {
        s->ioError = true;
        ERREXIT(cinfo, JERR_FILE_READ);
    }
    if (n == 0) {
        // A truncated file: end it with a synthetic EOI (once) so the rows that were read still come out. A
        // header cut short still fails, because libjpeg then reports the premature end.
        if (s->sawEof) ERREXIT(cinfo, JERR_INPUT_EOF);
        s->sawEof = true;
        s->buf[0] = 0xFF;
        s->buf[1] = JPEG_EOI;
        s->pub.next_input_byte = s->buf.data();
        s->pub.bytes_in_buffer = 2;
        return TRUE;
    }
    s->pos += n;
    s->pub.next_input_byte = s->buf.data();
    s->pub.bytes_in_buffer = static_cast<size_t>(n);
    return TRUE;
}
void jpegSrcSkip(j_decompress_ptr cinfo, long num) {
    auto* s = reinterpret_cast<JpegSrc*>(cinfo->src);
    if (num <= 0) return;
    if (static_cast<size_t>(num) <= s->pub.bytes_in_buffer) {
        s->pub.next_input_byte += num;
        s->pub.bytes_in_buffer -= static_cast<size_t>(num);
    } else {
        s->pos += num - static_cast<long>(s->pub.bytes_in_buffer);  // the next fill starts past the skipped bytes
        s->pub.bytes_in_buffer = 0;
    }
}
void jpegSrcTerm(j_decompress_ptr) {}

struct JpegJob {
    explicit JpegJob(ByteSource& source) {
        std::memset(&cinfo, 0, sizeof(cinfo));
        std::memset(&err, 0, sizeof(err));
        sm.src = &source;
        sm.buf.resize(256 * 1024);
        sm.pub.init_source = jpegSrcInit;
        sm.pub.fill_input_buffer = jpegSrcFill;
        sm.pub.skip_input_data = jpegSrcSkip;
        sm.pub.resync_to_restart = jpeg_resync_to_restart;
        sm.pub.term_source = jpegSrcTerm;
        cinfo.err = jpeg_std_error(&err.pub);
        err.pub.error_exit = jpegErrorExit;
        err.pub.emit_message = jpegEmit;
        err.pub.output_message = jpegOutput;
        jpeg_create_decompress(&cinfo);
        cinfo.src = &sm.pub;
    }
    ~JpegJob() { jpeg_destroy_decompress(&cinfo); }
    JpegJob(const JpegJob&) = delete;
    JpegJob& operator=(const JpegJob&) = delete;

    jpeg_decompress_struct cinfo;
    JpegErr err;
    JpegSrc sm;
    std::vector<uint8_t> row;
    Permit permit;                      // members, not locals: a longjmp skips destructors of locals
    std::unique_ptr<BoxResampler> rs;
};

Status decodeJpeg(ByteSource& src, const Options& opt, Raster& r) {
    JpegJob job(src);
    jpeg_decompress_struct& ci = job.cinfo;
    if (setjmp(job.err.jb)) return job.sm.ioError ? Status::kIoError : Status::kFailed;

    jpeg_save_markers(&ci, JPEG_APP0 + 1, 0xFFFF);
    if (jpeg_read_header(&ci, TRUE) != JPEG_HEADER_OK) return Status::kFailed;
    const int w = static_cast<int>(ci.image_width), h = static_cast<int>(ci.image_height);
    if (w <= 0 || h <= 0) return Status::kFailed;
    if (ci.jpeg_color_space == JCS_CMYK || ci.jpeg_color_space == JCS_YCCK) return Status::kUnsupported;
    if (ci.num_components != 1 && ci.num_components != 3) return Status::kUnsupported;

    int orientation = 1;
    for (jpeg_saved_marker_ptr m = ci.marker_list; m; m = m->next) {
        if (m->marker == JPEG_APP0 + 1) {
            orientation = exifOrientation(m->data, m->data_length);
            if (orientation != 1) break;
        }
    }

    // Take as much of the shrinking as possible out of the DCT (1/2, 1/4, 1/8), keeping the result at least as
    // large as the thumbnail so the box filter after it still has real pixels to average.
    const int longest = std::max(w, h);
    int denom = 1;
    while (denom < 8 && ceilDiv(longest, denom * 2) >= opt.targetSize) denom *= 2;
    ci.scale_num = 1;
    ci.scale_denom = static_cast<unsigned>(denom);
    ci.out_color_space = JCS_RGB;
    ci.dct_method = JDCT_ISLOW;
    ci.do_fancy_upsampling = (denom == 1 && opt.targetSize >= 512) ? TRUE : FALSE;  // cheaper chroma when small
    ci.do_block_smoothing = FALSE;
    jpeg_calc_output_dimensions(&ci);
    const int outW = static_cast<int>(ci.output_width), outH = static_cast<int>(ci.output_height);

    // A progressive or multi-scan JPEG needs every coefficient in memory (128 bytes per 8x8 block and component).
    // A baseline one is decoded a row at a time and needs next to nothing.
    uint64_t need = 4ull << 20;
    if (jpeg_has_multiple_scans(&ci)) {
        uint64_t coef = 0;
        for (int i = 0; i < ci.num_components; ++i) {
            const jpeg_component_info& c = ci.comp_info[i];
            const uint64_t bw = (static_cast<uint64_t>(c.width_in_blocks) + c.h_samp_factor - 1) / c.h_samp_factor * c.h_samp_factor;
            const uint64_t bh = (static_cast<uint64_t>(c.height_in_blocks) + c.v_samp_factor - 1) / c.v_samp_factor * c.v_samp_factor;
            coef += bw * bh * sizeof(JBLOCK);
        }
        if (coef > opt.maxDecodeBytes) return Status::kTooLarge;
        need += coef;
    }
    if (!job.permit.acquire(need)) return Status::kTooLarge;

    int dw, dh;
    fitWithin(w, h, opt.targetSize, dw, dh);
    dw = std::min(dw, outW);
    dh = std::min(dh, outH);

    jpeg_start_decompress(&ci);
    job.rs = std::make_unique<BoxResampler>(outW, outH, dw, dh, 3);
    job.row.resize(static_cast<size_t>(outW) * 3);
    while (ci.output_scanline < ci.output_height) {
        JSAMPROW rp = job.row.data();
        if (jpeg_read_scanlines(&ci, &rp, 1) != 1) return Status::kFailed;
        job.rs->addRow(job.row.data());
    }
    r.px = std::move(job.rs->out());
    r.w = dw;
    r.h = dh;
    r.ch = 3;
    r.storedW = w;
    r.storedH = h;
    r.orientation = orientation;
    r.hasAlpha = false;
    return Status::kOk;
}

// ───────────────────────── 4b. PNG ─────────────────────────

struct PngJob {
    explicit PngJob(ByteSource& s) : reader(s) {}
    ~PngJob() {
        if (png) png_destroy_read_struct(&png, &info, nullptr);
    }
    PngJob(const PngJob&) = delete;
    PngJob& operator=(const PngJob&) = delete;

    png_structp png = nullptr;
    png_infop info = nullptr;
    Reader reader;
    std::vector<uint8_t> row;
    std::vector<uint8_t> image;      // interlaced pictures only
    std::vector<png_bytep> rowPtrs;  // interlaced pictures only
    Permit permit;                   // members, not locals: a longjmp skips destructors of locals
    std::unique_ptr<BoxResampler> rs;
};

void pngRead(png_structp p, png_bytep dst, size_t n) {
    auto* job = static_cast<PngJob*>(png_get_io_ptr(p));
    if (job->reader.read(dst, n) != n) png_error(p, job->reader.ioError() ? "read error" : "truncated");
}
void pngError(png_structp p, png_const_charp) { png_longjmp(p, 1); }
void pngWarn(png_structp, png_const_charp) {}

Status decodePng(ByteSource& src, const Options& opt, Raster& r) {
    PngJob job(src);
    job.png = png_create_read_struct(PNG_LIBPNG_VER_STRING, nullptr, pngError, pngWarn);
    if (!job.png) return Status::kNoMemory;
    job.info = png_create_info_struct(job.png);
    if (!job.info) return Status::kNoMemory;
    if (setjmp(png_jmpbuf(job.png))) return job.reader.ioError() ? Status::kIoError : Status::kFailed;

    png_set_read_fn(job.png, &job, pngRead);
    png_read_info(job.png, job.info);
    png_uint_32 pw = 0, ph = 0;
    int bitDepth = 0, colorType = 0, interlace = 0;
    png_get_IHDR(job.png, job.info, &pw, &ph, &bitDepth, &colorType, &interlace, nullptr, nullptr);
    if (pw == 0 || ph == 0 || pw > 0x3FFFFFFFu || ph > 0x3FFFFFFFu) return Status::kFailed;
    const int w = static_cast<int>(pw), h = static_cast<int>(ph);

    const bool alpha = (colorType & PNG_COLOR_MASK_ALPHA) != 0 || png_get_valid(job.png, job.info, PNG_INFO_tRNS) != 0;
    const int ch = alpha ? 4 : 3;
    png_set_expand(job.png);  // palette -> RGB, low bit-depth gray -> 8 bit, tRNS -> alpha
    if (bitDepth == 16) png_set_scale_16(job.png);
    if (colorType == PNG_COLOR_TYPE_GRAY || colorType == PNG_COLOR_TYPE_GRAY_ALPHA) png_set_gray_to_rgb(job.png);
    const bool interlaced = interlace != PNG_INTERLACE_NONE;
    if (interlaced) png_set_interlace_handling(job.png);
    png_read_update_info(job.png, job.info);
    const size_t rowBytes = png_get_rowbytes(job.png, job.info);
    if (rowBytes != static_cast<size_t>(w) * ch) return Status::kFailed;

    // Interlaced pictures arrive in passes that each touch every row, so they need the whole image in memory.
    const uint64_t full = static_cast<uint64_t>(rowBytes) * static_cast<uint64_t>(h);
    if (interlaced && full > opt.maxDecodeBytes) return Status::kTooLarge;
    if (!job.permit.acquire((interlaced ? full : 0) + (4ull << 20))) return Status::kTooLarge;

    int dw, dh;
    fitWithin(w, h, opt.targetSize, dw, dh);
    job.rs = std::make_unique<BoxResampler>(w, h, dw, dh, ch);
    if (interlaced) {
        job.image.resize(static_cast<size_t>(full));
        job.rowPtrs.resize(static_cast<size_t>(h));
        for (int y = 0; y < h; ++y) job.rowPtrs[y] = job.image.data() + static_cast<size_t>(y) * rowBytes;
        png_read_image(job.png, job.rowPtrs.data());
        for (int y = 0; y < h; ++y) job.rs->addRow(job.rowPtrs[y]);
    } else {
        job.row.resize(rowBytes);
        for (int y = 0; y < h; ++y) {
            png_read_row(job.png, job.row.data(), nullptr);
            job.rs->addRow(job.row.data());
        }
    }
    r.px = std::move(job.rs->out());
    r.w = dw;
    r.h = dh;
    r.ch = ch;
    r.storedW = w;
    r.storedH = h;
    r.orientation = 1;
    r.hasAlpha = (ch == 4) && job.rs->minAlpha() < 255;
    return Status::kOk;
}

// ───────────────────────── 4c. WebP ─────────────────────────

Status decodeWebp(ByteSource& src, const Options& opt, Raster& r) {
    // libwebp wants the whole file. WebPs are small; the size guard above already bounded it.
    std::vector<uint8_t> data;
    const int64_t known = src.size();
    if (known > 0) data.reserve(static_cast<size_t>(known));
    constexpr size_t kStep = 1 << 20;
    for (;;) {
        const size_t at = data.size();
        if (at > opt.maxSourceBytes) return Status::kTooLarge;
        data.resize(at + kStep);
        const int64_t got = src.readAt(static_cast<int64_t>(at), data.data() + at, kStep);
        if (got < 0) return Status::kIoError;
        data.resize(at + static_cast<size_t>(got));
        if (got == 0) break;
    }

    WebPBitstreamFeatures f;
    if (WebPGetFeatures(data.data(), data.size(), &f) != VP8_STATUS_OK) return Status::kFailed;
    if (f.has_animation) return Status::kUnsupported;  // the caller's fallback shows the first frame
    const int w = f.width, h = f.height;
    if (w <= 0 || h <= 0) return Status::kFailed;

    // A lossless WebP decodes into a full-size ARGB buffer internally; a lossy one with alpha keeps a full-size
    // alpha plane. Charge the worst case.
    const uint64_t pixelBytes = static_cast<uint64_t>(w) * h * 4;
    if (pixelBytes > opt.maxDecodeBytes) return Status::kTooLarge;
    Permit permit;  // no longjmp in this decoder, so a local is fine
    if (!permit.acquire(data.size() + pixelBytes + (4ull << 20))) return Status::kTooLarge;

    int dw, dh;
    fitWithin(w, h, opt.targetSize, dw, dh);
    const int ch = f.has_alpha ? 4 : 3;

    WebPDecoderConfig cfg;
    if (!WebPInitDecoderConfig(&cfg)) return Status::kFailed;
    const bool scaled = (dw != w || dh != h);
    cfg.options.use_scaling = scaled ? 1 : 0;
    cfg.options.scaled_width = dw;
    cfg.options.scaled_height = dh;
    if (scaled && std::max(w, h) >= 2 * opt.targetSize) {  // shrinking this much hides what the shortcuts cost
        cfg.options.bypass_filtering = 1;
        cfg.options.no_fancy_upsampling = 1;
    }
    r.px.assign(static_cast<size_t>(dw) * dh * ch, 0);
    cfg.output.colorspace = ch == 4 ? MODE_RGBA : MODE_RGB;
    cfg.output.is_external_memory = 1;
    cfg.output.width = dw;
    cfg.output.height = dh;
    cfg.output.u.RGBA.rgba = r.px.data();
    cfg.output.u.RGBA.stride = dw * ch;
    cfg.output.u.RGBA.size = r.px.size();
    const VP8StatusCode st = WebPDecode(data.data(), data.size(), &cfg);
    WebPFreeDecBuffer(&cfg.output);
    if (st != VP8_STATUS_OK) return Status::kFailed;

    bool translucent = false;
    if (ch == 4) {
        for (size_t i = 3; i < r.px.size(); i += 4) {
            if (r.px[i] != 255) { translucent = true; break; }
        }
    }
    r.w = dw;
    r.h = dh;
    r.ch = ch;
    r.storedW = w;
    r.storedH = h;
    r.orientation = 1;
    r.hasAlpha = translucent;
    return Status::kOk;
}

// ───────────────────────── 5. encoders ─────────────────────────

bool encodeJpeg(const uint8_t* rgb, int w, int h, int quality, std::vector<uint8_t>& out) {
    struct Job {
        jpeg_compress_struct cinfo;
        JpegErr err;
        unsigned char* mem = nullptr;
        unsigned long memLen = 0;
        bool created = false;
        ~Job() {
            if (created) jpeg_destroy_compress(&cinfo);
            std::free(mem);
        }
    } job;
    std::memset(&job.cinfo, 0, sizeof(job.cinfo));
    std::memset(&job.err, 0, sizeof(job.err));
    job.cinfo.err = jpeg_std_error(&job.err.pub);
    job.err.pub.error_exit = jpegErrorExit;
    job.err.pub.emit_message = jpegEmit;
    job.err.pub.output_message = jpegOutput;
    if (setjmp(job.err.jb)) return false;
    jpeg_create_compress(&job.cinfo);
    job.created = true;
    jpeg_mem_dest(&job.cinfo, &job.mem, &job.memLen);
    job.cinfo.image_width = static_cast<JDIMENSION>(w);
    job.cinfo.image_height = static_cast<JDIMENSION>(h);
    job.cinfo.input_components = 3;
    job.cinfo.in_color_space = JCS_RGB;
    jpeg_set_defaults(&job.cinfo);
    jpeg_set_quality(&job.cinfo, std::clamp(quality, 1, 100), TRUE);
    job.cinfo.optimize_coding = TRUE;  // better tables for small pictures; negligible cost at this size
    jpeg_start_compress(&job.cinfo, TRUE);
    while (job.cinfo.next_scanline < job.cinfo.image_height) {
        JSAMPROW rp = const_cast<uint8_t*>(rgb) + static_cast<size_t>(job.cinfo.next_scanline) * w * 3;
        jpeg_write_scanlines(&job.cinfo, &rp, 1);
    }
    jpeg_finish_compress(&job.cinfo);
    out.assign(job.mem, job.mem + job.memLen);
    return true;
}

void pngWrite(png_structp p, png_bytep data, size_t n) {
    auto* v = static_cast<std::vector<uint8_t>*>(png_get_io_ptr(p));
    v->insert(v->end(), data, data + n);
}
void pngFlush(png_structp) {}

bool encodePng(const uint8_t* px, int w, int h, int ch, std::vector<uint8_t>& out) {
    struct Job {
        png_structp png = nullptr;
        png_infop info = nullptr;
        ~Job() {
            if (png) png_destroy_write_struct(&png, &info);
        }
    } job;
    job.png = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, pngError, pngWarn);
    if (!job.png) return false;
    job.info = png_create_info_struct(job.png);
    if (!job.info) return false;
    if (setjmp(png_jmpbuf(job.png))) return false;
    out.clear();
    png_set_write_fn(job.png, &out, pngWrite, pngFlush);
    png_set_IHDR(job.png, job.info, static_cast<png_uint_32>(w), static_cast<png_uint_32>(h), 8,
                 ch == 4 ? PNG_COLOR_TYPE_RGB_ALPHA : PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE,
                 PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
    png_set_compression_level(job.png, 1);  // thumbnails: speed over the last few percent
    png_set_filter(job.png, PNG_FILTER_TYPE_BASE, PNG_FILTER_SUB);
    png_write_info(job.png, job.info);
    for (int y = 0; y < h; ++y) png_write_row(job.png, const_cast<png_bytep>(px + static_cast<size_t>(y) * w * ch));
    png_write_end(job.png, nullptr);
    return true;
}

}  // namespace

void setMemoryBudget(uint64_t bytes) { MemoryBudget::get().setLimit(bytes); }

bool isLikelyBlank(const uint8_t* px, int w, int h, int ch) {
    if (!px || w <= 0 || h <= 0 || (ch != 3 && ch != 4)) return false;
    constexpr int kGrid = 8, kTotal = kGrid * kGrid;
    int minLuma = 255, maxLuma = 0, minR = 255, maxR = 0, minG = 255, maxG = 0, minB = 255, maxB = 0;
    int sumLuma = 0, dark = 0, bright = 0;
    int lumas[kTotal];
    int n = 0;
    for (int row = 0; row < kGrid; ++row) {
        for (int col = 0; col < kGrid; ++col) {
            const int x = std::clamp(static_cast<int>(((col + 0.5) / kGrid) * w), 0, w - 1);
            const int y = std::clamp(static_cast<int>(((row + 0.5) / kGrid) * h), 0, h - 1);
            const uint8_t* p = px + (static_cast<size_t>(y) * w + x) * ch;
            const int r = p[0], g = p[1], b = p[2];
            const int luma = (r * 299 + g * 587 + b * 114) / 1000;
            lumas[n++] = luma;
            sumLuma += luma;
            if (luma < 25) ++dark;
            if (luma > 230) ++bright;
            minLuma = std::min(minLuma, luma);
            maxLuma = std::max(maxLuma, luma);
            minR = std::min(minR, r); maxR = std::max(maxR, r);
            minG = std::min(minG, g); maxG = std::max(maxG, g);
            minB = std::min(minB, b); maxB = std::max(maxB, b);
        }
    }
    const int lumaRange = maxLuma - minLuma;
    const int channelRange = std::max({maxR - minR, maxG - minG, maxB - minB});
    if (lumaRange <= 14 && channelRange <= 18) return true;  // solid / flat colour
    const double avg = static_cast<double>(sumLuma) / kTotal;
    if (avg < 18.0 || avg > 240.0) return true;                                // near pitch-black or blown-out
    if (dark >= kTotal * 0.80 && avg < 35.0) return true;                      // slates and title cards
    if (bright >= kTotal * 0.85 && avg > 215.0) return true;
    double variance = 0.0;
    for (int i = 0; i < kTotal; ++i) {
        const double d = lumas[i] - avg;
        variance += d * d;
    }
    return std::sqrt(variance / kTotal) < 8.0;  // low contrast / low detail
}

Status makeThumbnail(ByteSource& src, const Options& optIn, Thumbnail& out) {
    try {
        Options opt = optIn;
        if (opt.targetSize < 1) opt.targetSize = 1;
        const int64_t total = src.size();
        if (total >= 0 && static_cast<uint64_t>(total) > opt.maxSourceBytes) return Status::kTooLarge;

        uint8_t head[16];
        const int64_t n = src.readAt(0, head, sizeof(head));
        if (n < 0) return Status::kIoError;
        const Format fmt = sniffFormat(head, static_cast<size_t>(n));

        Raster r;
        Status st = Status::kUnsupported;
        switch (fmt) {
            case Format::kJpeg: st = decodeJpeg(src, opt, r); break;
            case Format::kPng: st = decodePng(src, opt, r); break;
            case Format::kWebp: st = decodeWebp(src, opt, r); break;
            case Format::kUnknown: return n == 0 ? Status::kFailed : Status::kUnsupported;
        }
        if (st != Status::kOk) return st;

        applyOrientation(r);
        const bool sideways = r.orientation >= 5 && r.orientation <= 8;
        out.sourceWidth = sideways ? r.storedH : r.storedW;
        out.sourceHeight = sideways ? r.storedW : r.storedH;
        out.width = r.w;
        out.height = r.h;
        out.hasAlpha = r.hasAlpha;
        out.isBlank = isLikelyBlank(r.px.data(), r.w, r.h, r.ch);

        if (r.ch == 4 && r.hasAlpha) {
            out.isPng = true;
            return encodePng(r.px.data(), r.w, r.h, 4, out.bytes) ? Status::kOk : Status::kFailed;
        }
        out.isPng = false;
        if (r.ch == 4) {  // opaque after all: drop the alpha channel
            std::vector<uint8_t> rgb(static_cast<size_t>(r.w) * r.h * 3);
            for (size_t i = 0, o = 0; i < r.px.size(); i += 4, o += 3) {
                rgb[o] = r.px[i];
                rgb[o + 1] = r.px[i + 1];
                rgb[o + 2] = r.px[i + 2];
            }
            r.px.swap(rgb);
            r.ch = 3;
        }
        return encodeJpeg(r.px.data(), r.w, r.h, opt.quality, out.bytes) ? Status::kOk : Status::kFailed;
    } catch (const std::bad_alloc&) {
        return Status::kNoMemory;
    } catch (...) {
        return Status::kFailed;
    }
}

}  // namespace veimg
