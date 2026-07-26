#include "ffmpeg_player.h"
#include <android/log.h>
#include <unistd.h>
#include <sys/stat.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "FFmpegPlayer", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "FFmpegPlayer", __VA_ARGS__)
// Temporary diagnostic instrumentation for the seekbar-stepping /
// speed-hunting-during-2x-hold investigation. Filter logcat on these tags
// specifically (they're deliberately separate from LOGI/LOGE above so they
// can be grep'd out independently). NOTE: LOGD_SYNC in particular fires
// from onAudioReady(), which runs on the real-time Oboe audio callback
// thread -- __android_log_print() does I/O and is not real-time-safe, so
// having this active can itself perturb timing. Treat results captured
// while it's enabled as "probably indicative", not definitive, and pull
// these calls back out once the root cause is confirmed.
#define LOGD_SYNC(...) __android_log_print(ANDROID_LOG_DEBUG, "FFmpegPlayer.Sync", __VA_ARGS__)
#define LOGD_AUDIO(...) __android_log_print(ANDROID_LOG_DEBUG, "FFmpegPlayer.Audio", __VA_ARGS__)

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

void FFmpegPlayer::notifyEvent(const char* eventName, double positionMs, double durationMs, int width, int height, const char* errorMsg) {
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
    is_playing = true;
    // Reaching the natural end leaves the pipeline idling with nothing
    // queued (see the demux loop's EOF handling) -- without an explicit
    // seek there is nothing left to feed, so play() would otherwise be a
    // silent no-op right when the video is sitting at its end. Most
    // players treat "press play at the end" as "restart from the top",
    // so mirror that instead.
    if (input_eof.load()) {
        seekTo(0);
    }
    // pause()/"endReached" both push isPlaying=false to the Dart side via
    // an event; without a matching push here, the Dart-side value gets
    // stuck at isPlaying=false forever after the first pause, since
    // nothing ever tells it playback resumed (only the demux thread's
    // one-time initial "playing" event on open used to fire this).
    // durationMs is included so a resume after the video was already open
    // is a no-op on the Dart side rather than a re-initialization; width/
    // height are deliberately omitted (default 0 -> excluded from the
    // event map entirely, see notifyEvent) so this doesn't stomp the
    // already-known video size with 0x0.
    double durationMs = format_ctx ? (double)format_ctx->duration / AV_TIME_BASE * 1000 : 0;
    notifyEvent("playing", video_clock.load() * 1000, durationMs);
}
void FFmpegPlayer::pause() { is_playing = false; notifyEvent("paused"); }

void FFmpegPlayer::stop() {
    stop_requested = true;
    is_playing = false;

    // 1. Stop audio callbacks BEFORE deleting resources to prevent SIGSEGV
    if (audio_stream) {
        audio_stream->stop();
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
    LOGD_AUDIO("setPlaybackSpeed speed=%.2f swr_ctx=%s buffered_frames_at_switch=%zu",
               speed, newCtx ? "reconfigured" : (speed == 1.0f ? "n/a(1x)" : "FAILED"),
               audio_buffer.size() / kOutputChannels);
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
            avcodec_open2(video_codec_ctx, codec, NULL);
            
            // Set window geometry on the native window so ANativeWindow_lock works properly
            if (native_window && codecpar->width > 0 && codecpar->height > 0) {
                ANativeWindow_setBuffersGeometry(native_window, codecpar->width, codecpar->height, WINDOW_FORMAT_RGBA_8888);
            }

            video_thread = std::thread(&FFmpegPlayer::videoDecodeThreadFunc, this);
            notifyEvent("playing", 0, (double)format_ctx->duration / AV_TIME_BASE * 1000, codecpar->width, codecpar->height);
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

        if (video_queue.size() > kMaxQueuedVideoPackets || audio_queue.size() > kMaxQueuedAudioPackets) {
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

    while (!stop_requested) {
        if (fps_window_reset_requested.exchange(false)) {
            fps_window_start_sec = av_gettime_relative() / 1000000.0;
            fps_window_frame_count = 0;
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

                double pts = frame->best_effort_timestamp * av_q2d(format_ctx->streams[video_stream_idx]->time_base);
                video_clock = pts;
                
                // A/V Synchronization
                //
                // audio_clock is only ever updated when audioDecodeThreadFunc
                // decodes a new packet (see that function) -- it does NOT
                // track wall-clock time on its own. Audio and video tracks
                // essentially never end at exactly the same timestamp (encoder
                // delay, differing track durations, etc.), so on nearly every
                // file the audio track's last packet gets decoded first,
                // audio_clock stops updating and sits frozen from then on,
                // while pts here keeps advancing for the video frames still
                // arriving. diff = pts - audio_clock then grows without bound,
                // and for however many frames it takes to cross the 1.0s cap
                // below, this was sleeping for close to a full second per
                // frame -- experienced as the video grinding almost to a halt
                // for the last stretch before it actually reaches the end.
                // input_eof (set once the demuxer truly has no more packets
                // coming for either stream) tells us audio_clock can no longer
                // be trusted, so we fall back to plain fps-based pacing
                // instead of chasing it.
                if (audio_stream_idx >= 0 && audio_clock > 0 && !input_eof.load()) {
                    double diff = pts - audio_clock;
                    int sleepMs = 0;
                    bool slept = (diff > kAvSyncMinDiffSec && diff < kAvSyncMaxDiffSec);
                    if (slept) {
                        sleepMs = (int)(diff * 1000 / playback_speed);
                        std::this_thread::sleep_for(std::chrono::milliseconds(sleepMs));
                    }
                    LOGD_SYNC("mode=diff pts=%.3f audio_clock=%.3f diff=%.3f speed=%.2f sleep_ms=%d slept=%d",
                              pts, audio_clock.load(), diff, playback_speed.load(), sleepMs, slept);
                } else {
                    double fps = av_q2d(format_ctx->streams[video_stream_idx]->avg_frame_rate);
                    int delay_ms = (fps > 0) ? (int)(1000.0 / fps / playback_speed) : kFallbackFrameDelayMs;
                    std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
                    LOGD_SYNC("mode=fallback pts=%.3f audio_clock=%.3f fps=%.2f speed=%.2f sleep_ms=%d reason=%s",
                              pts, audio_clock.load(), fps, playback_speed.load(), delay_ms,
                              (audio_stream_idx < 0) ? "no_audio_stream" : (audio_clock <= 0 ? "audio_clock_not_set" : "input_eof"));
                }

                if (native_window && is_playing) {
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
                    LOGD_SYNC("timeChanged fire pts=%.3f wall_clock_us=%lld", pts, (long long)av_gettime());
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

                    // audio_clock has to reflect the sample that's about to
                    // actually play next, not whatever was just decoded --
                    // this thread only waits on packet availability (see
                    // the condition_variable wait above), not on real
                    // playback time, so decode+resample regularly races
                    // seconds ahead of what onAudioReady() has actually
                    // consumed so far. Using the raw decoded PTS here was
                    // the root cause of "most videos play too fast": video
                    // frames are paced against this clock (see
                    // videoDecodeThreadFunc's A/V sync block), so an
                    // audio_clock running ahead of true playback dragged
                    // video pacing ahead with it, skipping most of its
                    // sleep_for(). Backing out however much audio is still
                    // sitting unplayed in audio_buffer gives the PTS of the
                    // sample that will actually be heard next.
                    double frame_pts = frame->best_effort_timestamp *
                        av_q2d(format_ctx->streams[audio_stream_idx]->time_base);
                    double chunk_end_pts = frame_pts + (double)converted_samples / kOutputSampleRate;
                    double buffered_seconds = (double)(audio_buffer.size() / kOutputChannels) / kOutputSampleRate;
                    audio_clock = chunk_end_pts - buffered_seconds;
                    LOGD_AUDIO("push frame_pts=%.3f converted_samples=%d buffered_frames=%zu buffered_sec=%.3f audio_clock=%.3f",
                               frame_pts, converted_samples, audio_buffer.size() / kOutputChannels, buffered_seconds, audio_clock.load());
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
        } else {
            LOGD_SYNC("onAudioReady UNDERRUN mode=1x have_frames=%zu need_frames=%d",
                      audio_buffer.size() / kOutputChannels, numFrames);
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
        LOGD_SYNC("onAudioReady UNDERRUN mode=speed reason=null_swr_ctx speed=%.2f", speed);
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
        LOGD_SYNC("onAudioReady UNDERRUN mode=speed speed=%.2f have_frames=%zu need_frames=%zu",
                  speed, availableFrames, minFramesNeeded);
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

        const uint8_t* inPtr = reinterpret_cast<const uint8_t*>(audio_buffer.data());
        produced = swr_convert(speed_swr_ctx, &outSlice, outCap, &inPtr, (int)availableFrames);
        // swr_convert() always fully consumes the in_count it's given --
        // anything it can't fit into out_count is buffered internally and
        // returned by a later drain/next call, not left in `in` -- so this
        // whole chunk is gone from audio_buffer regardless of `produced`.
        audio_buffer.erase(audio_buffer.begin(), audio_buffer.begin() + availableFrames * kOutputChannels);

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
        LOGD_SYNC("onAudioReady UNDERRUN mode=speed speed=%.2f frames_written=%d frames_needed=%d remaining_buffer_frames=%zu",
                  speed, framesWritten, numFrames, audio_buffer.size() / kOutputChannels);
        memset(out + framesWritten * kOutputChannels, 0,
               (numFrames - framesWritten) * kOutputChannels * sizeof(float));
    } else if (++audio_ready_log_counter % 30 == 0) {
        // Trend line, not a problem report -- throttled to roughly once
        // every ~0.5-1s (30 callbacks) so it's readable rather than one
        // line per callback, while still showing whether buffer headroom
        // is trending down over the course of a 2x hold.
        LOGD_SYNC("onAudioReady ok speed=%.2f frames_written=%d remaining_buffer_frames=%zu",
                  speed, framesWritten, audio_buffer.size() / kOutputChannels);
    }

    if (vol != 1.0f) {
        int totalFloats = numFrames * kOutputChannels;
        for (int i = 0; i < totalFloats; i++) out[i] *= vol;
    }

    return oboe::DataCallbackResult::Continue;
}