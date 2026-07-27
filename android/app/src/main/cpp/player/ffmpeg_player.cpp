#include "ffmpeg_player.h"
#include <android/log.h>
#include <unistd.h>
#include <sys/stat.h>
#include <cmath>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "FFmpegPlayer", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "FFmpegPlayer", __VA_ARGS__)
// (Prior temporary LOGD_SYNC/LOGD_AUDIO instrumentation for the
// seekbar-stepping / speed-hunting investigation has been removed now that
// the root causes are fixed -- see pause-gating in video/audioDecodeThreadFunc,
// frame-drop + frame-timer pacing in videoDecodeThreadFunc, and the demux
// admission-control fix in demuxThreadFunc. LOGD_SYNC in particular ran on
// the real-time Oboe audio callback thread, where __android_log_print()'s
// blocking I/O could itself perturb the timing being measured.)

FFmpegPlayer::FFmpegPlayer(JNIEnv* env, jobject plugin_instance, ANativeWindow* window) {
    env->GetJavaVM(&jvm);
    plugin_instance_ref = env->NewGlobalRef(plugin_instance);
    if (window) {
        native_window = window;
        ANativeWindow_acquire(native_window);
    }
}

FFmpegPlayer::~FFmpegPlayer() {
    stop();
    if (native_window) {
        ANativeWindow_release(native_window);
        native_window = nullptr;
    }
    JNIEnv* env = getJniEnv();
    if (env && plugin_instance_ref) {
        env->DeleteGlobalRef(plugin_instance_ref);
        plugin_instance_ref = nullptr;
    }
}

std::once_flag FFmpegPlayer::jni_cache_once;
jclass FFmpegPlayer::hashmap_class = nullptr;
jmethodID FFmpegPlayer::hashmap_init = nullptr;
jmethodID FFmpegPlayer::hashmap_put = nullptr;
jclass FFmpegPlayer::double_class = nullptr;
jmethodID FFmpegPlayer::double_init = nullptr;
jclass FFmpegPlayer::integer_class = nullptr;
jmethodID FFmpegPlayer::integer_init = nullptr;
jclass FFmpegPlayer::long_class = nullptr;
jmethodID FFmpegPlayer::long_init = nullptr;

std::once_flag FFmpegPlayer::event_method_once;
jclass FFmpegPlayer::plugin_class = nullptr;
jmethodID FFmpegPlayer::on_event_method = nullptr;

void FFmpegPlayer::ensureJniCache(JNIEnv* env) {
    std::call_once(jni_cache_once, [env]() {
        auto globalClass = [env](const char* name) -> jclass {
            jclass local = env->FindClass(name);
            jclass global = local ? (jclass)env->NewGlobalRef(local) : nullptr;
            if (local) env->DeleteLocalRef(local);
            return global;
        };

        hashmap_class = globalClass("java/util/HashMap");
        hashmap_init = env->GetMethodID(hashmap_class, "<init>", "()V");
        hashmap_put = env->GetMethodID(hashmap_class, "put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

        double_class = globalClass("java/lang/Double");
        double_init = env->GetMethodID(double_class, "<init>", "(D)V");

        integer_class = globalClass("java/lang/Integer");
        integer_init = env->GetMethodID(integer_class, "<init>", "(I)V");

        long_class = globalClass("java/lang/Long");
        long_init = env->GetMethodID(long_class, "<init>", "(J)V");
    });
}

void FFmpegPlayer::ensureEventMethodCache(JNIEnv* env) {
    std::call_once(event_method_once, [this, env]() {
        jclass local = env->GetObjectClass(plugin_instance_ref);
        plugin_class = local ? (jclass)env->NewGlobalRef(local) : nullptr;
        if (local) env->DeleteLocalRef(local);
        if (plugin_class) {
            on_event_method = env->GetMethodID(plugin_class, "onEventFromNative", "(Ljava/util/Map;)V");
        }
    });
}

JNIEnv* FFmpegPlayer::getJniEnv() {
    JNIEnv* env = nullptr;
    if (!jvm) return nullptr;
    if (jvm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        jvm->AttachCurrentThread(&env, nullptr);
    }
    return env;
}

// AVCodecParameters::coded_side_data is the current (non-deprecated) home
// for per-stream side data as of the FFmpeg version this project vendors --
// av_stream_get_side_data(), the older AVStream-level accessor, was removed
// from it entirely (see git history for that build error). This reads the
// display transformation matrix MOV/MP4 muxers store there for a rotated
// "tkhd" -- the exact same rotation Android's MediaRecorder writes via
// setOrientationHint() -- directly off the AVStream actively driving
// playback, rather than through a second, independent
// MediaMetadataRetriever pass over the same content:// URI (which is what
// this used to depend on, and is a much less reliable path: it goes through
// the app's custom content provider a second time, with its own seek/auth
// behavior, instead of the file descriptor this player already has open
// and is successfully decoding from).
int FFmpegPlayer::detectRotationDegrees(AVFormatContext* fmt, int videoStreamIdx) {
    if (!fmt || videoStreamIdx < 0 || videoStreamIdx >= (int)fmt->nb_streams) return -1;
    const AVCodecParameters* par = fmt->streams[videoStreamIdx]->codecpar;
    const int32_t* display_matrix = nullptr;
    for (int sd = 0; sd < par->nb_coded_side_data; sd++) {
        if (par->coded_side_data[sd].type == AV_PKT_DATA_DISPLAYMATRIX) {
            display_matrix = reinterpret_cast<const int32_t*>(par->coded_side_data[sd].data);
            break;
        }
    }
    if (!display_matrix) return -1;
    // av_display_rotation_get() returns degrees counterclockwise; Android's
    // rotation convention (and this app's RotatedBox usage) is clockwise
    // degrees needed to display the frame correctly, hence the negation.
    double ccwDegrees = av_display_rotation_get(display_matrix);
    if (std::isnan(ccwDegrees)) return -1;
    return ((int)std::lround(-ccwDegrees) % 360 + 360) % 360;
}

void FFmpegPlayer::notifyEvent(const char* eventName, double positionMs, double durationMs, int width, int height, const char* errorMsg, int rotationDegrees) {
    JNIEnv* env = getJniEnv();
    if (!env || !plugin_instance_ref) return;

    ensureJniCache(env);
    ensureEventMethodCache(env);
    if (!hashmap_class || !on_event_method) return;

    jobject map = env->NewObject(hashmap_class, hashmap_init);

    jstring eventKey = env->NewStringUTF("event");
    jstring eventVal = env->NewStringUTF(eventName);
    env->CallObjectMethod(map, hashmap_put, eventKey, eventVal);
    env->DeleteLocalRef(eventKey);
    env->DeleteLocalRef(eventVal);

    // This was accepted as a parameter but never actually written into the
    // map below -- every "timeChanged" event therefore carried no
    // positionMs at all, so the Dart side's map['positionMs'] read always
    // fell back to its `?? 0` default. That silently reset the reported
    // playback position to zero on every single periodic update, which is
    // why the seekbar never appeared to move / always read back at 0.
    if (positionMs > 0 || durationMs > 0) {
        jstring posKey = env->NewStringUTF("positionMs");
        jobject posVal = env->NewObject(double_class, double_init, positionMs);
        env->CallObjectMethod(map, hashmap_put, posKey, posVal);
        env->DeleteLocalRef(posKey);
        env->DeleteLocalRef(posVal);
    }

    if (durationMs > 0) {
        jstring durKey = env->NewStringUTF("durationMs");
        jobject durVal = env->NewObject(double_class, double_init, durationMs);
        env->CallObjectMethod(map, hashmap_put, durKey, durVal);
        env->DeleteLocalRef(durKey);
        env->DeleteLocalRef(durVal);
    }
    
    if (width > 0 && height > 0) {
        jstring wKey = env->NewStringUTF("width");
        jstring hKey = env->NewStringUTF("height");
        jobject wVal = env->NewObject(integer_class, integer_init, width);
        jobject hVal = env->NewObject(integer_class, integer_init, height);
        env->CallObjectMethod(map, hashmap_put, wKey, wVal);
        env->CallObjectMethod(map, hashmap_put, hKey, hVal);
        env->DeleteLocalRef(wKey); env->DeleteLocalRef(hKey);
        env->DeleteLocalRef(wVal); env->DeleteLocalRef(hVal);
    }

    if (errorMsg) {
        jstring errKey = env->NewStringUTF("message");
        jstring errVal = env->NewStringUTF(errorMsg);
        env->CallObjectMethod(map, hashmap_put, errKey, errVal);
        env->DeleteLocalRef(errKey);
        env->DeleteLocalRef(errVal);
    }

    if (rotationDegrees >= 0) {
        jstring rotKey = env->NewStringUTF("rotationDegrees");
        jobject rotVal = env->NewObject(integer_class, integer_init, rotationDegrees);
        env->CallObjectMethod(map, hashmap_put, rotKey, rotVal);
        env->DeleteLocalRef(rotKey);
        env->DeleteLocalRef(rotVal);
    }

    env->CallVoidMethod(plugin_instance_ref, on_event_method, map);
    env->DeleteLocalRef(map);
}

int FFmpegPlayer::readPacketCallback(void* opaque, uint8_t* buf, int buf_size) {
    FFmpegPlayer* player = static_cast<FFmpegPlayer*>(opaque);
    if (player->media_fd < 0) return AVERROR_EOF;
    int ret = read(player->media_fd, buf, buf_size);
    return ret > 0 ? ret : AVERROR_EOF;
}

int64_t FFmpegPlayer::seekCallback(void* opaque, int64_t offset, int whence) {
    FFmpegPlayer* player = static_cast<FFmpegPlayer*>(opaque);
    if (player->media_fd < 0) return -1;
    if (whence == AVSEEK_SIZE) return player->media_size;
    return lseek(player->media_fd, offset, whence);
}

void FFmpegPlayer::setDataSource(int fd, bool autoPlay) {
    stop();
    
    media_fd = dup(fd);
    struct stat st;
    if (fstat(media_fd, &st) == 0) {
        media_size = st.st_size;
    }

    stop_requested = false;
    is_playing = autoPlay;
    audio_clock = 0.0;
    audio_chunk_end_pts = 0.0;
    video_clock = 0.0;
    seek_requested = false;
    input_eof = false;

    // Fresh counters for the new source. No fps_window_reset_requested
    // needed here (unlike after a seek) -- video_thread is a brand new
    // thread below, so its own local fps-window variables start clean by
    // construction.
    measured_fps = 0.0;
    frames_rendered_total = 0;
    frames_decoded_total = 0;
    frame_notify_count = 0;

    demux_thread = std::thread(&FFmpegPlayer::demuxThreadFunc, this);
}

void FFmpegPlayer::play() {
    if (!is_playing) {
        // Synchronize on resume: clear stale audio buffer and align audio clock 
        // to the exact video frame currently on screen.
        std::lock_guard<std::mutex> lock(audio_buf_mutex);
        audio_buffer.clear();
        double current_v_clock = video_clock.load();
        if (current_v_clock > 0) {
            audio_clock = current_v_clock;
            audio_chunk_end_pts = current_v_clock;
        }
    }
    is_playing = true;
    if (input_eof.load()) {
        seekTo(0);
    }
    double durationMs = format_ctx ? (double)format_ctx->duration / AV_TIME_BASE * 1000 : 0;
    notifyEvent("playing", video_clock.load() * 1000, durationMs);
}
void FFmpegPlayer::pause() { is_playing = false; notifyEvent("paused"); }

void FFmpegPlayer::stop() {
    stop_requested = true;
    is_playing = false;

    // 1. Stop audio callbacks BEFORE deleting resources to prevent SIGSEGV
    //
    // requestStop() is asynchronous -- it schedules the stop but does not
    // itself guarantee onAudioReady() won't be invoked again before the
    // underlying stream actually finishes stopping. On this app's "Legacy"
    // AAudio path (used on devices/OS builds without MMAP support -- see
    // the "got Legacy" log line), close() has been observed to return while
    // the internal AudioTrack callback thread is still mid-callback, which
    // then races the close/free below and crashes inside
    // oboe::AudioStreamAAudio::callOnAudioReady with a SIGSEGV -- this is a
    // known class of Oboe/AAudio teardown race (google/oboe#953, #1484),
    // not something unique to this app's code. waitForStateChange() blocks
    // (bounded by kAudioStreamStopTimeoutNanos) until AAudio itself confirms
    // the stream has actually reached Stopped before close() runs, closing
    // the race window close()/stop() alone left open. This is a mitigation,
    // not an absolute guarantee -- some OEM audio HALs have their own races
    // further down the stack that no amount of waiting here can fix.
    if (audio_stream) {
        oboe::StreamState currentState = audio_stream->getState();
        audio_stream->requestStop();
        oboe::StreamState nextState = currentState;
        oboe::Result waitResult = oboe::Result::OK;
        // A loop, not one waitForStateChange() call: requestStop() usually
        // passes through an intermediate Stopping state on the way to
        // Stopped, and waitForStateChange() only guarantees the state is
        // *different* from what's passed in -- a single call can return as
        // soon as Started -> Stopping happens, before the stream has
        // actually stopped. Bounded by kAudioStreamStopTimeoutNanos per
        // iteration; a timeout (or the stream going Closed/Disconnected
        // instead) breaks out rather than blocking indefinitely.
        while (waitResult == oboe::Result::OK &&
               nextState != oboe::StreamState::Stopped &&
               nextState != oboe::StreamState::Closed &&
               nextState != oboe::StreamState::Disconnected) {
            waitResult = audio_stream->waitForStateChange(currentState, &nextState, kAudioStreamStopTimeoutNanos);
            currentState = nextState;
        }
        audio_stream->close();
        audio_stream.reset();
    }

    // 2. Unblock decoding threads
    video_queue_cond.notify_all();
    audio_queue_cond.notify_all();
    
    if (demux_thread.joinable()) demux_thread.join();
    if (video_thread.joinable()) video_thread.join();
    if (audio_thread.joinable()) audio_thread.join();

    // 3. Safe cleanup
    //
    // format_ctx/video_codec_ctx/audio_codec_ctx/io_ctx are freed under
    // native_state_mutex -- see that field's comment in the header --
    // since getDiagnosticsSnapshot() can be called from a completely
    // unrelated thread at any time, including right now, with no join() or
    // other happens-before relationship to this function to rely on
    // instead.
    {
        std::lock_guard<std::mutex> lock(native_state_mutex);
        if (video_codec_ctx) { avcodec_free_context(&video_codec_ctx); video_codec_ctx = nullptr; }
        if (audio_codec_ctx) { avcodec_free_context(&audio_codec_ctx); audio_codec_ctx = nullptr; }
        if (format_ctx) { avformat_close_input(&format_ctx); format_ctx = nullptr; }
        if (io_ctx) { av_freep(&io_ctx->buffer); avio_context_free(&io_ctx); io_ctx = nullptr; }
    }
    if (swr_ctx) { swr_free(&swr_ctx); swr_ctx = nullptr; }
    {
        std::lock_guard<std::mutex> lock(audio_buf_mutex);
        if (speed_swr_ctx) { swr_free(&speed_swr_ctx); speed_swr_ctx = nullptr; }
    }
    if (sws_ctx) { sws_freeContext(sws_ctx); sws_ctx = nullptr; }

    std::lock_guard<std::mutex> l1(video_queue_mutex);
    while(!video_queue.empty()) { av_packet_free(&video_queue.front()); video_queue.pop(); }
    
    std::lock_guard<std::mutex> l2(audio_queue_mutex);
    while(!audio_queue.empty()) { av_packet_free(&audio_queue.front()); audio_queue.pop(); }

    std::lock_guard<std::mutex> l3(audio_buf_mutex);
    audio_buffer.clear();

    if (media_fd >= 0) { close(media_fd); media_fd = -1; }
}

void FFmpegPlayer::seekTo(int64_t positionMs) {
    // Deliberately does NOT touch format_ctx here: this can be called from
    // whatever thread handles the Flutter method channel, which runs
    // concurrently with demux_thread's own av_read_frame() calls on the
    // same format_ctx -- calling av_seek_frame() directly from here was a
    // data race (this is the root cause of "the seekbar doesn't work":
    // the seek could be silently lost, corrupted, or interleaved with an
    // in-flight read in undefined ways). demuxThreadFunc picks this up
    // and performs the actual seek itself, since it's the only thread
    // that ever touches format_ctx.
    if (!format_ctx) return;
    seek_target_ms = positionMs;
    seek_requested = true;
}

// Only ever called from demux_thread, at the top of its own loop -- see
// seekTo()'s comment for why this can't safely run on the caller's thread.
void FFmpegPlayer::performPendingSeek() {
    if (!seek_requested.exchange(false)) return;

    int64_t targetMs = seek_target_ms.load();
    int64_t target = av_rescale_q(targetMs, AVRational{1, 1000}, AV_TIME_BASE_Q);
    av_seek_frame(format_ctx, -1, target, AVSEEK_FLAG_BACKWARD);

    {
        std::lock_guard<std::mutex> l1(video_queue_mutex);
        while (!video_queue.empty()) { av_packet_free(&video_queue.front()); video_queue.pop(); }
    }
    {
        std::lock_guard<std::mutex> l2(audio_queue_mutex);
        while (!audio_queue.empty()) { av_packet_free(&audio_queue.front()); audio_queue.pop(); }
    }
    {
        std::lock_guard<std::mutex> l3(audio_buf_mutex);
        audio_buffer.clear();
    }

    // Without this, the decoders keep whatever reference-frame/reorder
    // state they had built up right before the jump, which is now
    // inconsistent with the post-seek bitstream position -- this is what
    // was silently breaking looping too: seekTo(0) at EOF landed back on
    // the exact same unflushed decoders, which then failed to produce
    // usable frames from the restarted stream.
    //
    // This used to call avcodec_flush_buffers() directly here, with no
    // synchronization against video_thread/audio_thread -- but those
    // threads can be mid-avcodec_send_packet()/avcodec_receive_frame() on
    // the exact same AVCodecContext at this exact moment (they only wait
    // on packet availability, not on the demux thread doing anything).
    // FFmpeg does not support flushing a codec context concurrently with
    // decode calls on it from another thread: the flush resets internal
    // state (reference frames, reorder buffers) out from under a decode
    // call that's actively reading it, corrupting it. That's what was
    // crashing with a SIGSEGV inside avcodec_send_packet whenever the
    // seekbar was used. Taking the same mutex the decode threads hold
    // around their codec calls (see video/audioDecodeThreadFunc) makes
    // the flush wait for any in-flight decode call to finish first.
    {
        std::lock_guard<std::mutex> lock(video_codec_mutex);
        if (video_codec_ctx) avcodec_flush_buffers(video_codec_ctx);
    }
    {
        std::lock_guard<std::mutex> lock(audio_codec_mutex);
        if (audio_codec_ctx) avcodec_flush_buffers(audio_codec_ctx);
    }

    audio_clock = targetMs / 1000.0;
    audio_chunk_end_pts = targetMs / 1000.0;
    video_clock = targetMs / 1000.0;
    // A seek (whether user-initiated or a loop restart) means we're no
    // longer at end-of-stream, so audio_clock is trustworthy again -- see
    // videoDecodeThreadFunc's A/V-sync block.
    input_eof = false;
    // Same idea for the measured-fps window: the queue-flush/refill stall
    // this seek just caused isn't representative of steady-state render
    // rate, so have video_thread restart its window from here rather than
    // let the stall dilute whatever window it was mid-way through.
    fps_window_reset_requested = true;
    notifyEvent("timeChanged", (double)targetMs, (double)format_ctx->duration / AV_TIME_BASE * 1000);
}

void FFmpegPlayer::setVolume(int v) { volume_multiplier = v / 100.0f; }
void FFmpegPlayer::setPlaybackSpeed(float speed) {
    if (speed <= 0.0f) speed = 1.0f;
    playback_speed = speed;

    // This runs on whichever thread called setRate() (JNI -> the Kotlin
    // caller's thread), never the audio thread -- see speed_swr_ctx's
    // comment in the header for why that matters. At speed == 1.0f,
    // onAudioReady() takes its 1:1 fast path and never touches
    // speed_swr_ctx at all, so there's nothing to (re)configure; just
    // release whatever's cached from a previous non-1x speed instead.
    SwrContext* newCtx = nullptr;
    if (speed != 1.0f) {
        AVChannelLayout layout = AV_CHANNEL_LAYOUT_STEREO;
        // Telling swr the input is at kOutputSampleRate * speed while the
        // output stays at the fixed device rate kOutputSampleRate is what
        // makes this a *speed* change rather than a real resample: for
        // speed > 1, swr believes it's converting down from a higher rate,
        // so it consumes source frames faster than they're played back
        // (pitch rises); for speed < 1, the reverse. This is the same
        // "consume source faster/slower than 1:1" trick the old linear
        // interpolation used (srcPos += speed per output sample) -- pitch
        // still shifts with rate, just via swr's actual anti-aliased
        // resampler instead of a hand-rolled per-sample lerp.
        int declaredInRate = (int)(kOutputSampleRate * (double)speed + 0.5);
        swr_alloc_set_opts2(&newCtx,
            &layout, AV_SAMPLE_FMT_FLT, kOutputSampleRate,
            &layout, AV_SAMPLE_FMT_FLT, declaredInRate,
            0, nullptr);
        if (newCtx && swr_init(newCtx) < 0) {
            swr_free(&newCtx);
            newCtx = nullptr;
        }
    }

    std::lock_guard<std::mutex> lock(audio_buf_mutex);
    if (speed_swr_ctx) swr_free(&speed_swr_ctx);
    speed_swr_ctx = newCtx;
}
void FFmpegPlayer::setLooping(bool loop) { looping = loop; }

jobject FFmpegPlayer::getDiagnosticsSnapshot(JNIEnv* env) {
    ensureJniCache(env);
    if (!hashmap_class) return nullptr;
    jobject map = env->NewObject(hashmap_class, hashmap_init);

    auto putString = [&](const char* key, const char* value) {
        if (!value) return;
        jstring k = env->NewStringUTF(key);
        jstring v = env->NewStringUTF(value);
        env->CallObjectMethod(map, hashmap_put, k, v);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(v);
    };
    auto putInt = [&](const char* key, int value) {
        jstring k = env->NewStringUTF(key);
        jobject v = env->NewObject(integer_class, integer_init, value);
        env->CallObjectMethod(map, hashmap_put, k, v);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(v);
    };
    auto putLong = [&](const char* key, int64_t value) {
        jstring k = env->NewStringUTF(key);
        jobject v = env->NewObject(long_class, long_init, (jlong)value);
        env->CallObjectMethod(map, hashmap_put, k, v);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(v);
    };
    auto putDouble = [&](const char* key, double value) {
        jstring k = env->NewStringUTF(key);
        jobject v = env->NewObject(double_class, double_init, value);
        env->CallObjectMethod(map, hashmap_put, k, v);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(v);
    };

    // Live engine counters are independent atomics written only by
    // video_thread (see their declarations in the header) -- no relation
    // to format_ctx/codec-context lifetime, so these are safe to read
    // outside native_state_mutex.
    putDouble("measuredFps", measured_fps.load());
    putLong("framesDecoded", (int64_t)frames_decoded_total.load());
    putLong("framesRendered", (int64_t)frames_rendered_total.load());

    // Real container/codec info, read straight from FFmpeg's own
    // AVFormatContext/AVCodecContext rather than a separate
    // MediaExtractor/MediaMetadataRetriever pass over the same file --
    // this is what's actually driving playback, so it's authoritative for
    // any container FFmpeg can open at all (including ones the platform
    // extractor doesn't recognize).
    //
    // The whole block has to stay inside native_state_mutex, not just a
    // null-check up front: format_ctx (and video_codec_ctx/audio_codec_ctx)
    // can be concurrently freed by a stop() running on another thread the
    // instant after a bare null-check released the lock, which is exactly
    // the use-after-free native_state_mutex exists to rule out -- see its
    // comment in the header.
    {
        std::lock_guard<std::mutex> lock(native_state_mutex);
        if (format_ctx) {
            if (format_ctx->iformat) {
                putString("containerFormat", format_ctx->iformat->long_name ? format_ctx->iformat->long_name : format_ctx->iformat->name);
            }
            if (format_ctx->bit_rate > 0) {
                putLong("containerBitrate", format_ctx->bit_rate);
            }

            if (video_stream_idx >= 0 && video_codec_ctx) {
                putString("videoCodec", avcodec_get_name(video_codec_ctx->codec_id));
                if (video_codec_ctx->width > 0 && video_codec_ctx->height > 0) {
                    putInt("videoWidth", video_codec_ctx->width);
                    putInt("videoHeight", video_codec_ctx->height);
                }
                int64_t videoBitrate = video_codec_ctx->bit_rate > 0
                    ? video_codec_ctx->bit_rate
                    : format_ctx->streams[video_stream_idx]->codecpar->bit_rate;
                if (videoBitrate > 0) putLong("videoBitrate", videoBitrate);

                AVRational frameRate = format_ctx->streams[video_stream_idx]->avg_frame_rate;
                if (frameRate.num > 0 && frameRate.den > 0) putDouble("frameRate", av_q2d(frameRate));

                // MP4 (and similar) muxers store rotation as a display
                // transformation matrix in the stream's side data -- the
                // same "tkhd" rotation Android's MediaRecorder writes via
                // setOrientationHint(). See detectRotationDegrees()'s doc
                // for why this (and the "playing" event, which is the path
                // actually driving playback) reads it straight from here
                // rather than through a second, independent
                // MediaMetadataRetriever pass.
                int rotation = detectRotationDegrees(format_ctx, video_stream_idx);
                if (rotation >= 0) putInt("rotationDegrees", rotation);
            }

            if (audio_stream_idx >= 0 && audio_codec_ctx) {
                putString("audioCodec", avcodec_get_name(audio_codec_ctx->codec_id));
                if (audio_codec_ctx->sample_rate > 0) putInt("audioSampleRate", audio_codec_ctx->sample_rate);
                if (audio_codec_ctx->ch_layout.nb_channels > 0) putInt("audioChannels", audio_codec_ctx->ch_layout.nb_channels);
                int64_t audioBitrate = audio_codec_ctx->bit_rate > 0
                    ? audio_codec_ctx->bit_rate
                    : format_ctx->streams[audio_stream_idx]->codecpar->bit_rate;
                if (audioBitrate > 0) putLong("audioBitrate", audioBitrate);
            }
        }
    }

    return map;
}

void FFmpegPlayer::demuxThreadFunc() {
    notifyEvent("opening");

    unsigned char* io_buffer = (unsigned char*)av_malloc(kIoBufferSize);
    {
        // See native_state_mutex's comment in the header: this only needs
        // to cover the pointer assignments themselves, not the blocking
        // avformat_open_input/avformat_find_stream_info calls below -- a
        // getDiagnosticsSnapshot() call landing in that narrow window would
        // just see format_ctx before its streams are fully parsed (fields
        // it reads default to "unknown" via its own null/zero checks), not
        // a freed pointer, which is the only thing this lock has to
        // prevent.
        std::lock_guard<std::mutex> lock(native_state_mutex);
        io_ctx = avio_alloc_context(io_buffer, kIoBufferSize, 0, this, readPacketCallback, NULL, seekCallback);
        format_ctx = avformat_alloc_context();
    }
    format_ctx->pb = io_ctx;

    if (avformat_open_input(&format_ctx, NULL, NULL, NULL) != 0) {
        notifyEvent("error", 0, 0, 0, 0, "Failed to open media file");
        return;
    }
    
    if (avformat_find_stream_info(format_ctx, NULL) < 0) {
        notifyEvent("error", 0, 0, 0, 0, "Failed to find stream info");
        return;
    }

    video_stream_idx = av_find_best_stream(format_ctx, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    audio_stream_idx = av_find_best_stream(format_ctx, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);

    if (video_stream_idx >= 0) {
        AVCodecParameters* codecpar = format_ctx->streams[video_stream_idx]->codecpar;
        const AVCodec* codec = avcodec_find_decoder(codecpar->codec_id);
        if (codec) {
            {
                std::lock_guard<std::mutex> lock(native_state_mutex);
                video_codec_ctx = avcodec_alloc_context3(codec);
            }
            avcodec_parameters_to_context(video_codec_ctx, codecpar);

            // Explicitly request frame+slice multi-threaded decode. This
            // was previously left at whatever avcodec_alloc_context3()
            // zero-initializes (thread_count = 0, "auto"), which some
            // vendored libavcodec builds interpret conservatively -- for
            // heavy content (e.g. 3840x2160 VP9) single-threaded decode
            // alone can be slower than real-time, which starves the whole
            // pipeline (see the admission-control comment below) and shows
            // up as the video freezing/slowing down rather than just
            // dropping the occasional frame. hardware_concurrency() is 0 on
            // a small number of platforms if it can't detect core count;
            // fall back to 4 rather than passing 0 through (0 here means
            // "single-threaded", not "auto", once thread_count is set
            // explicitly).
            unsigned hw_concurrency = std::thread::hardware_concurrency();
            video_codec_ctx->thread_count = hw_concurrency > 0 ? (int)hw_concurrency : 4;
            video_codec_ctx->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;

            avcodec_open2(video_codec_ctx, codec, NULL);
            
            // Set window geometry on the native window so ANativeWindow_lock works properly
            if (native_window && codecpar->width > 0 && codecpar->height > 0) {
                ANativeWindow_setBuffersGeometry(native_window, codecpar->width, codecpar->height, WINDOW_FORMAT_RGBA_8888);
            }

            video_thread = std::thread(&FFmpegPlayer::videoDecodeThreadFunc, this);
            notifyEvent("playing", 0, (double)format_ctx->duration / AV_TIME_BASE * 1000, codecpar->width, codecpar->height,
                        nullptr, detectRotationDegrees(format_ctx, video_stream_idx));
        }
    }
    
    if (audio_stream_idx >= 0) {
        AVCodecParameters* codecpar = format_ctx->streams[audio_stream_idx]->codecpar;
        const AVCodec* codec = avcodec_find_decoder(codecpar->codec_id);
        if (codec) {
            {
                std::lock_guard<std::mutex> lock(native_state_mutex);
                audio_codec_ctx = avcodec_alloc_context3(codec);
            }
            avcodec_parameters_to_context(audio_codec_ctx, codecpar);
            avcodec_open2(audio_codec_ctx, codec, NULL);

            // Modern FFmpeg 7/8 Channel Layout setup
            AVChannelLayout out_ch_layout = AV_CHANNEL_LAYOUT_STEREO;
            int sample_rate = audio_codec_ctx->sample_rate > 0 ? audio_codec_ctx->sample_rate : kOutputSampleRate;

            swr_alloc_set_opts2(&swr_ctx,
                &out_ch_layout, AV_SAMPLE_FMT_FLT, kOutputSampleRate,
                &audio_codec_ctx->ch_layout, audio_codec_ctx->sample_fmt, sample_rate,
                0, NULL);
            swr_init(swr_ctx);

            oboe::AudioStreamBuilder builder;
            builder.setDirection(oboe::Direction::Output)
                   ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
                   ->setFormat(oboe::AudioFormat::Float)
                   ->setChannelCount(kOutputChannels)
                   ->setSampleRate(kOutputSampleRate)
                   ->setDataCallback(this);
            builder.openStream(audio_stream);
            audio_stream->requestStart();

            audio_thread = std::thread(&FFmpegPlayer::audioDecodeThreadFunc, this);
        }
    }

    AVPacket* packet = av_packet_alloc();
    while (!stop_requested) {
        performPendingSeek();

        if (!is_playing) { 
            std::this_thread::sleep_for(std::chrono::milliseconds(kIdlePollIntervalMs)); 
            continue; 
        }

        // Sitting at true end-of-stream (non-looping): nothing left to
        // read until a seek lands, and performPendingSeek() above already
        // clears input_eof the moment one does. Skip straight to idling
        // instead of re-running av_read_frame every iteration for no
        // reason.
        if (input_eof.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(kEofIdlePollIntervalMs));
            continue;
        }

        // Pause demuxing once BOTH queues have reached their target depth,
        // with a hard per-queue backstop ceiling (kQueueBackstopMultiplier x
        // the target) so a genuinely stalled stream still can't grow
        // unbounded.
        //
        // An earlier version of this paused as soon as EITHER queue reached
        // its target, specifically to stop video_queue from growing
        // unbounded while video_thread paced itself 1:1 with real time even
        // when badly behind. videoDecodeThreadFunc no longer does that -- it
        // drops frames instead of pacing through a large backlog (see
        // kAvSyncFrameDropThresholdSec there) -- but the either-full
        // condition has a different failure mode on CPU-bound heavy content
        // (e.g. 3840x2160 VP9): if *decoding* itself (not presentation
        // pacing) can't keep up with real time, video_queue sits at its
        // target continuously, since it refills exactly as fast as the slow
        // decoder drains it. Pausing on that alone blocks new audio packets
        // from being read too, even though audio_queue has room and
        // audio_thread is decoding cheaply and quickly -- audio_buffer runs
        // dry waiting on packets that demuxing refuses to fetch, which is
        // heard as stuttering/silence and, combined with the video itself
        // barely advancing, presents as the whole player freezing. Requiring
        // both queues to be full before pausing lets audio keep being fed
        // independently of how slowly video is being consumed; the backstop
        // ceiling below is what still bounds video_queue's own growth in
        // that situation, rather than the audio queue's fullness.
        size_t video_backstop = kMaxQueuedVideoPackets * kQueueBackstopMultiplier;
        size_t audio_backstop = kMaxQueuedAudioPackets * kQueueBackstopMultiplier;
        bool video_full = (video_stream_idx >= 0) && (video_queue.size() > kMaxQueuedVideoPackets);
        bool audio_full = (audio_stream_idx >= 0) && (audio_queue.size() > kMaxQueuedAudioPackets);
        bool video_at_backstop = (video_stream_idx >= 0) && (video_queue.size() > video_backstop);
        bool audio_at_backstop = (audio_stream_idx >= 0) && (audio_queue.size() > audio_backstop);

        if ((video_full && audio_full) || video_at_backstop || audio_at_backstop) {
            std::this_thread::sleep_for(std::chrono::milliseconds(kIdlePollIntervalMs));
            continue;
        }

        if (av_read_frame(format_ctx, packet) >= 0) {
            if (packet->stream_index == video_stream_idx) {
                std::lock_guard<std::mutex> lock(video_queue_mutex);
                video_queue.push(av_packet_clone(packet));
                video_queue_cond.notify_one();
            } else if (packet->stream_index == audio_stream_idx) {
                std::lock_guard<std::mutex> lock(audio_queue_mutex);
                audio_queue.push(av_packet_clone(packet));
                audio_queue_cond.notify_one();
            }
            av_packet_unref(packet);
        } else {
            // Flip this *before* waiting for the queues to drain below,
            // not after: videoDecodeThreadFunc's A/V-sync block needs to
            // stop trusting audio_clock (which is about to freeze -- no
            // more audio packets are coming either) right away. Setting
            // it only after the drain wait finishes meant the video
            // thread spent that entire wait still chasing a frozen
            // audio_clock exactly as before this existed -- reproducing
            // the near-end slowdown this flag was added to fix, just
            // relocated into this wait instead of removed. Looping also
            // needs it set here for the same reason (the queues below
            // still have to drain before the seekTo(0) restart); it gets
            // cleared again the moment that seek actually lands, in
            // performPendingSeek().
            input_eof = true;

            // For a very short clip, av_read_frame can read the *entire*
            // file and hit EOF within milliseconds -- far faster than the
            // decode threads render it back out at real, paced speed.
            // Restarting (loop) or declaring the end right here, before
            // those threads have actually drained what's already queued,
            // used to clear/abandon frames that hadn't played yet: for
            // looping, that repeatedly wiped the whole clip out from
            // under the decode threads on every lap, leaving playback
            // stuck showing a single frame; for a one-shot clip, it fired
            // "endReached" (which the Dart side treats as playback
            // having reached the very end) well before what was on
            // screen had actually finished. Waiting here first fixes both.
            waitForQueuesDrained();
            if (stop_requested) break;

            if (looping) { 
                seekTo(0); 
            } else {
                // No more packets will ever arrive for either stream from
                // here on. This only runs once per real end: the moment
                // input_eof (set above) is true, the top-of-loop check
                // skips straight past av_read_frame on every later
                // iteration, so this branch can't be re-entered until a
                // seek clears that flag again.
                notifyEvent("endReached");
                // Deliberately does not break/return here: seekTo() (the
                // user dragging the seekbar, including back to the very
                // start) only ever gets *acted on* by this thread's own
                // performPendingSeek() call at the top of this loop --
                // exiting the thread here, as this used to do, left any
                // later seek (or play(), which now also seeks to 0 -- see
                // play()) permanently stranded with nothing left alive to
                // service it. Falling through and looping back around
                // just idles (see the input_eof check above) until either
                // a seek arrives or stop() tears this thread down.
            }
        }
    }
    av_packet_free(&packet);
}

// Waits until both decode queues have been fully drained by their
// consumer threads (i.e. video/audioDecodeThreadFunc have popped
// everything already read), plus a short grace period for whichever
// packet each thread most recently popped to finish its own paced
// render/sleep -- queue-empty alone doesn't guarantee that. Capped so a
// stuck decode thread can't hang this one forever.
void FFmpegPlayer::waitForQueuesDrained() {
    for (int i = 0; i < kDrainMaxIterations && !stop_requested; i++) {
        bool videoEmpty, audioEmpty;
        {
            std::lock_guard<std::mutex> l(video_queue_mutex);
            videoEmpty = video_queue.empty();
        }
        {
            std::lock_guard<std::mutex> l(audio_queue_mutex);
            audioEmpty = audio_queue.empty();
        }
        if (videoEmpty && audioEmpty) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(kDrainPollIntervalMs));
    }
    if (!stop_requested) {
        std::this_thread::sleep_for(std::chrono::milliseconds(kDrainGraceMs));
    }
}

void FFmpegPlayer::videoDecodeThreadFunc() {
    AVFrame* frame = av_frame_alloc();

    // Rolling actual-render-rate measurement (see measured_fps's comment in
    // the header). av_gettime_relative() is a monotonic clock with an
    // unspecified epoch -- only meaningful for deltas within this process,
    // which is all this uses it for.
    double fps_window_start_sec = av_gettime_relative() / 1000000.0;
    int fps_window_frame_count = 0;

    // Presentation deadline for frame-timer-style pacing, kept across loop
    // iterations (thread-local, not shared -- this thread is the sole owner
    // of its own pacing schedule). Rather than computing a fresh delay and
    // sleep_for()'ing it every single frame -- which lets each frame's own
    // scheduling error (OS scheduler granularity, mutex wait, sws_scale
    // time, etc.) go uncorrected until the *next* frame's audio_clock diff
    // happens to catch it -- this thread now advances an absolute wall-clock
    // deadline once per frame and sleeps *to* it, so an individual frame
    // arriving a few ms late doesn't push every subsequent frame later too.
    // Reset to "no deadline yet" (have_deadline=false) any time there's been
    // a gap that makes the old schedule meaningless: paused, seeked, or a
    // frame just got dropped.
    auto next_frame_deadline = std::chrono::steady_clock::now();
    bool have_deadline = false;

    while (!stop_requested) {
        if (fps_window_reset_requested.exchange(false)) {
            fps_window_start_sec = av_gettime_relative() / 1000000.0;
            fps_window_frame_count = 0;
            have_deadline = false;
            // A seek invalidates any hurry-up decision made about the
            // pre-seek position just as much as it invalidates the pacing
            // deadline above -- start the new position at full decode
            // quality and let the sync block below re-enter hurry-up on its
            // own if the new position turns out to be behind too.
            if (hurry_up_active) {
                std::lock_guard<std::mutex> codecLock(video_codec_mutex);
                if (video_codec_ctx) video_codec_ctx->skip_frame = AVDISCARD_DEFAULT;
                hurry_up_active = false;
            }
        }

        // Paused: don't pop and decode any *new* packet. Without this check,
        // this thread had no notion of "paused" at all -- it kept draining
        // whatever was already queued (up to kMaxQueuedVideoPackets, roughly
        // a second of content), advancing video_clock and firing
        // notifyEvent("timeChanged") the whole time, with only the actual
        // on-screen draw skipped. That's what made the reported position
        // keep creeping forward for a moment after pause instead of freezing
        // immediately -- see the matching check inside the decode loop below
        // for the packet that was already in flight when pause() landed.
        if (!is_playing.load()) {
            have_deadline = false;
            if (hurry_up_active) {
                std::lock_guard<std::mutex> codecLock(video_codec_mutex);
                if (video_codec_ctx) video_codec_ctx->skip_frame = AVDISCARD_DEFAULT;
                hurry_up_active = false;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(kIdlePollIntervalMs));
            continue;
        }

        AVPacket* pkt = nullptr;
        {
            std::unique_lock<std::mutex> lock(video_queue_mutex);
            video_queue_cond.wait(lock, [this] { return !video_queue.empty() || stop_requested; });
            if (stop_requested) break;
            pkt = video_queue.front();
            video_queue.pop();
        }

        int sendRet;
        {
            std::lock_guard<std::mutex> codecLock(video_codec_mutex);
            sendRet = avcodec_send_packet(video_codec_ctx, pkt);
        }
        if (sendRet == 0) {
            while (true) {
                int recvRet;
                {
                    std::lock_guard<std::mutex> codecLock(video_codec_mutex);
                    recvRet = avcodec_receive_frame(video_codec_ctx, frame);
                }
                if (recvRet != 0) break;

                // Counted here rather than after the render block below:
                // this is "the decoder produced a frame," full stop,
                // independent of whether it's actually drawn (native_window
                // can be null briefly during teardown, or is_playing can be
                // false if paused mid-decode) -- see frames_rendered_total
                // for the "did we actually draw it" counterpart.
                frames_decoded_total.fetch_add(1, std::memory_order_relaxed);

                // Paused mid-packet: this packet was already popped (and
                // possibly already mid-decode) before pause() landed. Still
                // drain the decoder's output for it -- avcodec_receive_frame
                // has to be called to completion or the next
                // avcodec_send_packet can return EAGAIN -- but don't advance
                // video_clock, run sync pacing, render, or notify Dart from
                // it. That keeps the reported/paced position from moving at
                // all once paused, rather than only for the packets that
                // hadn't been popped yet.
                if (!is_playing.load()) {
                    continue;
                }

                double pts;
                if (frame->best_effort_timestamp != AV_NOPTS_VALUE) {
                    pts = frame->best_effort_timestamp * av_q2d(format_ctx->streams[video_stream_idx]->time_base);
                } else {
                    // Malformed/unusual stream with no usable timestamp for
                    // this frame -- best_effort_timestamp's sentinel is
                    // INT64_MIN, so multiplying it by time_base would feed a
                    // huge garbage value into video_clock and the sync math
                    // below. Hold at the last known position instead.
                    pts = video_clock.load();
                }
                video_clock = pts;

                // A/V Synchronization
                //
                // audio_clock reflects the real-time audio consumer's
                // position (see onAudioReady) -- it does NOT track
                // wall-clock time on its own between updates. Audio and
                // video tracks essentially never end at exactly the same
                // timestamp (encoder delay, differing track durations,
                // etc.), so on nearly every file the audio track's last
                // packet gets consumed first, audio_clock stops updating and
                // sits frozen from then on, while pts here keeps advancing
                // for the video frames still arriving. diff = pts -
                // audio_clock then grows without bound, and for however many
                // frames it takes to cross the 1.0s cap below, this was
                // sleeping for close to a full second per frame --
                // experienced as the video grinding almost to a halt for the
                // last stretch before it actually reaches the end.
                // input_eof (set once the demuxer truly has no more packets
                // coming for either stream) tells us audio_clock can no
                // longer be trusted, so we fall back to plain fps-based
                // pacing instead of chasing it.
                bool should_render = true;
                int sleepMs = 0;
                if (audio_stream_idx >= 0 && audio_clock > 0 && !input_eof.load()) {
                    double fps = av_q2d(format_ctx->streams[video_stream_idx]->avg_frame_rate);
                    double default_delay = (fps > 0) ? (1.0 / fps) : (kFallbackFrameDelayMs / 1000.0);
                    double delay = default_delay;

                    double diff = pts - audio_clock;

                    // Leave hurry-up decode mode as soon as we're back
                    // within kHurryUpExitDiffSec, regardless of which
                    // branch below diff ends up in -- e.g. after a severe
                    // backlog starts clearing, diff typically passes back
                    // through the "moderately behind" branches on its way
                    // to caught-up, and hurry-up needs to end there too,
                    // not only once diff swings all the way to "ahead".
                    if (hurry_up_active && diff > -kHurryUpExitDiffSec) {
                        std::lock_guard<std::mutex> codecLock(video_codec_mutex);
                        if (video_codec_ctx) video_codec_ctx->skip_frame = AVDISCARD_DEFAULT;
                        hurry_up_active = false;
                    }

                    if (diff > kAvSyncMinDiffSec && diff < kAvSyncMaxDiffSec) {
                        // Video is ahead: extend frame delay by at most +20%
                        double max_extra = default_delay * 0.2;
                        double extra = std::min(diff, max_extra);
                        delay += extra;
                    } else if (diff < -kAvSyncFrameDropThresholdSec) {
                        // Video is severely behind: drop this frame outright
                        // instead of presenting it. Rendering every
                        // backlogged frame at zero delay (the old behavior)
                        // still pays the full sws_scale + ANativeWindow
                        // lock/present cost per frame, so a real backlog
                        // took real wall-clock time to burn through, all of
                        // it rendered back-to-back -- that's what was
                        // visible as the video suddenly "speeding up," then
                        // settling back down once the backlog cleared. Not
                        // presenting the stale frame at all skips that cost,
                        // so the backlog clears faster and nothing is ever
                        // actually shown sped up.
                        should_render = false;
                        delay = 0.0;

                        // On top of not presenting: if we're this far
                        // behind, decoding itself may be the bottleneck
                        // (heavy content like 4K VP9 can decode slower than
                        // real time), not just presentation pacing -- so
                        // also ask the decoder to skip non-reference frames
                        // entirely (the same "hurry up" ffplay uses) to cut
                        // decode cost while catching up. Skipped frames
                        // never reach avcodec_receive_frame at all, so
                        // there's nothing further to drop for them.
                        if (!hurry_up_active) {
                            std::lock_guard<std::mutex> codecLock(video_codec_mutex);
                            if (video_codec_ctx) video_codec_ctx->skip_frame = AVDISCARD_NONREF;
                            hurry_up_active = true;
                        }
                    } else if (diff < -0.100) {
                        // Video is behind (>100ms but under the drop
                        // threshold): catch up by presenting immediately
                        // with no sleep, same as before -- just bounded now,
                        // since anything further behind is dropped above
                        // instead of piling into this branch.
                        delay = 0.0;
                    } else if (diff < -kAvSyncMinDiffSec) {
                        // Video is slightly behind (<100ms): shorten frame delay slightly
                        double max_sub = default_delay * 0.2;
                        double sub = std::min(-diff, max_sub);
                        delay = std::max(0.0, delay - sub);
                    }

                    sleepMs = (int)(delay * 1000.0 / playback_speed);
                } else {
                    double fps = av_q2d(format_ctx->streams[video_stream_idx]->avg_frame_rate);
                    sleepMs = (fps > 0) ? (int)(1000.0 / fps / playback_speed) : kFallbackFrameDelayMs;
                    // No audio_clock to compare against right now (no audio
                    // stream, or it's no longer trustworthy at EOF) -- there's
                    // nothing to "catch up" to, so don't leave decode stuck
                    // skipping non-reference frames.
                    if (hurry_up_active) {
                        std::lock_guard<std::mutex> codecLock(video_codec_mutex);
                        if (video_codec_ctx) video_codec_ctx->skip_frame = AVDISCARD_DEFAULT;
                        hurry_up_active = false;
                    }
                }

                if (!should_render) {
                    // Dropping: don't schedule a slot for this frame at all,
                    // and don't let the deadline fall further behind wall-
                    // clock reality while we're catching up.
                    next_frame_deadline = std::chrono::steady_clock::now();
                } else {
                    if (!have_deadline) {
                        next_frame_deadline = std::chrono::steady_clock::now();
                        have_deadline = true;
                    }
                    next_frame_deadline += std::chrono::microseconds((int64_t)(sleepMs * 1000));
                    auto now = std::chrono::steady_clock::now();
                    if (next_frame_deadline > now) {
                        std::this_thread::sleep_until(next_frame_deadline);
                    } else {
                        // Already past the computed deadline -- don't sleep
                        // (would just add more delay), and pull the deadline
                        // back to now so a single late frame doesn't leave
                        // every subsequent frame perpetually trying to catch
                        // up to a schedule that's already behind reality.
                        next_frame_deadline = now;
                    }
                }

                if (should_render && native_window && is_playing) {
                    ANativeWindow_Buffer windowBuffer;
                    if (ANativeWindow_lock(native_window, &windowBuffer, NULL) == 0) {
                        if (!sws_ctx) {
                            sws_ctx = sws_getContext(video_codec_ctx->width, video_codec_ctx->height, video_codec_ctx->pix_fmt,
                                                     windowBuffer.width, windowBuffer.height, AV_PIX_FMT_RGBA, 
                                                     SWS_BILINEAR, NULL, NULL, NULL);
                        }
                        uint8_t* dst[4] = { (uint8_t*)windowBuffer.bits, NULL, NULL, NULL };
                        int dstStride[4] = { windowBuffer.stride * 4, 0, 0, 0 };
                        sws_scale(sws_ctx, frame->data, frame->linesize, 0, video_codec_ctx->height, dst, dstStride);
                        ANativeWindow_unlockAndPost(native_window);

                        // measured_fps is the actual on-screen render rate,
                        // as opposed to frameRate (the container's declared
                        // avg_frame_rate) -- it's what a "stats for nerds"
                        // overlay actually wants, since it reflects real
                        // dropped-frame/pacing behavior rather than just
                        // what the file claims. Recomputed once per ~1s
                        // window rather than every frame so it reads as a
                        // stable rate instead of jittering with each
                        // individual frame's render time.
                        frames_rendered_total.fetch_add(1, std::memory_order_relaxed);
                        fps_window_frame_count++;
                        double now_sec = av_gettime_relative() / 1000000.0;
                        double window_elapsed = now_sec - fps_window_start_sec;
                        if (window_elapsed >= kFpsWindowSec) {
                            measured_fps = fps_window_frame_count / window_elapsed;
                            fps_window_start_sec = now_sec;
                            fps_window_frame_count = 0;
                        }
                    }
                }
                
                if (++frame_notify_count % kTimeChangedNotifyEveryNFrames == 0) {
                    notifyEvent("timeChanged", pts * 1000, (double)format_ctx->duration / AV_TIME_BASE * 1000);
                }
            }
        }
        av_packet_free(&pkt);
    }
    av_frame_free(&frame);
}

void FFmpegPlayer::audioDecodeThreadFunc() {
    AVFrame* frame = av_frame_alloc();
    while (!stop_requested) {
        // Paused: don't pop and decode any *new* packet -- mirrors the same
        // check in videoDecodeThreadFunc. Without it, this thread had no
        // notion of "paused" either: it kept draining whatever was already
        // queued into audio_buffer the whole time (bounded only by the 0.5s
        // backpressure cap below), which used to also keep dragging
        // audio_clock forward during a pause. audio_clock is no longer
        // written from this thread at all now (see the push block below),
        // so this check's remaining job is just to stop burning through the
        // queue while paused rather than to protect the clock.
        if (!is_playing.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(kIdlePollIntervalMs));
            continue;
        }

        // Backpressure: If audio_buffer already holds > 0.5s of audio, wait for onAudioReady to consume it.
        // This prevents audio_buffer from ballooning to 10+ seconds and breaking A/V sync.
        {
            std::unique_lock<std::mutex> lock(audio_buf_mutex);
            if (audio_buffer.size() / kOutputChannels > kMaxBufferedAudioFrames) {
                lock.unlock();
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
                continue;
            }
        }

        AVPacket* pkt = nullptr;
        {
            std::unique_lock<std::mutex> lock(audio_queue_mutex);
            audio_queue_cond.wait(lock, [this] { return !audio_queue.empty() || stop_requested; });
            if (stop_requested) break;
            pkt = audio_queue.front();
            audio_queue.pop();
        }

        int sendRet;
        {
            std::lock_guard<std::mutex> codecLock(audio_codec_mutex);
            sendRet = avcodec_send_packet(audio_codec_ctx, pkt);
        }
        if (sendRet == 0) {
            while (true) {
                int recvRet;
                {
                    std::lock_guard<std::mutex> codecLock(audio_codec_mutex);
                    recvRet = avcodec_receive_frame(audio_codec_ctx, frame);
                }
                if (recvRet != 0) break;

                uint8_t* out_buffer = nullptr;
                int out_samples = av_rescale_rnd(swr_get_delay(swr_ctx, audio_codec_ctx->sample_rate) + frame->nb_samples, 
                                                 kOutputSampleRate, audio_codec_ctx->sample_rate, AV_ROUND_UP);
                av_samples_alloc(&out_buffer, NULL, kOutputChannels, out_samples, AV_SAMPLE_FMT_FLT, 0);
                
                int converted_samples = swr_convert(swr_ctx, &out_buffer, out_samples, (const uint8_t**)frame->data, frame->nb_samples);
                
                if (converted_samples > 0) {
                    std::lock_guard<std::mutex> lock(audio_buf_mutex);
                    float* float_buf = (float*)out_buffer;
                    int num_floats = converted_samples * kOutputChannels;
                    audio_buffer.insert(audio_buffer.end(), float_buf, float_buf + num_floats);

                    // audio_chunk_end_pts publishes the decode-side frontier
                    // (the content PTS just past the samples this thread has
                    // now handed off) -- that's a fact this thread genuinely
                    // owns. audio_clock itself is intentionally NOT written
                    // here: it needs to reflect the sample that's about to
                    // actually play next, which depends on how much of what
                    // this thread has pushed is still sitting unplayed --
                    // information only the real-time consumer (onAudioReady)
                    // has, since this thread only waits on packet
                    // availability, not on real playback time. Having two
                    // independent writers to the same clock (this thread
                    // computing an "optimistic" value, onAudioReady
                    // computing the "real" one) was harmless only by
                    // accident of both being mutex-guarded -- collapsing to
                    // onAudioReady as the single owner removes that
                    // duplication rather than just leaving it in place.
                    double frame_pts;
                    if (frame->best_effort_timestamp != AV_NOPTS_VALUE) {
                        frame_pts = frame->best_effort_timestamp *
                            av_q2d(format_ctx->streams[audio_stream_idx]->time_base);
                    } else {
                        // No usable timestamp for this frame -- hold at the
                        // last known frontier rather than feeding the
                        // AV_NOPTS_VALUE sentinel into the PTS math.
                        frame_pts = audio_chunk_end_pts.load();
                    }
                    double chunk_end_pts = frame_pts + (double)converted_samples / kOutputSampleRate;
                    audio_chunk_end_pts = chunk_end_pts;
                }
                av_freep(&out_buffer);
            }
        }
        av_packet_free(&pkt);
    }
    av_frame_free(&frame);
}

oboe::DataCallbackResult FFmpegPlayer::onAudioReady(oboe::AudioStream* audioStream, void* audioData, int32_t numFrames) {
    float* out = static_cast<float*>(audioData);
    std::lock_guard<std::mutex> lock(audio_buf_mutex);

    if (!is_playing) {
        memset(out, 0, numFrames * kOutputChannels * sizeof(float));
        return oboe::DataCallbackResult::Continue;
    }

    float speed = playback_speed.load();
    if (speed <= 0.0f) speed = 1.0f;
    float vol = volume_multiplier;

    // Previously this always copied audio out 1:1 regardless of
    // playback_speed -- the video thread's A/V-sync sleeps already scale
    // by playback_speed (see videoDecodeThreadFunc), but with audio
    // always actually playing at 1x, video just kept re-syncing back to
    // real-time audio, so changing speed had no real effect on anything
    // audible. Speeding up/slowing down here too -- by consuming source
    // frames faster/slower than 1:1 per output frame -- is what actually
    // makes setPlaybackSpeed do something. This shifts pitch along with
    // rate (no independent time-stretching), which is the standard
    // trade-off for a simple speed control.
    if (speed == 1.0f) {
        int numFloatsNeeded = numFrames * kOutputChannels;
        if (audio_buffer.size() >= (size_t)numFloatsNeeded) {
            for (int i = 0; i < numFloatsNeeded; i++) {
                out[i] = audio_buffer[i] * vol;
            }
            audio_buffer.erase(audio_buffer.begin(), audio_buffer.begin() + numFloatsNeeded);
            double buffered_seconds = (double)(audio_buffer.size() / kOutputChannels) / kOutputSampleRate;
            audio_clock = audio_chunk_end_pts.load() - buffered_seconds;
        } else {
            memset(out, 0, numFloatsNeeded * sizeof(float));
        }
        return oboe::DataCallbackResult::Continue;
    }

    // Non-1x speed: pull resampled audio through speed_swr_ctx (configured
    // by setPlaybackSpeed(), never here -- see that function and
    // speed_swr_ctx's header comment for why). It can be null very briefly
    // right after a speed change, if this callback lands between
    // playback_speed's atomic store and setPlaybackSpeed() reaching its
    // lock below -- treat that the same as an underrun.
    if (!speed_swr_ctx) {
        memset(out, 0, numFrames * kOutputChannels * sizeof(float));
        return oboe::DataCallbackResult::Continue;
    }

    // Require roughly the same amount of buffered input the old
    // interpolator did before resampling at all -- without this, a
    // nearly-empty audio_buffer would feed swr a tiny, noisy trickle of
    // input every callback instead of accumulating enough to resample
    // smoothly.
    size_t availableFrames = audio_buffer.size() / kOutputChannels;
    size_t minFramesNeeded = (size_t)(numFrames * (double)speed);
    if (availableFrames < minFramesNeeded) {
        memset(out, 0, numFrames * kOutputChannels * sizeof(float));
        return oboe::DataCallbackResult::Continue;
    }

    int32_t framesWritten = 0;
    while (framesWritten < numFrames) {
        uint8_t* outSlice = reinterpret_cast<uint8_t*>(out + framesWritten * kOutputChannels);
        int outCap = numFrames - framesWritten;

        // Drain whatever swr already has buffered internally from a prior
        // callback before feeding it more input.
        int produced = swr_convert(speed_swr_ctx, &outSlice, outCap, nullptr, 0);
        if (produced > 0) {
            framesWritten += produced;
            continue;
        }

        availableFrames = audio_buffer.size() / kOutputChannels;
        if (availableFrames == 0) break; // genuinely out of input; pad silence below

        // swr_convert() greedily consumes ALL input provided to it, buffering
        // whatever it doesn't immediately output. To prevent it from swallowing
        // the entire audio_buffer (and ruining the audio_clock calculation), we
        // only feed it roughly the number of frames it needs to produce outCap
        // (plus a tiny 32-frame margin for the resampling filter's internal delay).
        int framesToFeed = std::min((int)availableFrames, (int)(outCap * speed) + 32);

        const uint8_t* inPtr = reinterpret_cast<const uint8_t*>(audio_buffer.data());
        produced = swr_convert(speed_swr_ctx, &outSlice, outCap, &inPtr, framesToFeed);
        
        audio_buffer.erase(audio_buffer.begin(), audio_buffer.begin() + framesToFeed * kOutputChannels);

        if (produced > 0) {
            framesWritten += produced;
        } else {
            // Fed everything available and swr still has nothing to emit
            // -- this callback has a hard time budget, so don't spin on
            // it; pad the remainder with silence instead.
            break;
        }
    }

    if (framesWritten < numFrames) {
        memset(out + framesWritten * kOutputChannels, 0,
               (numFrames - framesWritten) * kOutputChannels * sizeof(float));
    }

    if (vol != 1.0f) {
        int totalFloats = numFrames * kOutputChannels;
        for (int i = 0; i < totalFloats; i++) out[i] *= vol;
    }

    double buffered_seconds = (double)(audio_buffer.size() / kOutputChannels) / kOutputSampleRate;
    audio_clock = audio_chunk_end_pts.load() - buffered_seconds;

    return oboe::DataCallbackResult::Continue;
}