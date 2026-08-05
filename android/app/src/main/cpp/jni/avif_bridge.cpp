#include <jni.h>
#include <vector>
#include <cstring>
#include <android/log.h>
#include "avif/avif.h"
#include "jni_bridge_common.h"

#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "VaultExplorer_AVIF", __VA_ARGS__)

extern "C" JNIEXPORT jintArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getAvifInfoNative(
        JNIEnv* env, jobject, jbyteArray avifBytes) {
    JNI_TRY
    if (!avifBytes) return nullptr;
    jsize len = env->GetArrayLength(avifBytes);
    jbyte* data = env->GetByteArrayElements(avifBytes, nullptr);

    avifDecoder* decoder = avifDecoderCreate();
    if (!decoder) {
        env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);
        return nullptr;
    }

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
    int count = decoder->imageCount;
    int durationMs = static_cast<int>(decoder->duration * 1000.0);

    avifDecoderDestroy(decoder);
    env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);

    jintArray result = env->NewIntArray(4);
    jint info[4] = {width, height, count, durationMs};
    env->SetIntArrayRegion(result, 0, 4, info);
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_decodeAvifFrameNative(
        JNIEnv* env, jobject, jbyteArray avifBytes, jint frameIndex) {
    JNI_TRY
    if (!avifBytes) return nullptr;
    jsize len = env->GetArrayLength(avifBytes);
    jbyte* data = env->GetByteArrayElements(avifBytes, nullptr);

    avifDecoder* decoder = avifDecoderCreate();
    if (!decoder) {
        env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);
        return nullptr;
    }

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

    res = avifDecoderNthImage(decoder, frameIndex);
    if (res != AVIF_RESULT_OK) {
        LOGE("avifDecoderNthImage(%d) failed: %s (%d)", frameIndex, avifResultToString(res), res);
        avifDecoderDestroy(decoder);
        env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);
        return nullptr;
    }

    avifRGBImage rgb;
    avifRGBImageSetDefaults(&rgb, decoder->image);
    rgb.format = AVIF_RGB_FORMAT_RGBA;
    rgb.depth = 8;

    res = avifRGBImageAllocatePixels(&rgb);
    if (res != AVIF_RESULT_OK) {
        LOGE("avifRGBImageAllocatePixels failed: %s (%d)", avifResultToString(res), res);
        avifDecoderDestroy(decoder);
        env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);
        return nullptr;
    }

    res = avifImageYUVToRGB(decoder->image, &rgb);
    if (res != AVIF_RESULT_OK) {
        LOGE("avifImageYUVToRGB failed: %s (%d)", avifResultToString(res), res);
        avifRGBImageFreePixels(&rgb);
        avifDecoderDestroy(decoder);
        env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);
        return nullptr;
    }

    int durationMs = static_cast<int>(decoder->imageTiming.duration * 1000.0);
    if (durationMs <= 0) durationMs = 100;

    size_t rgbaSize = static_cast<size_t>(rgb.rowBytes) * rgb.height;
    jbyteArray rgbaArray = env->NewByteArray(static_cast<jsize>(rgbaSize));
    env->SetByteArrayRegion(rgbaArray, 0, static_cast<jsize>(rgbaSize),
                            reinterpret_cast<const jbyte*>(rgb.pixels));

    avifRGBImageFreePixels(&rgb);
    avifDecoderDestroy(decoder);
    env->ReleaseByteArrayElements(avifBytes, data, JNI_ABORT);

    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID initMethod = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID putMethod = env->GetMethodID(mapClass, "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jobject map = env->NewObject(mapClass, initMethod);

    jstring keyBytes = env->NewStringUTF("rgbaBytes");
    jstring keyDuration = env->NewStringUTF("durationMs");

    jclass integerClass = env->FindClass("java/lang/Integer");
    jmethodID integerInit = env->GetMethodID(integerClass, "<init>", "(I)V");
    jobject durationObj = env->NewObject(integerClass, integerInit, durationMs);

    env->CallObjectMethod(map, putMethod, keyBytes, rgbaArray);
    env->CallObjectMethod(map, putMethod, keyDuration, durationObj);

    return map;
    JNI_CATCH_RETURN(nullptr)
}