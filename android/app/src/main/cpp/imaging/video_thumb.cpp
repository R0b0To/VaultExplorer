// See video_thumb.h. Without VE_HAVE_FFMPEG this file only provides the pure helpers and a stub that answers
// "unsupported", so the engine links and runs the same either way and the caller falls back to another route.
#include "video_thumb.h"

#include <algorithm>
#include <cmath>

namespace veimg {

double clampThumbnailFraction(double fraction) {
    if (std::isnan(fraction)) return 0.12;
    return std::clamp(fraction, 0.05, 0.90);
}

std::vector<double> blankFrameRetryFractions(double preferred) {
    std::vector<double> out;
    for (double f : {clampThumbnailFraction(preferred), 0.25, 0.45}) {
        if (std::find(out.begin(), out.end(), f) == out.end()) out.push_back(f);
    }
    return out;
}

int64_t timeAtFraction(int64_t durationUs, double fraction) {
    return static_cast<int64_t>(std::llround(static_cast<double>(durationUs) * clampThumbnailFraction(fraction)));
}

}  // namespace veimg

#ifndef VE_HAVE_FFMPEG

namespace veimg {
bool videoThumbnailsAvailable() { return false; }
Status makeVideoThumbnail(ByteSource&, const VideoOptions&, VideoThumbnail& out) {
    out.diag = "this engine was built without FFmpeg";
    return Status::kUnsupported;
}
}  // namespace veimg

#else  // VE_HAVE_FFMPEG

#include <chrono>
#include <cstring>
#include <memory>
#include <new>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/display.h>
#include <libavutil/error.h>
#include <libavutil/log.h>
#include <libavutil/mem.h>
#include <libavutil/pixfmt.h>
#include <libswscale/swscale.h>
}

namespace veimg {

bool videoThumbnailsAvailable() { return true; }

namespace {

using Clock = std::chrono::steady_clock;

std::string avErr(int e) {
    char buf[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(e, buf, sizeof buf);
    return buf;
}

long long msSince(Clock::time_point t) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - t).count();
}

// ───────────────────────── I/O over a ByteSource ─────────────────────────

struct IoState {
    ByteSource* src = nullptr;
    int64_t pos = 0;
    int64_t size = -1;
    Clock::time_point deadline;
    bool ioError = false;
};

constexpr int kIoBufferSize = 256 * 1024;  // one readAt per refill; a vault read is far costlier than a memcpy

int readPacket(void* opaque, uint8_t* buf, int size) {
    auto* io = static_cast<IoState*>(opaque);
    const int64_t n = io->src->readAt(io->pos, buf, static_cast<size_t>(size));
    if (n < 0) {
        io->ioError = true;
        return AVERROR(EIO);
    }
    if (n == 0) return AVERROR_EOF;
    io->pos += n;
    return static_cast<int>(n);
}

int64_t seekPacket(void* opaque, int64_t offset, int whence) {
    auto* io = static_cast<IoState*>(opaque);
    whence &= ~AVSEEK_FORCE;
    if (whence == AVSEEK_SIZE) return io->size >= 0 ? io->size : AVERROR(ENOSYS);
    int64_t target;
    switch (whence) {
        case SEEK_SET: target = offset; break;
        case SEEK_CUR: target = io->pos + offset; break;
        case SEEK_END:
            if (io->size < 0) return AVERROR(ENOSYS);
            target = io->size + offset;
            break;
        default: return AVERROR(EINVAL);
    }
    if (target < 0) return AVERROR(EINVAL);
    io->pos = target;
    return target;
}

int interruptCallback(void* opaque) { return Clock::now() > static_cast<IoState*>(opaque)->deadline ? 1 : 0; }

// ───────────────────────── RAII ─────────────────────────

struct Source {
    IoState io;
    AVIOContext* pb = nullptr;
    AVFormatContext* fmt = nullptr;
    AVCodecContext* dec = nullptr;
    AVPacket* pkt = nullptr;
    AVFrame* frame = nullptr;
    SwsContext* sws = nullptr;
    int sws_w = 0, sws_h = 0, sws_dw = 0, sws_dh = 0, sws_fmt = -1;
    ~Source() {
        if (sws) sws_freeContext(sws);
        if (frame) av_frame_free(&frame);
        if (pkt) av_packet_free(&pkt);
        if (dec) avcodec_free_context(&dec);
        if (fmt) avformat_close_input(&fmt);  // custom IO: leaves `pb` alone
        if (pb) {
            av_freep(&pb->buffer);
            avio_context_free(&pb);
        }
    }
};

// ───────────────────────── geometry & colour ─────────────────────────

// EXIF-style orientation for the stream's display matrix (rotation recorded by phones), 1 when there is none.
int orientationOf(const AVStream* st) {
    const AVPacketSideData* sd = av_packet_side_data_get(st->codecpar->coded_side_data, st->codecpar->nb_coded_side_data,
                                                         AV_PKT_DATA_DISPLAYMATRIX);
    if (!sd || sd->size < static_cast<size_t>(sizeof(int32_t) * 9)) return 1;
    const double angle = av_display_rotation_get(reinterpret_cast<const int32_t*>(sd->data));  // degrees, counter-clockwise
    if (std::isnan(angle)) return 1;
    const double a = std::fmod(std::fmod(angle, 360.0) + 360.0, 360.0);  // 0..360
    if (std::fabs(a - 90.0) < 1.0) return 8;   // 90 CCW  = EXIF "rotate 270 CW"
    if (std::fabs(a - 180.0) < 1.0) return 3;
    if (std::fabs(a - 270.0) < 1.0) return 6;  // 90 CW
    return 1;
}

int colorSpaceOf(const AVFrame* f) {
    switch (f->colorspace) {
        case AVCOL_SPC_BT709: return SWS_CS_ITU709;
        case AVCOL_SPC_BT470BG:
        case AVCOL_SPC_SMPTE170M: return SWS_CS_ITU601;
        case AVCOL_SPC_SMPTE240M: return SWS_CS_SMPTE240M;
        case AVCOL_SPC_BT2020_NCL:
        case AVCOL_SPC_BT2020_CL: return SWS_CS_BT2020;
        default: return (f->height >= 720 || f->width >= 1280) ? SWS_CS_ITU709 : SWS_CS_ITU601;  // what players assume
    }
}

// Scales `f` to RGB24 at dw x dh into `out` (tightly packed).
bool scaleToRgb(Source& s, const AVFrame* f, int dw, int dh, std::vector<uint8_t>& out) {
    if (!s.sws || s.sws_w != f->width || s.sws_h != f->height || s.sws_dw != dw || s.sws_dh != dh || s.sws_fmt != f->format) {
        if (s.sws) sws_freeContext(s.sws);
        s.sws = sws_getContext(f->width, f->height, static_cast<AVPixelFormat>(f->format), dw, dh, AV_PIX_FMT_RGB24,
                               SWS_AREA | SWS_ACCURATE_RND, nullptr, nullptr, nullptr);
        s.sws_w = f->width;
        s.sws_h = f->height;
        s.sws_dw = dw;
        s.sws_dh = dh;
        s.sws_fmt = f->format;
        if (!s.sws) return false;
        // Without this swscale assumes BT.601 / limited range for every YUV picture: HD video would be tinted.
        sws_setColorspaceDetails(s.sws, sws_getCoefficients(colorSpaceOf(f)), f->color_range == AVCOL_RANGE_JPEG ? 1 : 0,
                                 sws_getCoefficients(SWS_CS_DEFAULT), 1, 0, 1 << 16, 1 << 16);
    }
    // swscale's SIMD writes in whole vectors: give it an aligned stride and a little slack, then copy tight.
    const int stride = (dw * 3 + 31) & ~31;
    std::vector<uint8_t> padded(static_cast<size_t>(stride) * dh + 64);
    uint8_t* dst[4] = {padded.data(), nullptr, nullptr, nullptr};
    int dstStride[4] = {stride, 0, 0, 0};
    if (sws_scale(s.sws, f->data, f->linesize, 0, f->height, dst, dstStride) != dh) return false;
    out.resize(static_cast<size_t>(dw) * dh * 3);
    for (int y = 0; y < dh; ++y) std::memcpy(&out[static_cast<size_t>(y) * dw * 3], &padded[static_cast<size_t>(y) * stride], static_cast<size_t>(dw) * 3);
    return true;
}

// ───────────────────────── frame grabbing ─────────────────────────

struct Grab {
    Source* s;
    int videoIndex;
    bool atStart = true;  // nothing read yet: no seek needed for the start
    int64_t startTime = 0;
};

// Decodes one picture at `timeUs` (<= 0: the start). A keyframe: the nearest one at or before the point.
bool grabFrame(Grab& g, int64_t timeUs, Clock::time_point deadline) {
    Source& s = *g.s;
    if (!(timeUs <= 0 && g.atStart)) {
        if (av_seek_frame(s.fmt, -1, g.startTime + std::max<int64_t>(timeUs, 0), AVSEEK_FLAG_BACKWARD) < 0) return false;
        avcodec_flush_buffers(s.dec);
    }
    g.atStart = false;
    s.dec->skip_frame = AVDISCARD_NONKEY;  // only whole pictures; also skips undecodable leading B-frames
    constexpr int kKeyframeBudget = 96;    // video packets without a picture before trying every frame type
    constexpr int kGiveUp = 600;
    int packets = 0;
    for (;;) {
        if (Clock::now() > deadline) return false;
        int r = av_read_frame(s.fmt, s.pkt);
        if (r < 0) {  // end of the data (or a read error): whatever the decoder still holds
            avcodec_send_packet(s.dec, nullptr);
            av_frame_unref(s.frame);
            return avcodec_receive_frame(s.dec, s.frame) >= 0;
        }
        if (s.pkt->stream_index != g.videoIndex) {
            av_packet_unref(s.pkt);
            continue;
        }
        ++packets;
        r = avcodec_send_packet(s.dec, s.pkt);
        av_packet_unref(s.pkt);
        if (r >= 0 || r == AVERROR(EAGAIN)) {
            av_frame_unref(s.frame);
            if (avcodec_receive_frame(s.dec, s.frame) >= 0) return true;
        }
        if (packets == kKeyframeBudget) s.dec->skip_frame = AVDISCARD_DEFAULT;  // streams that mark no keyframes
        if (packets >= kGiveUp) return false;
    }
}

Status frameToThumbnail(Source& s, const AVStream* st, const AVFrame* f, const VideoOptions& opt, VideoThumbnail& out) {
    int srcW = f->width, srcH = f->height;
    if (srcW <= 0 || srcH <= 0) return Status::kFailed;
    // The picture as it is meant to be shown: pixel aspect ratio applied to the width, then rotation.
    int dispW = srcW;
    const AVRational sar = av_guess_sample_aspect_ratio(s.fmt, const_cast<AVStream*>(st), const_cast<AVFrame*>(f));
    if (sar.num > 0 && sar.den > 0 && sar.num != sar.den)
        dispW = std::max(1, static_cast<int>(std::llround(static_cast<double>(srcW) * sar.num / sar.den)));
    int dw, dh;
    fitWithin(dispW, srcH, opt.targetSize, dw, dh);
    std::vector<uint8_t> rgb;
    if (!scaleToRgb(s, f, dw, dh, rgb)) return Status::kFailed;
    return finishThumbnail(std::move(rgb), dw, dh, orientationOf(st), dispW, srcH, opt.quality, out.thumb);
}

}  // namespace

Status makeVideoThumbnail(ByteSource& src, const VideoOptions& optIn, VideoThumbnail& out) {
    // FFmpeg narrates every oddity of a file on stderr. Nobody can act on that here; the status says what happened.
    static const bool quiet = (av_log_set_level(AV_LOG_QUIET), true);
    (void)quiet;
    try {
        VideoOptions opt = optIn;
        opt.targetSize = std::max(opt.targetSize, 1);
        const auto deadline = Clock::now() + std::chrono::milliseconds(std::max(opt.timeoutMs, 1000));

        const auto started = Clock::now();
        // Every early exit says why, in `out.diag`.
        auto bail = [&](Status st, std::string why) {
            out.diag = std::move(why) + " | " + std::to_string(msSince(started)) + "ms";
            return st;
        };

        Source s;
        s.io.src = &src;
        s.io.size = src.size();
        s.io.deadline = deadline;
        auto* buffer = static_cast<uint8_t*>(av_malloc(kIoBufferSize));
        if (!buffer) return bail(Status::kNoMemory, "out of memory (io buffer)");
        s.pb = avio_alloc_context(buffer, kIoBufferSize, 0, &s.io, readPacket, nullptr, seekPacket);
        if (!s.pb) {
            av_free(buffer);
            return bail(Status::kNoMemory, "out of memory (avio)");
        }
        s.fmt = avformat_alloc_context();
        if (!s.fmt) return bail(Status::kNoMemory, "out of memory (format context)");
        s.fmt->pb = s.pb;
        s.fmt->flags |= AVFMT_FLAG_CUSTOM_IO;
        s.fmt->interrupt_callback.callback = interruptCallback;
        s.fmt->interrupt_callback.opaque = &s.io;
        s.fmt->probesize = 4 << 20;                    // enough to find the video's parameters; bounds the up-front read
        s.fmt->max_analyze_duration = 2 * AV_TIME_BASE;

        int r = avformat_open_input(&s.fmt, "", nullptr, nullptr);  // on failure frees and nulls s.fmt
        if (r < 0)  // not a container this build knows (or the source failed)
            return bail(s.io.ioError ? Status::kIoError : Status::kUnsupported, "open_input: " + avErr(r));
        const std::string container = s.fmt->iformat && s.fmt->iformat->name ? s.fmt->iformat->name : "?";
        const auto opened = Clock::now();
        r = avformat_find_stream_info(s.fmt, nullptr);
        if (r < 0)
            return bail(s.io.ioError ? Status::kIoError : Status::kFailed, container + ": find_stream_info: " + avErr(r));

        const AVCodec* codec = nullptr;
        const int vi = av_find_best_stream(s.fmt, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
        if (vi == AVERROR_DECODER_NOT_FOUND) {  // a video, but its codec is not compiled in
            std::string name = "?";
            for (unsigned i = 0; i < s.fmt->nb_streams; ++i)
                if (s.fmt->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
                    name = avcodec_get_name(s.fmt->streams[i]->codecpar->codec_id);
                    break;
                }
            return bail(Status::kUnsupported, container + ": no decoder built in for video codec " + name);
        }
        if (vi < 0) return bail(Status::kFailed, container + ": no video stream");
        AVStream* st = s.fmt->streams[vi];
        if (!codec) return bail(Status::kUnsupported, container + ": no decoder");
        const std::string codecName = codec->name ? codec->name : "?";
        for (unsigned i = 0; i < s.fmt->nb_streams; ++i)
            if (static_cast<int>(i) != vi) s.fmt->streams[i]->discard = AVDISCARD_ALL;  // audio, subtitles, covers

        s.dec = avcodec_alloc_context3(codec);
        if (!s.dec) return bail(Status::kNoMemory, "out of memory (decoder)");
        r = avcodec_parameters_to_context(s.dec, st->codecpar);
        if (r < 0) return bail(Status::kFailed, container + "/" + codecName + ": parameters: " + avErr(r));
        s.dec->thread_count = 1;  // parallelism comes from decoding several videos at once, not from one decode
        s.dec->skip_loop_filter = AVDISCARD_ALL;  // invisible at thumbnail size, and a real saving
        r = avcodec_open2(s.dec, codec, nullptr);
        if (r < 0)  // a profile it cannot decode
            return bail(Status::kUnsupported, container + "/" + codecName + ": avcodec_open2: " + avErr(r));
        s.pkt = av_packet_alloc();
        s.frame = av_frame_alloc();
        if (!s.pkt || !s.frame) return bail(Status::kNoMemory, "out of memory (packet/frame)");
        const std::string what = container + "/" + codecName + " " + std::to_string(st->codecpar->width) + "x" +
                                 std::to_string(st->codecpar->height) + " open=" + std::to_string(std::chrono::duration_cast<std::chrono::milliseconds>(opened - started).count()) +
                                 "ms probe=" + std::to_string(msSince(opened)) + "ms";

        Grab g;
        g.s = &s;
        g.videoIndex = vi;
        g.startTime = s.fmt->start_time != AV_NOPTS_VALUE ? s.fmt->start_time : 0;
        int64_t durationUs = s.fmt->duration != AV_NOPTS_VALUE ? s.fmt->duration : 0;
        if (durationUs <= 0 && st->duration != AV_NOPTS_VALUE) durationUs = av_rescale_q(st->duration, st->time_base, AV_TIME_BASE_Q);
        durationUs = std::max<int64_t>(durationUs, 0);
        out.durationUs = durationUs;

        // One candidate: a grab and its conversion, or the reason it failed.
        auto candidate = [&](int64_t timeUs, VideoThumbnail& into) -> Status {
            if (!grabFrame(g, timeUs, deadline)) return s.io.ioError ? Status::kIoError : Status::kFailed;
            return frameToThumbnail(s, st, s.frame, opt, into);
        };

        if (opt.explicitTimeUs >= 0) {
            const Status ex = candidate(opt.explicitTimeUs, out);
            out.diag = what + " explicit " + (ex == Status::kOk ? "ok" : "failed") + " | " + std::to_string(msSince(started)) + "ms";
            return ex;
        }

        // The start always comes first: it needs no seek, and it is what 'firstFrame' and 'hybrid' want.
        Status st0 = candidate(0, out);
        if (st0 != Status::kOk) return bail(st0, what + ": no picture at the start");
        out.durationUs = durationUs;
        int retries = 0;

        switch (opt.strategy) {
            case VideoStrategy::kFirstFrame: break;
            case VideoStrategy::kFrameAtPercentage:
                if (durationUs > 0) {
                    VideoThumbnail c;
                    if (candidate(timeAtFraction(durationUs, opt.framePosition), c) == Status::kOk) {
                        out = std::move(c);  // a frame at the wanted position beats the first one
                        out.durationUs = durationUs;
                    }
                }
                break;
            case VideoStrategy::kHybrid:
                if (out.thumb.isBlank && durationUs > 0) {
                    for (double fraction : blankFrameRetryFractions(opt.framePosition)) {
                        VideoThumbnail c;
                        ++retries;
                        if (candidate(timeAtFraction(durationUs, fraction), c) != Status::kOk) continue;
                        if (!c.thumb.isBlank) {
                            out = std::move(c);
                            out.durationUs = durationUs;
                            break;
                        }
                    }
                }
                break;
        }
        out.diag = what + " blank_retries=" + std::to_string(retries) + " | " + std::to_string(msSince(started)) + "ms";
        return Status::kOk;
    } catch (const std::bad_alloc&) {
        out.diag = "out of memory";
        return Status::kNoMemory;
    } catch (...) {
        out.diag = "unexpected exception";
        return Status::kFailed;
    }
}

}  // namespace veimg

#endif  // VE_HAVE_FFMPEG
