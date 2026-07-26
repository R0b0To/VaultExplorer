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
    void demuxThreadFunc();
    void videoDecodeThreadFunc();
    void audioDecodeThreadFunc();
    void performPendingSeek(); // called only from demux_thread
    void waitForQueuesDrained(); // called only from demux_thread
    
    static int readPacketCallback(void* opaque, uint8_t* buf, int buf_size);
    static int64_t seekCallback(void* opaque, int64_t offset, int whence);

    void notifyEvent(const char* eventName, double positionMs = 0, double durationMs = 0, int width = 0, int height = 0, const char* errorMsg = nullptr);
    JNIEnv* getJniEnv();

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
    std::shared_ptr<oboe::AudioStream> audio_stream;
    
    std::mutex audio_buf_mutex;
    std::vector<float> audio_buffer;
    std::atomic<double> audio_clock{0.0};
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

    SwsContext* sws_ctx = nullptr;
};