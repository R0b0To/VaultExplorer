// Native video thumbnails: open a video, decode ONE picture and hand back a small JPEG -- in a single blocking call,
// without a player. Platform-neutral C++17 on top of FFmpeg's libavformat / libavcodec / libswscale (a minimal,
// software-only, static build; see ffmpeg_deps.cmake); the bytes come from a [ByteSource], so a file inside an
// unlocked vault is read straight through the engine, never staged on disk and never served over a socket.
//
// What replaces what: the desktop route used to start a whole libmpv instance (renderer, texture, audio output,
// a loopback HTTP server session) for every frame it wanted, once for the start of the video and again for every
// retry, all of it driven from the UI isolate. Here the cost of a thumbnail is the I/O for the container header
// plus decoding a single keyframe, and several can run at once on worker threads.
//
// The frame-selection rules are Android's (and desktop_video_thumbnails.dart's):
//   firstFrame        the picture at the start;
//   frameAtPercentage the picture at `framePosition` of the duration (clamped to 5%..90%);
//   hybrid            the start, and when that looks blank (black leader, fade-in, slate) the first not-blank
//                     picture at `framePosition`, 25% or 45%.
// An explicit time (the editor's film strip) wins over all of it and is never retried.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "thumb.h"

namespace veimg {

enum class VideoStrategy { kFirstFrame = 0, kFrameAtPercentage = 1, kHybrid = 2 };

struct VideoOptions {
    int targetSize = 180;
    int quality = 75;  // JPEG
    VideoStrategy strategy = VideoStrategy::kHybrid;
    double framePosition = 0.12;
    // >= 0: exactly that point (0 = the start); the strategy is ignored and nothing is retried.
    int64_t explicitTimeUs = -1;
    // The whole call, including every retry. A source that cannot be read in time fails instead of hanging.
    int timeoutMs = 20000;
};

struct VideoThumbnail {
    Thumbnail thumb;  // sourceWidth/Height: the picture as it is shown (rotation and pixel aspect applied)
    int64_t durationUs = 0;  // 0 when the container does not say
    // What happened, for logs: the container and codec, the picture size, the timings -- or why it stopped. Never
    // contains a file name or path. Filled on success and on failure alike.
    std::string diag;
};

// kUnsupported: not something this build can open or decode (an unknown container, a codec that is not compiled in,
// or a build without FFmpeg at all) -- the caller should use another route. kFailed: it is a video this build
// understands but no picture could be produced (corrupt, no video stream, timed out). kIoError: the source failed.
Status makeVideoThumbnail(ByteSource& src, const VideoOptions& opt, VideoThumbnail& out);

// True when this build has FFmpeg; false means makeVideoThumbnail() always answers kUnsupported.
bool videoThumbnailsAvailable();

// The pure parts of the frame selection, exposed for tests.
double clampThumbnailFraction(double fraction);                 // NaN -> 0.12; else clamped to 0.05..0.90
std::vector<double> blankFrameRetryFractions(double preferred); // [clamp(preferred), 0.25, 0.45] without repeats
int64_t timeAtFraction(int64_t durationUs, double fraction);    // round(duration * clamp(fraction))

}  // namespace veimg
