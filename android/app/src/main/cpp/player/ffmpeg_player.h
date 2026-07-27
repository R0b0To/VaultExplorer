#pragma once

#include <jni.h>
#include <android/native_window.h>
#include <string>
#include <atomic>
#include <cstdint>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <queue>
#include <vector>
#include <oboe/Oboe.h>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavutil/imgutils.h>
#include <libavutil/time.h>
#include <libavutil/opt.h>
#include <libavutil/channel_layout.h>
#include <libavutil/display.h>
}

class FFmpegPlayer : public oboe::AudioStreamDataCallback {
public:
    FFmpegPlayer(JNIEnv* env, jobject plugin_instance, ANativeWindow* window);
    ~FFmpegPlayer();

    void setDataSource(int fd, bool autoPlay);
    void play();
    void pause();
    void stop();
    void seekTo(int64_t positionMs);
    void setVolume(int volume);
    void setPlaybackSpeed(float speed);
    void setLooping(bool looping);

    // Synchronous, JNI-thread-safe snapshot of decoder-level diagnostics
    // (codec, resolution, frame rate, bitrate, live frame counters...) for
    // the debug overlay. Unlike notifyEvent(), this is a pull rather than a
    // push -- called directly from the JNI bridge function on whatever
    // thread the Flutter method channel call arrived on, using the JNIEnv
    // JNI already handed that thread, so it doesn't need getJniEnv()'s
    // attach dance. Returns a local ref to a new java.util.HashMap.
    jobject getDiagnosticsSnapshot(JNIEnv* env);

    oboe::DataCallbackResult onAudioReady(oboe::AudioStream* audioStream, void* audioData, int32_t numFrames) override;

private:
    // Tunable pipeline constants. Grouped here so the thresholds governing
    // buffering, polling, and A/V sync are named and visible in one place
    // instead of as bare literals scattered through the .cpp.
    static constexpr int kIoBufferSize = 32768;               // avio staging buffer, bytes
    static constexpr size_t kMaxQueuedVideoPackets = 30;
    static constexpr size_t kMaxQueuedAudioPackets = 30;
    static constexpr int kIdlePollIntervalMs = 10;             // paused / queues-full idle sleep
    static constexpr int kEofIdlePollIntervalMs = 50;          // idle sleep once input_eof is set
    static constexpr int kTimeChangedNotifyEveryNFrames = 15;  // "timeChanged" event throttle
    static constexpr int kDrainMaxIterations = 500;            // waitForQueuesDrained cap (~5s)
    static constexpr int kDrainPollIntervalMs = 10;
    static constexpr int kDrainGraceMs = 60;                   // post-drain settle time
    static constexpr double kAvSyncMinDiffSec = 0.005;         // below this, don't bother sleeping
    static constexpr double kAvSyncMaxDiffSec = 1.0;           // above this, audio_clock is untrusted
    static constexpr double kAvSyncFrameDropThresholdSec = 0.3; // beyond this far behind, drop the frame instead of burst-rendering it
    static constexpr int kFallbackFrameDelayMs = 33;           // used when avg_frame_rate is unknown
    static constexpr double kFpsWindowSec = 1.0;               // measured_fps rolling window
    static constexpr int kOutputSampleRate = 48000;            // fixed oboe/swr output rate
    static constexpr int kOutputChannels = 2;                  // fixed oboe/swr output channel count
    static constexpr size_t kMaxBufferedAudioFrames = 24000;   // 0.5s backpressure limit

    void demuxThreadFunc();
    void videoDecodeThreadFunc();
    void audioDecodeThreadFunc();
    void performPendingSeek(); // called only from demux_thread
    void waitForQueuesDrained(); // called only from demux_thread
    
    static int readPacketCallback(void* opaque, uint8_t* buf, int buf_size);
    static int64_t seekCallback(void* opaque, int64_t offset, int whence);

    void notifyEvent(const char* eventName, double positionMs = 0, double durationMs = 0, int width = 0, int height = 0, const char* errorMsg = nullptr, int rotationDegrees = -1);

    // Shared by notifyEvent()'s "playing" call (so rotation rides along on
    // the same event that already reliably delivers width/height, instead
    // of requiring a second, independent fetch) and getDiagnosticsSnapshot()
    // (for the debug overlay, kept as a fallback/cross-check). Reads the MP4
    // "tkhd" rotation matrix straight off the AVStream that's actually being
    // decoded -- see the .cpp definition for why this replaced a
    // MediaMetadataRetriever-based read through the app's custom content://
    // provider. Returns degrees clockwise in [0, 360), or -1 if the stream
    // has no display-matrix side data (i.e. no rotation).
    static int detectRotationDegrees(AVFormatContext* fmt, int videoStreamIdx);
    JNIEnv* getJniEnv();

    // java.util.HashMap/Double/Integer/Long and the plugin's
    // onEventFromNative are all resolved via FindClass/GetMethodID/
    // GetObjectClass fresh on every single notifyEvent()/
    // getDiagnosticsSnapshot() call -- notifyEvent() alone can fire many
    // times a second (every ~15th decoded video frame, see
    // kTimeChangedNotifyEveryNFrames). jclass/jmethodID are stable for the
    // lifetime of the class (not tied to any particular instance or JNIEnv),
    // so they're safe to resolve once, as global refs, and reuse from then
    // on -- ensureJniCache()/ensureEventMethodCache() do that lazily on
    // first use. java.util.HashMap/Double/Integer/Long are bootstrap-
    // classloader framework classes, so (unlike an app-defined class)
    // FindClass for them is safe to call from any attached thread,
    // including the demux/video/audio decode threads -- see getJniEnv().
    static void ensureJniCache(JNIEnv* env);
    static std::once_flag jni_cache_once;
    static jclass hashmap_class;
    static jmethodID hashmap_init;
    static jmethodID hashmap_put;
    static jclass double_class;
    static jmethodID double_init;
    static jclass integer_class;
    static jmethodID integer_init;
    static jclass long_class;
    static jmethodID long_init;

    // Cached separately from the framework classes above: this one is
    // keyed off plugin_instance_ref (an app class, FFmpegPlayerEngine),
    // resolved via GetObjectClass rather than FindClass specifically
    // because FindClass for app-defined classes is unreliable from a
    // native-created thread (demux/video/audio threads) whose classloader
    // context isn't the app's -- see getJniEnv()'s attach dance. Every
    // FFmpegPlayer instance shares the one FFmpegPlayerEngine class object,
    // so per-process caching (rather than per-instance) is correct here too.
    void ensureEventMethodCache(JNIEnv* env);
    static std::once_flag event_method_once;
    static jclass plugin_class;
    static jmethodID on_event_method;

    JavaVM* jvm = nullptr;
    jobject plugin_instance_ref = nullptr;
    ANativeWindow* native_window = nullptr;

    std::atomic<bool> is_playing{false};
    std::atomic<bool> stop_requested{false};
    std::atomic<bool> looping{false};
    std::atomic<float> playback_speed{1.0f};
    std::atomic<float> volume_multiplier{1.0f};

    // seekTo() is called from whatever thread handles the Flutter method
    // channel, but format_ctx is only ever safe to touch from
    // demux_thread (it's also mid-av_read_frame() there at any given
    // moment). So seekTo() just records the request here; demuxThreadFunc
    // performs the actual av_seek_frame() + codec flush itself, at the top
    // of its own loop, whether that request came from the app or from
    // this same thread looping back to 0 at EOF.
    std::atomic<bool> seek_requested{false};
    std::atomic<int64_t> seek_target_ms{0};

    // Set once av_read_frame() genuinely runs out of input (demux_thread,
    // non-looping path) and cleared on setDataSource()/performPendingSeek().
    // videoDecodeThreadFunc's A/V-sync block uses this to stop trusting
    // audio_clock once no more audio packets will ever arrive -- see that
    // block's comment for why a frozen audio_clock otherwise makes
    // playback crawl to a near-halt right before the end.
    std::atomic<bool> input_eof{false};

    // avcodec_flush_buffers() (called from performPendingSeek(), which
    // only ever runs on demux_thread) must not run concurrently with
    // avcodec_send_packet()/avcodec_receive_frame() on the same context
    // from video_thread/audio_thread -- FFmpeg does not guarantee any
    // safety between those calls without external locking. These guard
    // every access to their respective codec context so a seek's flush
    // can't land mid-decode (see performPendingSeek()'s comment for the
    // crash this caused).
    std::mutex video_codec_mutex;
    std::mutex audio_codec_mutex;

    int media_fd = -1;
    int64_t media_size = 0;

    // Guards format_ctx/io_ctx/video_codec_ctx/audio_codec_ctx against a
    // genuine use-after-free between stop() freeing them and
    // getDiagnosticsSnapshot() reading them. Every other access to these
    // pointers (demux_thread/video_thread/audio_thread) is already safe
    // without it: those threads are always join()'d by stop() before it
    // frees anything (see stop()'s ordering), so there's no concurrent
    // free/use between them. getDiagnosticsSnapshot() is different -- it's
    // called directly from whatever thread the Flutter method channel
    // handed the JNI bridge, with no join() or other ordering against
    // stop() at all, so without this lock a stop() (e.g. the user backing
    // out of the viewer) racing a diagnostics call could free one of these
    // out from under it. Held only briefly at each assignment/free site
    // (not across avformat_open_input/avformat_find_stream_info, which can
    // block for a while) and for the duration of getDiagnosticsSnapshot's
    // read -- see that function for why the whole read has to be inside
    // the lock rather than just the null-checks.
    std::mutex native_state_mutex;

    AVFormatContext* format_ctx = nullptr;
    AVIOContext* io_ctx = nullptr;
    
    int video_stream_idx = -1;
    int audio_stream_idx = -1;
    AVCodecContext* video_codec_ctx = nullptr;
    AVCodecContext* audio_codec_ctx = nullptr;

    std::thread demux_thread;
    std::thread video_thread;
    std::thread audio_thread;

    std::queue<AVPacket*> video_queue;
    std::queue<AVPacket*> audio_queue;
    std::mutex video_queue_mutex;
    std::mutex audio_queue_mutex;
    std::condition_variable video_queue_cond;
    std::condition_variable audio_queue_cond;

    SwrContext* swr_ctx = nullptr;

    // Separate from swr_ctx above, which only ever runs codec-format ->
    // FLT/stereo/kOutputSampleRate once per decoded frame on the decode
    // thread. This one is FLT/stereo -> FLT/stereo and exists purely to
    // change the *declared* input rate to reflect playback_speed, so
    // onAudioReady() can pull resampled audio through FFmpeg's own
    // (anti-aliased) resampler instead of the hand-rolled linear
    // interpolation it used to do. Reconfigured only from
    // setPlaybackSpeed() -- swr_alloc/swr_init/swr_free must never run on
    // the real-time Oboe audio thread, since unbounded allocation there is
    // how audio glitches happen. audio_buf_mutex (already held for all of
    // onAudioReady) guards the pointer swap so the audio thread never
    // observes a torn/half-initialized context.
    SwrContext* speed_swr_ctx = nullptr;

    std::shared_ptr<oboe::AudioStream> audio_stream;
    
    std::mutex audio_buf_mutex;
    std::vector<float> audio_buffer;
    std::atomic<double> audio_clock{0.0};
    std::atomic<double> audio_chunk_end_pts{0.0};
    std::atomic<double> video_clock{0.0};

    // Diagnostics-only counters read by getDiagnosticsSnapshot(). Written
    // exclusively from video_thread (videoDecodeThreadFunc), so no mutex is
    // needed for the writes themselves -- only atomic for the cross-thread
    // read from getDiagnosticsSnapshot(). measured_fps is a rolling actual-
    // render rate (distinct from the container's declared avg_frame_rate),
    // recomputed once per ~1s window using a monotonic clock so it isn't
    // affected by system clock adjustments. fps_window_reset_requested lets
    // performPendingSeek() (demux_thread) ask video_thread to restart that
    // window after a seek, so one post-seek window doesn't get diluted by
    // the stall while queues were flushed/refilled.
    std::atomic<double> measured_fps{0.0};
    std::atomic<uint64_t> frames_rendered_total{0};
    std::atomic<uint64_t> frames_decoded_total{0};
    std::atomic<bool> fps_window_reset_requested{false};

    // Was previously `static int frame_count` local to
    // videoDecodeThreadFunc -- a function-local static is one variable
    // shared by every call to that function *from every FFmpegPlayer
    // instance in the process*, not one per instance. With a single player
    // alive at a time (today's usage) that's harmless; the moment two
    // players ever run concurrently (picture-in-picture, playlist
    // prefetch, etc.) their video_threads would race on the same counter
    // with no synchronization -- a genuine data race, plus the throttle
    // would fire at whatever combined rate both threads happen to hit it.
    // Only ever touched from this instance's own video_thread, so plain
    // (non-atomic) is correct.
    int frame_notify_count = 0;

    SwsContext* sws_ctx = nullptr;
};