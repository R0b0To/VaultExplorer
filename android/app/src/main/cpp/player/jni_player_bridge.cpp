// File: android/app/src/main/cpp/player/jni_player_bridge.cpp
#include <jni.h>
#include <android/native_window_jni.h>
#include "ffmpeg_player.h"

extern "C" {
    // Register HW codecs with JNI on load
    void av_jni_set_java_vm(void *vm, void *log_ctx);
}


extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_ffmpegplayer_FFmpegPlayerEngine_nativeCreate(JNIEnv* env, jobject thiz, jobject surface) {
    ANativeWindow* window = surface ? ANativeWindow_fromSurface(env, surface) : nullptr;
    FFmpegPlayer* player = new FFmpegPlayer(env, thiz, window);
    return reinterpret_cast<jlong>(player);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_ffmpegplayer_FFmpegPlayerEngine_nativeSetDataSource(JNIEnv* env, jobject thiz, jlong ptr, jint fd, jboolean autoPlay) {
    auto player = reinterpret_cast<FFmpegPlayer*>(ptr);
    if (player) player->setDataSource(fd, autoPlay);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_ffmpegplayer_FFmpegPlayerEngine_nativePlay(JNIEnv* env, jobject thiz, jlong ptr) {
    auto player = reinterpret_cast<FFmpegPlayer*>(ptr);
    if (player) player->play();
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_ffmpegplayer_FFmpegPlayerEngine_nativePause(JNIEnv* env, jobject thiz, jlong ptr) {
    auto player = reinterpret_cast<FFmpegPlayer*>(ptr);
    if (player) player->pause();
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_ffmpegplayer_FFmpegPlayerEngine_nativeStop(JNIEnv* env, jobject thiz, jlong ptr) {
    auto player = reinterpret_cast<FFmpegPlayer*>(ptr);
    if (player) player->stop();
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_ffmpegplayer_FFmpegPlayerEngine_nativeSeekTo(JNIEnv* env, jobject thiz, jlong ptr, jlong positionMs) {
    auto player = reinterpret_cast<FFmpegPlayer*>(ptr);
    if (player) player->seekTo(positionMs);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_ffmpegplayer_FFmpegPlayerEngine_nativeSetVolume(JNIEnv* env, jobject thiz, jlong ptr, jint volume) {
    auto player = reinterpret_cast<FFmpegPlayer*>(ptr);
    if (player) player->setVolume(volume);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_ffmpegplayer_FFmpegPlayerEngine_nativeSetRate(JNIEnv* env, jobject thiz, jlong ptr, jfloat rate) {
    auto player = reinterpret_cast<FFmpegPlayer*>(ptr);
    if (player) player->setPlaybackSpeed(rate);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_ffmpegplayer_FFmpegPlayerEngine_nativeSetLooping(JNIEnv* env, jobject thiz, jlong ptr, jboolean looping) {
    auto player = reinterpret_cast<FFmpegPlayer*>(ptr);
    if (player) player->setLooping(looping);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_ffmpegplayer_FFmpegPlayerEngine_nativeDispose(JNIEnv* env, jobject thiz, jlong ptr) {
    auto player = reinterpret_cast<FFmpegPlayer*>(ptr);
    if (player) delete player;
}