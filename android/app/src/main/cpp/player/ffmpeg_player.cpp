#include "ffmpeg_player.h"
#include <android/log.h>
#include <unistd.h>
#include <sys/stat.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "FFmpegPlayer", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "FFmpegPlayer", __VA_ARGS__)

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

    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID init = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID put = env->GetMethodID(mapClass, "put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jobject map = env->NewObject(mapClass, init);

    jstring eventKey = env->NewStringUTF("event");
    jstring eventVal = env->NewStringUTF(eventName);
    env->CallObjectMethod(map, put, eventKey, eventVal);
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
        jclass doubleClass = env->FindClass("java/lang/Double");
        jmethodID doubleInit = env->GetMethodID(doubleClass, "<init>", "(D)V");
        jobject posVal = env->NewObject(doubleClass, doubleInit, positionMs);
        env->CallObjectMethod(map, put, posKey, posVal);
        env->DeleteLocalRef(posKey);
        env->DeleteLocalRef(posVal);
    }

    if (durationMs > 0) {
        jstring durKey = env->NewStringUTF("durationMs");
        jclass doubleClass = env->FindClass("java/lang/Double");
        jmethodID doubleInit = env->GetMethodID(doubleClass, "<init>", "(D)V");
        jobject durVal = env->NewObject(doubleClass, doubleInit, durationMs);
        env->CallObjectMethod(map, put, durKey, durVal);
        env->DeleteLocalRef(durKey);
        env->DeleteLocalRef(durVal);
    }
    
    if (width > 0 && height > 0) {
        jstring wKey = env->NewStringUTF("width");
        jstring hKey = env->NewStringUTF("height");
        jclass intClass = env->FindClass("java/lang/Integer");
        jmethodID intInit = env->GetMethodID(intClass, "<init>", "(I)V");
        jobject wVal = env->NewObject(intClass, intInit, width);
        jobject hVal = env->NewObject(intClass, intInit, height);
        env->CallObjectMethod(map, put, wKey, wVal);
        env->CallObjectMethod(map, put, hKey, hVal);
        env->DeleteLocalRef(wKey); env->DeleteLocalRef(hKey);
        env->DeleteLocalRef(wVal); env->DeleteLocalRef(hVal);
    }

    if (errorMsg) {
        jstring errKey = env->NewStringUTF("message");
        jstring errVal = env->NewStringUTF(errorMsg);
        env->CallObjectMethod(map, put, errKey, errVal);
        env->DeleteLocalRef(errKey);
        env->DeleteLocalRef(errVal);
    }

    jclass pluginClass = env->GetObjectClass(plugin_instance_ref);
    jmethodID onEventMethod = env->GetMethodID(pluginClass, "onEventFromNative", "(Ljava/util/Map;)V");
    if (onEventMethod) env->CallVoidMethod(plugin_instance_ref, onEventMethod, map);
    
    env->DeleteLocalRef(map);
    env->DeleteLocalRef(mapClass);
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

    demux_thread = std::thread(&FFmpegPlayer::demuxThreadFunc, this);
}

void FFmpegPlayer::play() {
    is_playing = true;
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
    if (video_codec_ctx) { avcodec_free_context(&video_codec_ctx); video_codec_ctx = nullptr; }
    if (audio_codec_ctx) { avcodec_free_context(&audio_codec_ctx); audio_codec_ctx = nullptr; }
    if (format_ctx) { avformat_close_input(&format_ctx); format_ctx = nullptr; }
    if (io_ctx) { av_freep(&io_ctx->buffer); avio_context_free(&io_ctx); io_ctx = nullptr; }
    if (swr_ctx) { swr_free(&swr_ctx); swr_ctx = nullptr; }
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
    if (video_codec_ctx) avcodec_flush_buffers(video_codec_ctx);
    if (audio_codec_ctx) avcodec_flush_buffers(audio_codec_ctx);

    audio_clock = targetMs / 1000.0;
    video_clock = targetMs / 1000.0;
    notifyEvent("timeChanged", (double)targetMs, (double)format_ctx->duration / AV_TIME_BASE * 1000);
}

void FFmpegPlayer::setVolume(int v) { volume_multiplier = v / 100.0f; }
void FFmpegPlayer::setPlaybackSpeed(float speed) { playback_speed = speed; }
void FFmpegPlayer::setLooping(bool loop) { looping = loop; }

void FFmpegPlayer::demuxThreadFunc() {
    notifyEvent("opening");

    unsigned char* io_buffer = (unsigned char*)av_malloc(32768);
    io_ctx = avio_alloc_context(io_buffer, 32768, 0, this, readPacketCallback, NULL, seekCallback);
    format_ctx = avformat_alloc_context();
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
            video_codec_ctx = avcodec_alloc_context3(codec);
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
            audio_codec_ctx = avcodec_alloc_context3(codec);
            avcodec_parameters_to_context(audio_codec_ctx, codecpar);
            avcodec_open2(audio_codec_ctx, codec, NULL);

            // Modern FFmpeg 7/8 Channel Layout setup
            AVChannelLayout out_ch_layout = AV_CHANNEL_LAYOUT_STEREO;
            int sample_rate = audio_codec_ctx->sample_rate > 0 ? audio_codec_ctx->sample_rate : 48000;

            swr_alloc_set_opts2(&swr_ctx,
                &out_ch_layout, AV_SAMPLE_FMT_FLT, 48000,
                &audio_codec_ctx->ch_layout, audio_codec_ctx->sample_fmt, sample_rate,
                0, NULL);
            swr_init(swr_ctx);

            oboe::AudioStreamBuilder builder;
            builder.setDirection(oboe::Direction::Output)
                   ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
                   ->setFormat(oboe::AudioFormat::Float)
                   ->setChannelCount(2)
                   ->setSampleRate(48000)
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
            std::this_thread::sleep_for(std::chrono::milliseconds(10)); 
            continue; 
        }

        if (video_queue.size() > 50 || audio_queue.size() > 100) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
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
            if (looping) { 
                seekTo(0); 
            } else { 
                notifyEvent("endReached"); 
                break; 
            }
        }
    }
    av_packet_free(&packet);
}

void FFmpegPlayer::videoDecodeThreadFunc() {
    AVFrame* frame = av_frame_alloc();
    while (!stop_requested) {
        AVPacket* pkt = nullptr;
        {
            std::unique_lock<std::mutex> lock(video_queue_mutex);
            video_queue_cond.wait(lock, [this] { return !video_queue.empty() || stop_requested; });
            if (stop_requested) break;
            pkt = video_queue.front();
            video_queue.pop();
        }

        if (avcodec_send_packet(video_codec_ctx, pkt) == 0) {
            while (avcodec_receive_frame(video_codec_ctx, frame) == 0) {
                double pts = frame->best_effort_timestamp * av_q2d(format_ctx->streams[video_stream_idx]->time_base);
                video_clock = pts;
                
                // A/V Synchronization
                if (audio_stream_idx >= 0 && audio_clock > 0) {
                    double diff = pts - audio_clock;
                    if (diff > 0.005 && diff < 1.0) {
                        std::this_thread::sleep_for(std::chrono::milliseconds((int)(diff * 1000 / playback_speed)));
                    }
                } else {
                    double fps = av_q2d(format_ctx->streams[video_stream_idx]->avg_frame_rate);
                    int delay_ms = (fps > 0) ? (int)(1000.0 / fps / playback_speed) : 33;
                    std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
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
                    }
                }
                
                static int frame_count = 0;
                if (++frame_count % 15 == 0) {
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

        if (avcodec_send_packet(audio_codec_ctx, pkt) == 0) {
            while (avcodec_receive_frame(audio_codec_ctx, frame) == 0) {
                uint8_t* out_buffer = nullptr;
                int out_samples = av_rescale_rnd(swr_get_delay(swr_ctx, audio_codec_ctx->sample_rate) + frame->nb_samples, 
                                                 48000, audio_codec_ctx->sample_rate, AV_ROUND_UP);
                av_samples_alloc(&out_buffer, NULL, 2, out_samples, AV_SAMPLE_FMT_FLT, 0);
                
                int converted_samples = swr_convert(swr_ctx, &out_buffer, out_samples, (const uint8_t**)frame->data, frame->nb_samples);
                
                if (converted_samples > 0) {
                    std::lock_guard<std::mutex> lock(audio_buf_mutex);
                    float* float_buf = (float*)out_buffer;
                    int num_floats = converted_samples * 2;
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
                    double chunk_end_pts = frame_pts + (double)converted_samples / 48000.0;
                    double buffered_seconds = (double)(audio_buffer.size() / 2) / 48000.0;
                    audio_clock = chunk_end_pts - buffered_seconds;
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
    int numFloatsNeeded = numFrames * 2;
    
    std::lock_guard<std::mutex> lock(audio_buf_mutex);
    if (audio_buffer.size() >= (size_t)numFloatsNeeded && is_playing) {
        float vol = volume_multiplier;
        for (int i = 0; i < numFloatsNeeded; i++) {
            out[i] = audio_buffer[i] * vol;
        }
        audio_buffer.erase(audio_buffer.begin(), audio_buffer.begin() + numFloatsNeeded);
    } else {
        memset(out, 0, numFloatsNeeded * sizeof(float));
    }
    return oboe::DataCallbackResult::Continue;
}