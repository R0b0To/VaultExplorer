#include "jni_bridge_common.h"

#include <cstdint>
#include "mbedtls/platform_util.h"

std::vector<int> extractKeyfileFds(JNIEnv* env, jintArray arr) {
    std::vector<int> fds;
    if (!arr) return fds;
    jsize len = env->GetArrayLength(arr);
    if (len <= 0) return fds;
    jint* elems = env->GetIntArrayElements(arr, nullptr);
    if (!elems) return fds;
    fds.assign(elems, elems + len);
    env->ReleaseIntArrayElements(arr, elems, JNI_ABORT); // read-only access, nothing to copy back
    return fds;
}

ScopedJniUserEntropy::ScopedJniUserEntropy(JNIEnv* env, jbyteArray entropy) {
    if (!entropy) return;
    jsize len = env->GetArrayLength(entropy);
    if (len <= 0) return;
    std::vector<uint8_t> copy(static_cast<size_t>(len));
    env->GetByteArrayRegion(entropy, 0, len, reinterpret_cast<jbyte*>(copy.data()));
    if (env->ExceptionCheck()) {
        // A failed region copy leaves a pending Java exception; clear it and
        // carry on without the extra entropy (urandom alone is still fine).
        env->ExceptionClear();
        mbedtls_platform_zeroize(copy.data(), copy.size());
        return;
    }
    scope_ = std::make_unique<userentropy::Scope>(copy.data(), copy.size());
    mbedtls_platform_zeroize(copy.data(), copy.size());
}

ScopedJniUserEntropy::~ScopedJniUserEntropy() = default;
