#include <jni.h>
#include <cstdint>
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

// ── Single-frame API (image editor / info probe) ────────────────────────
//
// NativeEngine.kt declares getAvifInfoNative and decodeAvifFrameNative, and
// the Dart/Kotlin layers call them (ImageEditorScreen._decodeImage ->
// VaultCryptoApi.getAvifInfo/decodeAvifFrame -> DerivedKeyHandlers), but only
// decodeAvifNative used to exist on the native side. Calling a `native`
// method that has no JNI symbol throws UnsatisfiedLinkError, which is an
// Error and not an Exception, so none of the handlers' `catch (e: Exception)`
// blocks caught it and opening an AVIF in the editor killed the app.

namespace {

// Creates a decoder over [data] and parses the container. On failure the
// decoder is destroyed and nullptr returned. The caller keeps [data] alive
// for as long as the returned decoder is used (avifDecoderSetIOMemory does
// not copy it).
avifDecoder* createParsedAvifDecoder(const uint8_t* data, size_t len) {
    avifDecoder* decoder = avifDecoderCreate();
    if (!decoder) return nullptr;
    decoder->maxThreads = getOptimalAvifThreads();
    decoder->codecChoice = AVIF_CODEC_CHOICE_AUTO;

    avifResult res = avifDecoderSetIOMemory(decoder, data, len);
    if (res != AVIF_RESULT_OK) {
        LOGE("avifDecoderSetIOMemory failed: %s (%d)", avifResultToString(res), res);
        avifDecoderDestroy(decoder);
        return nullptr;
    }
    res = avifDecoderParse(decoder);
    if (res != AVIF_RESULT_OK) {
        LOGE("avifDecoderParse failed: %s (%d)", avifResultToString(res), res);
        avifDecoderDestroy(decoder);
        return nullptr;
    }
    return decoder;
}

int avifDurationToMs(double seconds) {
    if (!(seconds > 0.0)) return 0;
    double ms = seconds * 1000.0;
    return ms > 2147483000.0 ? 2147483000 : static_cast<int>(ms);
}

}  // namespace

// Returns [width, height, frameCount, totalDurationMs], or null when the
// bytes are not a decodable AVIF.
extern "C" JNIEXPORT jintArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getAvifInfoNative(
        JNIEnv* env, jobject, jbyteArray avifBytes) {
    JNI_TRY
    if (!avifBytes) return nullptr;
    jsize len = env->GetArrayLength(avifBytes);
    if (len <= 0) return nullptr;
    jbyte* data = env->GetByteArrayElements(avifBytes, nullptr);
    if (!data) return nullptr;

    avifDecoder* decoder =
        createParsedAvifDecoder(reinterpret_cast<const uint8_t*>(data), static_cast<size_t>(len));

    jint values[4] = {0, 0, 0, 0};
    const bool ok = decoder != nullptr;
    if (ok) {
        values[0] = static_cast<jint>(decoder->image->width);
        values[1] = static_cast<jint>(decoder->image->height);
        values[2] = static_cast<jint>(decoder->imageCount);
        values[3] = static_cast<jint>(avifDurationToMs(decoder->duration));
        avifDecoderDestroy(decoder);
    }
    env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);
    if (!ok) return nullptr;

    jintArray out = env->NewIntArray(4);
    if (!out) return nullptr;  // OutOfMemoryError is already pending
    env->SetIntArrayRegion(out, 0, 4, values);
    return out;
    JNI_CATCH_RETURN(nullptr)
}

// Decodes ONE frame to 8-bit RGBA. Returns {"rgbaBytes": byte[],
// "durationMs": Integer}, or null when the bytes are not a decodable AVIF or
// [frameIndex] is out of range.
extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_decodeAvifFrameNative(
        JNIEnv* env, jobject, jbyteArray avifBytes, jint frameIndex) {
    JNI_TRY
    if (!avifBytes) return nullptr;
    jsize len = env->GetArrayLength(avifBytes);
    if (len <= 0) return nullptr;
    jbyte* data = env->GetByteArrayElements(avifBytes, nullptr);
    if (!data) return nullptr;

    avifDecoder* decoder =
        createParsedAvifDecoder(reinterpret_cast<const uint8_t*>(data), static_cast<size_t>(len));
    if (!decoder) {
        env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);
        return nullptr;
    }

    jobject result = nullptr;
    avifRGBImage rgb;
    bool rgbAllocated = false;

    do {
        if (frameIndex < 0 || frameIndex >= decoder->imageCount) {
            LOGE("frame %d out of range (imageCount=%d)", static_cast<int>(frameIndex),
                 static_cast<int>(decoder->imageCount));
            break;
        }
        avifResult res = avifDecoderNthImage(decoder, static_cast<uint32_t>(frameIndex));
        if (res != AVIF_RESULT_OK) {
            LOGE("avifDecoderNthImage(%d) failed: %s (%d)", static_cast<int>(frameIndex),
                 avifResultToString(res), res);
            break;
        }

        avifRGBImageSetDefaults(&rgb, decoder->image);
        rgb.format = AVIF_RGB_FORMAT_RGBA;
        rgb.depth = 8;
        res = avifRGBImageAllocatePixels(&rgb);
        if (res != AVIF_RESULT_OK) {
            LOGE("avifRGBImageAllocatePixels failed: %s (%d)", avifResultToString(res), res);
            break;
        }
        rgbAllocated = true;

        res = avifImageYUVToRGB(decoder->image, &rgb);
        if (res != AVIF_RESULT_OK) {
            LOGE("avifImageYUVToRGB failed: %s (%d)", avifResultToString(res), res);
            break;
        }

        const size_t rgbaSize = static_cast<size_t>(rgb.rowBytes) * rgb.height;
        if (rgbaSize == 0 || rgbaSize > static_cast<size_t>(INT32_MAX)) {
            LOGE("decoded frame too large for a Java array: %zu bytes", rgbaSize);
            break;
        }

        int durationMs = avifDurationToMs(decoder->imageTiming.duration);
        if (durationMs <= 0) durationMs = 100;

        jbyteArray rgbaArray = env->NewByteArray(static_cast<jsize>(rgbaSize));
        if (!rgbaArray) break;  // OutOfMemoryError is already pending
        env->SetByteArrayRegion(rgbaArray, 0, static_cast<jsize>(rgbaSize),
                                reinterpret_cast<const jbyte*>(rgb.pixels));

        jclass mapClass = env->FindClass("java/util/HashMap");
        jclass integerClass = env->FindClass("java/lang/Integer");
        if (!mapClass || !integerClass) break;
        jmethodID mapInit = env->GetMethodID(mapClass, "<init>", "()V");
        jmethodID mapPut = env->GetMethodID(mapClass, "put",
            "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
        jmethodID integerInit = env->GetMethodID(integerClass, "<init>", "(I)V");
        if (!mapInit || !mapPut || !integerInit) break;

        jobject map = env->NewObject(mapClass, mapInit);
        jobject durationObj = env->NewObject(integerClass, integerInit, durationMs);
        jstring keyBytes = env->NewStringUTF("rgbaBytes");
        jstring keyDuration = env->NewStringUTF("durationMs");
        if (!map || !durationObj || !keyBytes || !keyDuration) break;

        env->CallObjectMethod(map, mapPut, keyBytes, rgbaArray);
        env->CallObjectMethod(map, mapPut, keyDuration, durationObj);
        if (env->ExceptionCheck()) break;
        result = map;
    } while (false);

    if (rgbAllocated) avifRGBImageFreePixels(&rgb);
    avifDecoderDestroy(decoder);
    env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);
    return result;
    JNI_CATCH_RETURN(nullptr)
}
