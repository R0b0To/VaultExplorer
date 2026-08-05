#include <jni.h>
#include <vector>
#include <cstring>
#include <thread>
#include <algorithm>
#include <android/log.h>
#include "avif/avif.h"
#include "jni_bridge_common.h"

#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "VaultExplorer_AVIF", __VA_ARGS__)

static uint32_t getOptimalAvifThreads() {
    uint32_t cores = std::thread::hardware_concurrency();
    if (cores == 0) return 4;
    return std::min(cores, 8u);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_decodeAvifNative(
        JNIEnv* env, jobject, jbyteArray avifBytes) {
    JNI_TRY
    if (!avifBytes) return nullptr;
    jsize len = env->GetArrayLength(avifBytes);
    if (len <= 0) return nullptr;
    jbyte* data = env->GetByteArrayElements(avifBytes, nullptr);
    if (!data) return nullptr;

    avifDecoder* decoder = avifDecoderCreate();
    if (!decoder) {
        env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);
        return nullptr;
    }

    decoder->maxThreads = getOptimalAvifThreads();
    decoder->codecChoice = AVIF_CODEC_CHOICE_AUTO;

    avifResult res = avifDecoderSetIOMemory(decoder, reinterpret_cast<const uint8_t*>(data), len);
    if (res != AVIF_RESULT_OK) {
        LOGE("avifDecoderSetIOMemory failed: %s (%d)", avifResultToString(res), res);
        avifDecoderDestroy(decoder);
        env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);
        return nullptr;
    }

    res = avifDecoderParse(decoder);
    if (res != AVIF_RESULT_OK) {
        LOGE("avifDecoderParse failed: %s (%d)", avifResultToString(res), res);
        avifDecoderDestroy(decoder);
        env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);
        return nullptr;
    }

    int width = decoder->image->width;
    int height = decoder->image->height;
    int totalDurationMs = static_cast<int>(decoder->duration * 1000.0);

    // Prepare Java structures for returning result
    jclass arrayListClass = env->FindClass("java/util/ArrayList");
    jmethodID arrayListInit = env->GetMethodID(arrayListClass, "<init>", "()V");
    jmethodID arrayListAdd = env->GetMethodID(arrayListClass, "add", "(Ljava/lang/Object;)Z");
    jobject framesList = env->NewObject(arrayListClass, arrayListInit);

    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID mapInit = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(mapClass, "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jclass integerClass = env->FindClass("java/lang/Integer");
    jmethodID integerInit = env->GetMethodID(integerClass, "<init>", "(I)V");

    jstring keyBytes = env->NewStringUTF("rgbaBytes");
    jstring keyDuration = env->NewStringUTF("durationMs");

    // Single O(n) sequential decode pass
    while (avifDecoderNextImage(decoder) == AVIF_RESULT_OK) {
        avifRGBImage rgb;
        avifRGBImageSetDefaults(&rgb, decoder->image);
        rgb.format = AVIF_RGB_FORMAT_RGBA;
        rgb.depth = 8;

        if (avifRGBImageAllocatePixels(&rgb) != AVIF_RESULT_OK) {
            break;
        }

        if (avifImageYUVToRGB(decoder->image, &rgb) != AVIF_RESULT_OK) {
            avifRGBImageFreePixels(&rgb);
            break;
        }

        int durationMs = static_cast<int>(decoder->imageTiming.duration * 1000.0);
        if (durationMs <= 0) durationMs = 100;

        size_t rgbaSize = static_cast<size_t>(rgb.rowBytes) * rgb.height;
        jbyteArray rgbaArray = env->NewByteArray(static_cast<jsize>(rgbaSize));
        env->SetByteArrayRegion(rgbaArray, 0, static_cast<jsize>(rgbaSize),
                                reinterpret_cast<const jbyte*>(rgb.pixels));

        jobject frameMap = env->NewObject(mapClass, mapInit);
        jobject durationObj = env->NewObject(integerClass, integerInit, durationMs);

        env->CallObjectMethod(frameMap, mapPut, keyBytes, rgbaArray);
        env->CallObjectMethod(frameMap, mapPut, keyDuration, durationObj);

        env->CallBooleanMethod(framesList, arrayListAdd, frameMap);

        avifRGBImageFreePixels(&rgb);

        env->DeleteLocalRef(rgbaArray);
        env->DeleteLocalRef(frameMap);
        env->DeleteLocalRef(durationObj);
    }

    avifDecoderDestroy(decoder);
    env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);

    jobject resultMap = env->NewObject(mapClass, mapInit);
    jstring keyWidth = env->NewStringUTF("width");
    jstring keyHeight = env->NewStringUTF("height");
    jstring keyTotalDuration = env->NewStringUTF("totalDurationMs");
    jstring keyFrames = env->NewStringUTF("frames");

    env->CallObjectMethod(resultMap, mapPut, keyWidth, env->NewObject(integerClass, integerInit, width));
    env->CallObjectMethod(resultMap, mapPut, keyHeight, env->NewObject(integerClass, integerInit, height));
    env->CallObjectMethod(resultMap, mapPut, keyTotalDuration, env->NewObject(integerClass, integerInit, totalDurationMs));
    env->CallObjectMethod(resultMap, mapPut, keyFrames, framesList);

    return resultMap;
    JNI_CATCH_RETURN(nullptr)
}