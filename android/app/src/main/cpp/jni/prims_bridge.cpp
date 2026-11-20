// JNI bridge for crypto/prims (the platform-neutral HMAC / AES-CBC / ... primitives).
//
// Kotlin side: com.aeidolon.vaultexplorer.crypto.NativePrims. It replaces the JCA calls behind the
// `hmac` and `aesCbcDecrypt` platform-channel methods, so Android and a desktop front-end run the
// same code for TOTP codes, authenticator-backup imports and Bitwarden's MAC check.
//
// Inputs are COPIED into local buffers and the copies wiped -- the Java arrays are never zeroed in
// place. That matters: Kotlin falls back to JCA when a native call returns null, and a fallback that
// finds its key already wiped would fail (or worse, compute something else) instead of failing cleanly.
#include <jni.h>
#include <android/log.h>

#include <string>
#include <vector>

#include "mbedtls/platform_util.h"

#include "jni_bridge_common.h"
#include "jni_utf8.h"
#include "crypto/prims.h"

namespace {

// A byte[] copied out of the JVM, wiped on destruction.
struct Secret {
    std::vector<uint8_t> v;
    bool ok = true;
    Secret(JNIEnv* env, jbyteArray a) {
        if (!a) {
            ok = false;
            return;
        }
        const jsize n = env->GetArrayLength(a);
        v.resize(static_cast<size_t>(n));
        if (n > 0) env->GetByteArrayRegion(a, 0, n, reinterpret_cast<jbyte*>(v.data()));
        if (env->ExceptionCheck()) ok = false;
    }
    ~Secret() {
        if (!v.empty()) mbedtls_platform_zeroize(v.data(), v.size());
    }
    const uint8_t* data() const { return v.empty() ? nullptr : v.data(); }
    size_t size() const { return v.size(); }
};

// The result as a new byte[]; the native copy is wiped.
jbyteArray toJava(JNIEnv* env, prims::Bytes& b) {
    jbyteArray r = env->NewByteArray(static_cast<jsize>(b.size()));
    if (r && !b.empty()) env->SetByteArrayRegion(r, 0, static_cast<jsize>(b.size()), reinterpret_cast<const jbyte*>(b.data()));
    if (!b.empty()) mbedtls_platform_zeroize(b.data(), b.size());
    return r;
}

}  // namespace

#define VP_JNI(ret, name) extern "C" JNIEXPORT ret JNICALL Java_com_aeidolon_vaultexplorer_crypto_NativePrims_##name

// Probe for NativePrims.isAvailable: resolves the library, does nothing else.
VP_JNI(void, nativeInit)(JNIEnv*, jclass) {}

// HMAC of `data` under `key`; `hash` is "sha1" | "sha256" | "sha512". Null for anything the
// primitive rejects (unknown hash, empty key), which sends Kotlin to its JCA path.
VP_JNI(jbyteArray, nativeHmac)(JNIEnv* env, jclass, jstring hash, jbyteArray key, jbyteArray data) {
    JNI_TRY
    prims::Hash h;
    if (!hash || !prims::parseHash(jniStringToUtf8(env, hash), h)) return nullptr;
    Secret k(env, key), d(env, data);
    if (!k.ok || !d.ok) return nullptr;
    prims::Bytes mac;
    if (!prims::hmac(h, k.data(), k.size(), d.data(), d.size(), mac)) return nullptr;
    return toJava(env, mac);
    JNI_CATCH_RETURN(nullptr)
}

// AES-CBC / PKCS#7 decryption. Null on any failure (bad key or IV length, length not a multiple of
// 16, bad padding): Kotlin then runs the JCA path, which raises the exception callers expect.
VP_JNI(jbyteArray, nativeAesCbcDecrypt)(JNIEnv* env, jclass, jbyteArray key, jbyteArray iv, jbyteArray ciphertext) {
    JNI_TRY
    Secret k(env, key), v(env, iv), c(env, ciphertext);
    if (!k.ok || !v.ok || !c.ok) return nullptr;
    prims::Bytes pt;
    if (!prims::aesCbcDecrypt(k.data(), k.size(), v.data(), v.size(), c.data(), c.size(), pt)) return nullptr;
    return toJava(env, pt);
    JNI_CATCH_RETURN(nullptr)
}
