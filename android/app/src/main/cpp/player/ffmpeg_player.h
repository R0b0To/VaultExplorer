#pragma once

#include <jni.h>
#include <android/native_window.h>
#include <string>
#include <atomic>
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

    oboe::DataCallbackResult onAudioReady(oboe::AudioStream* audioStream, void* audioData, int32_t numFrames) override;

private:
    void demuxThreadFunc();
    void videoDecodeThreadFunc();
    void audioDecodeThreadFunc();
    void performPendingSeek(); // called only from demux_thread
    
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

    int media_fd = -1;
    int64_t media_size = 0;

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

    SwsContext* sws_ctx = nullptr;
};