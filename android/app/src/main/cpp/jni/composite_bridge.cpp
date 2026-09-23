#include <jni.h>
#include <vector>
#include <string>
#include <algorithm>
#include <android/log.h>
#include "containers/carrier_profiler.h"
#include "containers/composite_block_device.h"
#include "containers/composite_map.h"
#include "containers/container_create_composite.h"
#include "session/session_guard.h"
#include "session/volume_state.h"
#include "virtual_block_device.h"
#include "filesystems/fs_ops.h"
#include "jni_bridge_common.h"
#include "session/session_prepare.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_Composite", __VA_ARGS__)

namespace {
std::vector<CarrierTarget> parseCarrierTargets(
    JNIEnv* env, jobjectArray carrierPaths, jintArray carrierFds
) {
    std::vector<CarrierTarget> targets;
    jsize count = 0;
    if (carrierPaths) count = env->GetArrayLength(carrierPaths);
    else if (carrierFds) count = env->GetArrayLength(carrierFds);
    if (count <= 0) return targets;

    jint* fds = carrierFds ? env->GetIntArrayElements(carrierFds, nullptr) : nullptr;
    for (jsize i = 0; i < count; ++i) {
        CarrierTarget t;
        if (fds) t.fd = fds[i];
        if (carrierPaths) {
            jstring jstr = static_cast<jstring>(env->GetObjectArrayElement(carrierPaths, i));
            if (jstr) {
                const char* utf = env->GetStringUTFChars(jstr, nullptr);
                t.path = utf ? utf : "";
                env->ReleaseStringUTFChars(jstr, utf);
                env->DeleteLocalRef(jstr);
            }
        }
        if (t.fd >= 0) {
            t.closeOnDestruct = true;
        }
        targets.push_back(t);
    }
    if (fds) env->ReleaseIntArrayElements(carrierFds, fds, JNI_ABORT);
    return targets;
}
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_profileCarriersNative(
    JNIEnv* env, jobject, jobjectArray carrierPaths, jintArray carrierFds, jint safetyMarginPct
) {
    JNI_TRY
    auto carriers = parseCarrierTargets(env, carrierPaths, carrierFds);
    if (carriers.empty()) return nullptr;

    // 1. Sort canonically so UI, Create, and Unlock always use the identical order
    CompositeMap::sortCanonical(carriers);

    unsigned pct = (safetyMarginPct > 0 && safetyMarginPct <= 100) ? static_cast<unsigned>(safetyMarginPct) : 10;
    auto profile = CarrierProfiler::profileForAllocation(carriers, pct);

    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID mapInit = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(mapClass, "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jclass listClass = env->FindClass("java/util/ArrayList");
    jmethodID listInit = env->GetMethodID(listClass, "<init>", "(I)V");
    jmethodID listAdd = env->GetMethodID(listClass, "add", "(Ljava/lang/Object;)Z");

    jclass intClass = env->FindClass("java/lang/Integer");
    jmethodID intInit = env->GetMethodID(intClass, "<init>", "(I)V");
    jclass longClass = env->FindClass("java/lang/Long");
    jmethodID longInit = env->GetMethodID(longClass, "<init>", "(J)V");

    jobject resMap = env->NewObject(mapClass, mapInit);
    jobject listObj = env->NewObject(listClass, listInit, static_cast<jint>(profile.perFile.size()));

    for (const auto& b : profile.perFile) {
        jobject item = env->NewObject(mapClass, mapInit);

        auto putInt = [&](const char* k, int v) {
            jstring jk = env->NewStringUTF(k);
            jobject jv = env->NewObject(intClass, intInit, v);
            env->CallObjectMethod(item, mapPut, jk, jv);
            env->DeleteLocalRef(jk); env->DeleteLocalRef(jv);
        };
        auto putLong = [&](const char* k, uint64_t v) {
            jstring jk = env->NewStringUTF(k);
            jobject jv = env->NewObject(longClass, longInit, static_cast<jlong>(v));
            env->CallObjectMethod(item, mapPut, jk, jv);
            env->DeleteLocalRef(jk); env->DeleteLocalRef(jv);
        };
        auto putString = [&](const char* k, const std::string& v) {
            jstring jk = env->NewStringUTF(k);
            jstring jv = env->NewStringUTF(v.c_str());
            env->CallObjectMethod(item, mapPut, jk, jv);
            env->DeleteLocalRef(jk); env->DeleteLocalRef(jv);
        };

        putInt("fileIndex", static_cast<int>(b.fileIndex));
        putString("path", b.path);
        putString("detectedFormat", b.detectedFormat);
        putLong("fileSize", b.fileSize);
        putLong("payloadOffset", b.payloadOffset);
        putLong("allocatableBytes", b.allocatableBytes);
        putInt("tier", static_cast<int>(b.tier));

        env->CallBooleanMethod(listObj, listAdd, item);
        env->DeleteLocalRef(item);
    }

    jstring kTotal = env->NewStringUTF("totalAllocatableBytes");
    jobject vTotal = env->NewObject(longClass, longInit, static_cast<jlong>(profile.totalAllocatableBytes));
    env->CallObjectMethod(resMap, mapPut, kTotal, vTotal);
    env->DeleteLocalRef(kTotal); env->DeleteLocalRef(vTotal);

    jstring kCarriers = env->NewStringUTF("carriers");
    env->CallObjectMethod(resMap, mapPut, kCarriers, listObj);
    env->DeleteLocalRef(kCarriers); env->DeleteLocalRef(listObj);

    return resMap;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_createCompositeContainerNative(
    JNIEnv* env, jobject,
    jint volId,
    jobjectArray carrierPaths,
    jintArray carrierFds,
    jlongArray payloadOffsets,
    jlongArray extentLengths,
    jstring password,
    jint pim,
    jstring fileSystem,
    jint containerFormat,
    jint cipherId,
    jint hashId,
    jintArray keyfileFds,
    jboolean quickFormat,
    jstring operationId // Exactly 14 parameters, matching NativeEngine.kt
) {
    JNI_TRY
    auto carriers = parseCarrierTargets(env, carrierPaths, carrierFds);
    if (carriers.empty()) return JNI_FALSE;

    // 1. Sort carriers canonically
    CompositeMap::sortCanonical(carriers);

    // 2. Read the user-requested capacity from the sum of Java's extentLengths
    uint64_t requestedTotalBytes = 0;
    if (extentLengths) {
        jsize lenCount = env->GetArrayLength(extentLengths);
        if (lenCount > 0) {
            jlong* lens = env->GetLongArrayElements(extentLengths, nullptr);
            for (jsize i = 0; i < lenCount; ++i) {
                if (lens[i] > 0) requestedTotalBytes += static_cast<uint64_t>(lens[i]);
            }
            env->ReleaseLongArrayElements(extentLengths, lens, JNI_ABORT);
        }
    }

    // 3. Profile carriers and derive extents matching the requested capacity proportionally
    auto profile = CarrierProfiler::profileForAllocation(carriers, 10);
    auto extents = CompositeMap::deriveExtents(profile.perFile, requestedTotalBytes);
    if (extents.empty()) {
        LOGI("createCompositeContainerNative: derived 0 extents for %zu carriers", carriers.size());
        return JNI_FALSE;
    }

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const char* nativeFS = env->GetStringUTFChars(fileSystem, nullptr);
    const char* nativeOpId = operationId ? env->GetStringUTFChars(operationId, nullptr) : nullptr;
    std::vector<int> kf = extractKeyfileFds(env, keyfileFds);

    auto result = createCompositeContainer(
        volId, carriers, extents, nativePass, pim, nativeFS, containerFormat, cipherId, hashId,
        kf.empty() ? nullptr : kf.data(), static_cast<int>(kf.size()), quickFormat,
        nativeOpId ? nativeOpId : ""
    );

    env->ReleaseStringUTFChars(password, nativePass);
    env->ReleaseStringUTFChars(fileSystem, nativeFS);
    if (operationId && nativeOpId) env->ReleaseStringUTFChars(operationId, nativeOpId);

    return result.success ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}

// Builds the Map<String, Any?> handed back to Kotlin for a composite unlock
// attempt. Keys: "success" (Boolean); on success also "files" (ArrayList<String>,
// currently always empty -- the composite path doesn't pre-populate a root
// listing); on failure also "errorCode" (String) -- one of the codes documented
// on CompositeUnlockResult in container_create_composite.h, plus the
// bridge-local NO_CARRIERS / NO_EXTENTS_DETECTED / FILESYSTEM_MOUNT_FAILED for
// failures that happen before/after prepareCompositeSession runs.
static jobject buildCompositeUnlockResultMap(
    JNIEnv* env, bool success, const std::string& errorCode
) {
    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID mapInit = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(mapClass, "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jclass boolClass = env->FindClass("java/lang/Boolean");
    jmethodID boolInit = env->GetMethodID(boolClass, "<init>", "(Z)V");

    jobject result = env->NewObject(mapClass, mapInit);

    jstring kSuccess = env->NewStringUTF("success");
    jobject vSuccess = env->NewObject(boolClass, boolInit, static_cast<jboolean>(success));
    env->CallObjectMethod(result, mapPut, kSuccess, vSuccess);
    env->DeleteLocalRef(kSuccess);
    env->DeleteLocalRef(vSuccess);

    if (success) {
        jclass listClass = env->FindClass("java/util/ArrayList");
        jmethodID listInit = env->GetMethodID(listClass, "<init>", "()V");
        jstring kFiles = env->NewStringUTF("files");
        jobject vFiles = env->NewObject(listClass, listInit);
        env->CallObjectMethod(result, mapPut, kFiles, vFiles);
        env->DeleteLocalRef(kFiles);
        env->DeleteLocalRef(vFiles);
    } else {
        jstring kErr = env->NewStringUTF("errorCode");
        jstring vErr = env->NewStringUTF(errorCode.c_str());
        env->CallObjectMethod(result, mapPut, kErr, vErr);
        env->DeleteLocalRef(kErr);
        env->DeleteLocalRef(vErr);
    }
    return result;
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_unlockCompositeContainerNative(
    JNIEnv* env, jobject,
    jint volId,
    jobjectArray carrierPaths,
    jintArray carrierFds,
    jlongArray payloadOffsets,
    jlongArray extentLengths,
    jstring password,
    jint pim,
    jint cipherId,
    jint hashId,
    jintArray keyfileFds,
    jboolean readOnly
) {
    JNI_TRY

    clearUnlockCancellation(volId);
    
    auto carriers = parseCarrierTargets(env, carrierPaths, carrierFds);
    if (carriers.empty()) return buildCompositeUnlockResultMap(env, false, "NO_CARRIERS");

    // 1. Sort carriers into the identical canonical order
    CompositeMap::sortCanonical(carriers);

    // 2. Auto-detect extent boundaries using unique header-keyed blind trailers
    auto profile = CarrierProfiler::profileForRecovery(carriers);
    auto extents = CompositeMap::deriveExtents(profile.perFile);
    if (extents.empty()) {
        LOGI("unlockCompositeContainerNative: derived 0 extents for %zu carriers", carriers.size());
        return buildCompositeUnlockResultMap(env, false, "NO_EXTENTS_DETECTED");
    }

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    size_t passLen = nativePass ? std::strlen(nativePass) : 0;
    std::vector<int> kf = extractKeyfileFds(env, keyfileFds);

    CompositeUnlockResult unlockResult = prepareCompositeSession(
        volId, carriers, extents,
        reinterpret_cast<const unsigned char*>(nativePass), passLen,
        pim, cipherId, hashId,
        kf.empty() ? nullptr : kf.data(), static_cast<int>(kf.size()),
        readOnly == JNI_TRUE
    );

    env->ReleaseStringUTFChars(password, nativePass);
    if (!unlockResult.success) {
        LOGI("unlockCompositeContainerNative: prepareCompositeSession failed for volId=%d code=%s",
             volId, unlockResult.errorCode.c_str());
        return buildCompositeUnlockResultMap(env, false, unlockResult.errorCode);
    }

    bool mountOk = false;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        mountOk = ensureMounted(volId);
    }
    if (!mountOk) {
        LOGI("unlockCompositeContainerNative: filesystem mount failed for volId=%d", volId);
        return buildCompositeUnlockResultMap(env, false, "FILESYSTEM_MOUNT_FAILED");
    }

    return buildCompositeUnlockResultMap(env, true, "");
    JNI_CATCH_RETURN(nullptr)
}