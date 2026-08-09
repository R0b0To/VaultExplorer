#include <jni.h>
#include <cstring>
#include <vector>
#include <mutex>
#include "mbedtls/md.h"
#include "mbedtls/pkcs5.h"
#include "mbedtls/gcm.h"
#include "mbedtls/platform_util.h"
#include "crypto/cascade.h"
#include "crypto/vc_header_layout.h"
#include "crypto/keyfile_mixing.h"
#include "crypto/luks_header.h"
#include "crypto/cipher_shim.h"
#include "crypto/single_file_crypto.h"
#include "session_prepare.h"
#include "session_guard.h"
#include "volume_state.h"
#include "jni_bridge_common.h"
#include "jni_callbacks.h"
#include "crypto/scrypt.h"
#include "crypto/eme.h"
#include "crypto/siv.h"
#include "crypto/cryfs_block_cipher.h"
#include "crypto/xchacha20poly1305.h"
#undef min
#undef max

struct MdContextGuard {
    mbedtls_md_context_t ctx;
    MdContextGuard() { mbedtls_md_init(&ctx); }
    ~MdContextGuard() { mbedtls_md_free(&ctx); }
};

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_encryptSingleFileNative(
        JNIEnv* env, jobject,
        jint srcFd, jint destFd, jint cipherIndex,
        jstring password, jintArray keyfileFds, jint opId) {
    JNI_TRY
    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    size_t passLen = nativePass ? strlen(nativePass) : 0;

    auto cancelCheck = [opId]() -> bool {
        return isSplitJoinCancelled(opId);
    };
    auto progressCb = [opId](uint64_t done, uint64_t total) {
        reportSplitJoinProgress(opId, done, total);
    };

    bool ok = encryptSingleFile(
        srcFd, destFd, cipherIndex,
        reinterpret_cast<const unsigned char*>(nativePass), passLen,
        kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()),
        opId, cancelCheck, progressCb
    );

    if (nativePass) env->ReleaseStringUTFChars(password, nativePass);
    return ok ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_decryptSingleFileNative(
        JNIEnv* env, jobject,
        jint srcFd, jint destFd,
        jstring password, jintArray keyfileFds, jint opId) {
    JNI_TRY
    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    size_t passLen = nativePass ? strlen(nativePass) : 0;

    auto cancelCheck = [opId]() -> bool {
        return isSplitJoinCancelled(opId);
    };
    auto progressCb = [opId](uint64_t done, uint64_t total) {
        reportSplitJoinProgress(opId, done, total);
    };

    bool ok = decryptSingleFile(
        srcFd, destFd,
        reinterpret_cast<const unsigned char*>(nativePass), passLen,
        kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()),
        opId, cancelCheck, progressCb
    );

    if (nativePass) env->ReleaseStringUTFChars(password, nativePass);
    return ok ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getMaxVolumesNative(JNIEnv* env, jobject) {
    JNI_TRY
    return static_cast<jint>(MAX_VOLUMES);
    JNI_CATCH_RETURN(-1)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getLastDerivedKeyMaterialNative(
        JNIEnv* env, jobject, jint volId) {
    JNI_TRY
    if (volId < 0 || volId >= MAX_VOLUMES) return nullptr;
    VolumeState& v = volumes[volId];
    std::lock_guard<std::mutex> lock(v.mutex);
    if (v.preservedDerivedKey == nullptr || v.preservedDerivedKeyLen == 0) return nullptr;
    jbyteArray result = env->NewByteArray(static_cast<jsize>(v.preservedDerivedKeyLen));
    env->SetByteArrayRegion(result, 0, static_cast<jsize>(v.preservedDerivedKeyLen),
                            reinterpret_cast<const jbyte*>(v.preservedDerivedKey));
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_deriveKeyMaterialNative(
        JNIEnv* env, jobject,
        jint fd, jstring password, jint pim, jint cipherId, jint hashId, jintArray keyfileFds) {
    JNI_TRY
    if (fd < 0 || password == nullptr) return nullptr;
    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    unsigned char headerBuf[VC_FULL_HEADER_SIZE];
    if (pread(fd, headerBuf, VC_FULL_HEADER_SIZE, 0) != VC_FULL_HEADER_SIZE) {
        env->ReleaseStringUTFChars(password, nativePass);
        closeUnusedKeyfileFds(kfFds.data(), static_cast<int>(kfFds.size()));
        return nullptr;
    }
    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = std::min(strlen(nativePass), sizeof(mixedPassword));
    memcpy(mixedPassword, nativePass, mixedPasswordLen);
    env->ReleaseStringUTFChars(password, nativePass);
    if (!kfFds.empty() && !applyKeyfilesToPassword(kfFds.data(), static_cast<int>(kfFds.size()), mixedPassword, &mixedPasswordLen)) {
        return nullptr;
    }
    unsigned char dKey[192];
    unsigned char dummyDecH[VC_HEADER_BODY_SIZE];
    CascadeId matchedCipher{};
    HashId matchedHash{};
    ParsedHeaderFields fields;
    const bool ok = deriveAndValidateHeader(
        headerBuf,
        mixedPassword,
        mixedPasswordLen,
        pim,
        cipherId,
        hashId,
        dKey,
        dummyDecH,
        matchedCipher,
        matchedHash,
        fields
    );
    if (!ok) return nullptr;
    jbyteArray result = env->NewByteArray(192);
    env->SetByteArrayRegion(result, 0, 192, reinterpret_cast<jbyte*>(dKey));
    mbedtls_platform_zeroize(dKey, sizeof(dKey));
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_hashPasswordNative(
        JNIEnv* env, jobject,
        jstring password, jbyteArray salt, jint iterations) {
    JNI_TRY
    if (password == nullptr || salt == nullptr) return nullptr;
    const jsize saltLen = env->GetArrayLength(salt);
    if (saltLen == 0) return nullptr;
    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    jbyte* saltData        = env->GetByteArrayElements(salt, nullptr);
    unsigned char out[64] = {0};
    jbyteArray result     = nullptr;
    const unsigned int safeIter =
        (iterations > 0) ? static_cast<unsigned int>(iterations) : 200000u;
    MdContextGuard mdGuard;
    if (mbedtls_md_setup(&mdGuard.ctx,
            mbedtls_md_info_from_type(MBEDTLS_MD_SHA512), 1) == 0) {
        int rc = mbedtls_pkcs5_pbkdf2_hmac(
            &mdGuard.ctx,
            reinterpret_cast<const unsigned char*>(nativePass), strlen(nativePass),
            reinterpret_cast<const unsigned char*>(saltData), static_cast<size_t>(saltLen),
            safeIter, 64, out);
        if (rc == 0) {
            result = env->NewByteArray(64);
            env->SetByteArrayRegion(result, 0, 64, reinterpret_cast<jbyte*>(out));
        } else {
            LOGI("hashPasswordNative: PBKDF2 failed, rc=%d", rc);
        }
    }
    mbedtls_platform_zeroize(out, sizeof(out));
    env->ReleaseStringUTFChars(password, nativePass);
    env->ReleaseByteArrayElements(salt, saltData, JNI_ABORT);
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getCascadeFingerprint(
        JNIEnv* env, jobject, jint cascadeId) {
    JNI_TRY
    if (cascadeId < 0 || cascadeId >= 15) return -1;
    CascadeSpec spec = cascadeSpecFor(static_cast<CascadeId>(cascadeId));
    int packed = spec.layerCount * 1000;
    for (int i = 0; i < 3; i++) {
        int layerVal = (i < spec.layerCount) ? static_cast<int>(spec.layers[i]) : 9;
        packed += layerVal * (i == 0 ? 100 : (i == 1 ? 10 : 1));
    }
    return packed;
    JNI_CATCH_RETURN(-1)
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getCascadeIdCount(JNIEnv* env, jobject) {
    JNI_TRY
    return 15;
    JNI_CATCH_RETURN(-1)
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getHashIdCount(JNIEnv* env, jobject) {
    JNI_TRY
    return 6;
    JNI_CATCH_RETURN(-1)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_gocryptfsEmeNative(
        JNIEnv* env, jobject,
        jbyteArray key, jbyteArray tweak, jbyteArray data, jboolean encrypt) {
    JNI_TRY
    if (!key || !tweak || !data) return nullptr;
    jsize keyLen = env->GetArrayLength(key);
    jsize tweakLen = env->GetArrayLength(tweak);
    jsize dataLen = env->GetArrayLength(data);
    if (tweakLen != 16 || dataLen == 0 || dataLen % 16 != 0) return nullptr;
    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* tweakData = env->GetByteArrayElements(tweak, nullptr);
    jbyte* inData = env->GetByteArrayElements(data, nullptr);
    std::vector<uint8_t> out(dataLen);
    bool ok = eme_transform(
        reinterpret_cast<const uint8_t*>(keyData), static_cast<size_t>(keyLen),
        reinterpret_cast<const uint8_t*>(tweakData),
        reinterpret_cast<const uint8_t*>(inData),
        out.data(), static_cast<size_t>(dataLen),
        encrypt == JNI_TRUE
    );
    env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);
    env->ReleaseByteArrayElements(tweak, tweakData, JNI_ABORT);
    env->ReleaseByteArrayElements(data, inData, JNI_ABORT);
    if (!ok) return nullptr;
    jbyteArray result = env->NewByteArray(dataLen);
    env->SetByteArrayRegion(result, 0, dataLen, reinterpret_cast<const jbyte*>(out.data()));
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_sivEncryptNative(
        JNIEnv* env, jobject,
        jbyteArray encKey, jbyteArray macKey, jbyteArray plaintext, jobjectArray adArray) {
    JNI_TRY
    if (!encKey || !macKey || !plaintext) return nullptr;
    jsize encKeyLen = env->GetArrayLength(encKey);
    jsize macKeyLen = env->GetArrayLength(macKey);
    jsize ptLen = env->GetArrayLength(plaintext);
    jbyte* encKeyData = env->GetByteArrayElements(encKey, nullptr);
    jbyte* macKeyData = env->GetByteArrayElements(macKey, nullptr);
    jbyte* ptData = env->GetByteArrayElements(plaintext, nullptr);
    std::vector<std::vector<uint8_t>> adList;
    if (adArray) {
        jsize adCount = env->GetArrayLength(adArray);
        for (jsize i = 0; i < adCount; i++) {
            jbyteArray adElem = static_cast<jbyteArray>(env->GetObjectArrayElement(adArray, i));
            if (adElem) {
                jsize len = env->GetArrayLength(adElem);
                jbyte* bytes = env->GetByteArrayElements(adElem, nullptr);
                adList.push_back(std::vector<uint8_t>(bytes, bytes + len));
                env->ReleaseByteArrayElements(adElem, bytes, JNI_ABORT);
                env->DeleteLocalRef(adElem);
            }
        }
    }
    std::vector<uint8_t> out(16 + ptLen);
    bool ok = siv_encrypt(
        reinterpret_cast<const uint8_t*>(encKeyData), static_cast<size_t>(encKeyLen),
        reinterpret_cast<const uint8_t*>(macKeyData), static_cast<size_t>(macKeyLen),
        reinterpret_cast<const uint8_t*>(ptData), static_cast<size_t>(ptLen),
        adList, out.data(), out.size()
    );
    env->ReleaseByteArrayElements(encKey, encKeyData, JNI_ABORT);
    env->ReleaseByteArrayElements(macKey, macKeyData, JNI_ABORT);
    env->ReleaseByteArrayElements(plaintext, ptData, JNI_ABORT);
    if (!ok) return nullptr;
    jbyteArray result = env->NewByteArray(out.size());
    env->SetByteArrayRegion(result, 0, out.size(), reinterpret_cast<const jbyte*>(out.data()));
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_sivDecryptNative(
        JNIEnv* env, jobject,
        jbyteArray encKey, jbyteArray macKey, jbyteArray ciphertext, jobjectArray adArray) {
    JNI_TRY
    if (!encKey || !macKey || !ciphertext) return nullptr;
    jsize encKeyLen = env->GetArrayLength(encKey);
    jsize macKeyLen = env->GetArrayLength(macKey);
    jsize ctLen = env->GetArrayLength(ciphertext);
    if (ctLen < 16) return nullptr;
    jbyte* encKeyData = env->GetByteArrayElements(encKey, nullptr);
    jbyte* macKeyData = env->GetByteArrayElements(macKey, nullptr);
    jbyte* ctData = env->GetByteArrayElements(ciphertext, nullptr);
    std::vector<std::vector<uint8_t>> adList;
    if (adArray) {
        jsize adCount = env->GetArrayLength(adArray);
        for (jsize i = 0; i < adCount; i++) {
            jbyteArray adElem = static_cast<jbyteArray>(env->GetObjectArrayElement(adArray, i));
            if (adElem) {
                jsize len = env->GetArrayLength(adElem);
                jbyte* bytes = env->GetByteArrayElements(adElem, nullptr);
                adList.push_back(std::vector<uint8_t>(bytes, bytes + len));
                env->ReleaseByteArrayElements(adElem, bytes, JNI_ABORT);
                env->DeleteLocalRef(adElem);
            }
        }
    }
    std::vector<uint8_t> out(ctLen - 16);
    bool ok = siv_decrypt(
        reinterpret_cast<const uint8_t*>(encKeyData), static_cast<size_t>(encKeyLen),
        reinterpret_cast<const uint8_t*>(macKeyData), static_cast<size_t>(macKeyLen),
        reinterpret_cast<const uint8_t*>(ctData), static_cast<size_t>(ctLen),
        adList, out.data(), out.size()
    );
    env->ReleaseByteArrayElements(encKey, encKeyData, JNI_ABORT);
    env->ReleaseByteArrayElements(macKey, macKeyData, JNI_ABORT);
    env->ReleaseByteArrayElements(ciphertext, ctData, JNI_ABORT);
    if (!ok) return nullptr;
    jbyteArray result = env->NewByteArray(out.size());
    env->SetByteArrayRegion(result, 0, out.size(), reinterpret_cast<const jbyte*>(out.data()));
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_scryptNative(
        JNIEnv* env, jobject,
        jbyteArray passphrase, jbyteArray salt, jint N, jint r, jint p, jint dkLen) {
    JNI_TRY
    if (passphrase == nullptr || salt == nullptr || dkLen <= 0) return nullptr;
    jsize pwLen = env->GetArrayLength(passphrase);
    jsize saltLen = env->GetArrayLength(salt);
    jbyte* pwData = env->GetByteArrayElements(passphrase, nullptr);
    jbyte* saltData = env->GetByteArrayElements(salt, nullptr);
    std::vector<uint8_t> out(static_cast<size_t>(dkLen));
    bool ok = scrypt_crypto(
        reinterpret_cast<const uint8_t*>(pwData), static_cast<size_t>(pwLen),
        reinterpret_cast<const uint8_t*>(saltData), static_cast<size_t>(saltLen),
        static_cast<uint32_t>(N), static_cast<uint32_t>(r), static_cast<uint32_t>(p),
        out.data(), static_cast<size_t>(dkLen)
    );
    env->ReleaseByteArrayElements(passphrase, pwData, JNI_ABORT);
    env->ReleaseByteArrayElements(salt, saltData, JNI_ABORT);
    if (!ok) return nullptr;
    jbyteArray result = env->NewByteArray(dkLen);
    env->SetByteArrayRegion(result, 0, dkLen, reinterpret_cast<const jbyte*>(out.data()));
    mbedtls_platform_zeroize(out.data(), out.size());
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_cryfsCipherIdNative(
        JNIEnv* env, jobject, jstring cipherName) {
    JNI_TRY
    if (!cipherName) return -1;
    const char* name = env->GetStringUTFChars(cipherName, nullptr);
    CryfsCipherId id = cryfsCipherIdFromName(name);
    env->ReleaseStringUTFChars(cipherName, name);
    if (id == CryfsCipherId::kUnknown) return -1;
    return static_cast<jint>(id);
    JNI_CATCH_RETURN(-1)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_cryfsEncryptBlockNative(
        JNIEnv* env, jobject,
        jint cipherId, jbyteArray key, jbyteArray plaintext) {
    JNI_TRY
    if (!key || !plaintext || cipherId < 0) return nullptr;
    jsize keyLen = env->GetArrayLength(key);
    jsize ptLen = env->GetArrayLength(plaintext);
    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* ptData = ptLen > 0 ? env->GetByteArrayElements(plaintext, nullptr) : nullptr;
    std::vector<uint8_t> out = cryfsBlockEncrypt(
        static_cast<CryfsCipherId>(cipherId),
        reinterpret_cast<const uint8_t*>(keyData), static_cast<size_t>(keyLen),
        reinterpret_cast<const uint8_t*>(ptData), static_cast<size_t>(ptLen)
    );
    env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);
    if (ptData) env->ReleaseByteArrayElements(plaintext, ptData, JNI_ABORT);
    if (out.empty() && ptLen != 0) return nullptr;
    jbyteArray result = env->NewByteArray(out.size());
    if (!out.empty()) {
        env->SetByteArrayRegion(result, 0, out.size(), reinterpret_cast<const jbyte*>(out.data()));
    }
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_cryfsDecryptBlockNative(
        JNIEnv* env, jobject,
        jint cipherId, jbyteArray key, jbyteArray ciphertext) {
    JNI_TRY
    if (!key || !ciphertext || cipherId < 0) return nullptr;
    jsize keyLen = env->GetArrayLength(key);
    jsize ctLen = env->GetArrayLength(ciphertext);
    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* ctData = env->GetByteArrayElements(ciphertext, nullptr);
    std::vector<uint8_t> out;
    bool ok = cryfsBlockDecrypt(
        static_cast<CryfsCipherId>(cipherId),
        reinterpret_cast<const uint8_t*>(keyData), static_cast<size_t>(keyLen),
        reinterpret_cast<const uint8_t*>(ctData), static_cast<size_t>(ctLen),
        out
    );
    env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);
    env->ReleaseByteArrayElements(ciphertext, ctData, JNI_ABORT);
    if (!ok) return nullptr;
    jbyteArray result = env->NewByteArray(out.size());
    if (!out.empty()) {
        env->SetByteArrayRegion(result, 0, out.size(), reinterpret_cast<const jbyte*>(out.data()));
    }
    mbedtls_platform_zeroize(out.data(), out.size());
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_hashPasswordSha256Native(
        JNIEnv* env, jobject,
        jstring password, jbyteArray salt, jint iterations, jint outputLen) {
    JNI_TRY
    if (password == nullptr || salt == nullptr || outputLen <= 0) return nullptr;
    const jsize saltLen = env->GetArrayLength(salt);
    if (saltLen == 0) return nullptr;
    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    jbyte* saltData        = env->GetByteArrayElements(salt, nullptr);
    const unsigned int safeIter =
        (iterations > 0) ? static_cast<unsigned int>(iterations) : 50000u;
    std::vector<unsigned char> out(static_cast<size_t>(outputLen), 0);
    bool ok = pbkdf2Hmac(
        HashId::kSha256,
        reinterpret_cast<const unsigned char*>(nativePass), strlen(nativePass),
        reinterpret_cast<const unsigned char*>(saltData), static_cast<size_t>(saltLen),
        safeIter, out.data(), out.size());
    env->ReleaseStringUTFChars(password, nativePass);
    env->ReleaseByteArrayElements(salt, saltData, JNI_ABORT);
    if (!ok) return nullptr;
    jbyteArray result = env->NewByteArray(static_cast<jsize>(out.size()));
    env->SetByteArrayRegion(result, 0, static_cast<jsize>(out.size()), reinterpret_cast<jbyte*>(out.data()));
    mbedtls_platform_zeroize(out.data(), out.size());
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_aesGcmEncryptNative(
        JNIEnv* env, jobject,
        jbyteArray key, jbyteArray iv, jbyteArray plaintext) {
    JNI_TRY
    if (!key || !iv || !plaintext) return nullptr;
    jsize keyLen = env->GetArrayLength(key);
    jsize ivLen = env->GetArrayLength(iv);
    jsize ptLen = env->GetArrayLength(plaintext);
    if (keyLen != 16 && keyLen != 24 && keyLen != 32) return nullptr;
    if (ivLen == 0) return nullptr;
    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* ivData = env->GetByteArrayElements(iv, nullptr);
    jbyte* ptData = ptLen > 0 ? env->GetByteArrayElements(plaintext, nullptr) : nullptr;
    constexpr size_t tagLen = 16;
    std::vector<uint8_t> out(static_cast<size_t>(ptLen) + tagLen);
    mbedtls_gcm_context ctx;
    mbedtls_gcm_init(&ctx);
    bool ok = mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES,
                                 reinterpret_cast<const unsigned char*>(keyData),
                                 static_cast<unsigned int>(keyLen * 8)) == 0;
    if (ok) {
        ok = mbedtls_gcm_crypt_and_tag(
            &ctx, MBEDTLS_GCM_ENCRYPT, static_cast<size_t>(ptLen),
            reinterpret_cast<const unsigned char*>(ivData), static_cast<size_t>(ivLen),
            nullptr, 0,
            reinterpret_cast<const unsigned char*>(ptData), out.data(),
            tagLen, out.data() + ptLen) == 0;
    }
    mbedtls_gcm_free(&ctx);
    env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);
    env->ReleaseByteArrayElements(iv, ivData, JNI_ABORT);
    if (ptData) env->ReleaseByteArrayElements(plaintext, ptData, JNI_ABORT);
    if (!ok) return nullptr;
    jbyteArray result = env->NewByteArray(static_cast<jsize>(out.size()));
    env->SetByteArrayRegion(result, 0, static_cast<jsize>(out.size()), reinterpret_cast<const jbyte*>(out.data()));
    mbedtls_platform_zeroize(out.data(), out.size());
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_aesGcmDecryptNative(
        JNIEnv* env, jobject,
        jbyteArray key, jbyteArray iv, jbyteArray ciphertextAndTag) {
    JNI_TRY
    if (!key || !iv || !ciphertextAndTag) return nullptr;
    jsize keyLen = env->GetArrayLength(key);
    jsize ivLen = env->GetArrayLength(iv);
    jsize ctLen = env->GetArrayLength(ciphertextAndTag);
    constexpr size_t tagLen = 16;
    if (ctLen < static_cast<jsize>(tagLen)) return nullptr;
    if (keyLen != 16 && keyLen != 24 && keyLen != 32) return nullptr;
    if (ivLen == 0) return nullptr;
    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* ivData = env->GetByteArrayElements(iv, nullptr);
    jbyte* ctData = env->GetByteArrayElements(ciphertextAndTag, nullptr);
    const size_t ptLen = static_cast<size_t>(ctLen) - tagLen;
    std::vector<uint8_t> out(ptLen);
    const unsigned char* tagPtr = reinterpret_cast<const unsigned char*>(ctData) + ptLen;
    mbedtls_gcm_context ctx;
    mbedtls_gcm_init(&ctx);
    bool ok = mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES,
                                 reinterpret_cast<const unsigned char*>(keyData),
                                 static_cast<unsigned int>(keyLen * 8)) == 0;
    if (ok) {
        ok = mbedtls_gcm_auth_decrypt(
            &ctx, ptLen,
            reinterpret_cast<const unsigned char*>(ivData), static_cast<size_t>(ivLen),
            nullptr, 0,
            tagPtr, tagLen,
            reinterpret_cast<const unsigned char*>(ctData), out.data()) == 0;
    }
    mbedtls_gcm_free(&ctx);
    env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);
    env->ReleaseByteArrayElements(iv, ivData, JNI_ABORT);
    env->ReleaseByteArrayElements(ciphertextAndTag, ctData, JNI_ABORT);
    if (!ok) {
        mbedtls_platform_zeroize(out.data(), out.size());
        return nullptr;
    }
    jbyteArray result = env->NewByteArray(static_cast<jsize>(out.size()));
    if (ptLen > 0) {
        env->SetByteArrayRegion(result, 0, static_cast<jsize>(out.size()), reinterpret_cast<const jbyte*>(out.data()));
    }
    mbedtls_platform_zeroize(out.data(), out.size());
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_xchacha20Poly1305SealNative(
        JNIEnv* env, jobject,
        jbyteArray key, jbyteArray nonce, jbyteArray aad, jbyteArray plaintext) {
    JNI_TRY
    if (!key || !nonce || !plaintext) return nullptr;
    if (env->GetArrayLength(key) != 32 || env->GetArrayLength(nonce) != 24) return nullptr;
    jsize ptLen = env->GetArrayLength(plaintext);
    jsize aadLen = aad ? env->GetArrayLength(aad) : 0;
    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* nonceData = env->GetByteArrayElements(nonce, nullptr);
    jbyte* aadData = aad ? env->GetByteArrayElements(aad, nullptr) : nullptr;
    jbyte* ptData = env->GetByteArrayElements(plaintext, nullptr);
    std::vector<uint8_t> out(static_cast<size_t>(ptLen) + 16);
    bool ok = xchacha20Poly1305Seal(
        reinterpret_cast<const uint8_t*>(keyData),
        reinterpret_cast<const uint8_t*>(nonceData),
        aadData ? reinterpret_cast<const uint8_t*>(aadData) : nullptr, static_cast<size_t>(aadLen),
        reinterpret_cast<const uint8_t*>(ptData), static_cast<size_t>(ptLen),
        out.data());
    env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);
    env->ReleaseByteArrayElements(nonce, nonceData, JNI_ABORT);
    if (aadData) env->ReleaseByteArrayElements(aad, aadData, JNI_ABORT);
    env->ReleaseByteArrayElements(plaintext, ptData, JNI_ABORT);
    if (!ok) {
        mbedtls_platform_zeroize(out.data(), out.size());
        return nullptr;
    }
    jbyteArray result = env->NewByteArray(static_cast<jsize>(out.size()));
    env->SetByteArrayRegion(result, 0, static_cast<jsize>(out.size()), reinterpret_cast<const jbyte*>(out.data()));
    mbedtls_platform_zeroize(out.data(), out.size());
    return result;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_xchacha20Poly1305OpenNative(
        JNIEnv* env, jobject,
        jbyteArray key, jbyteArray nonce, jbyteArray aad, jbyteArray ciphertextAndTag) {
    JNI_TRY
    if (!key || !nonce || !ciphertextAndTag) return nullptr;
    if (env->GetArrayLength(key) != 32 || env->GetArrayLength(nonce) != 24) return nullptr;
    constexpr size_t tagLen = 16;
    jsize ctLen = env->GetArrayLength(ciphertextAndTag);
    if (ctLen < static_cast<jsize>(tagLen)) return nullptr;
    jsize aadLen = aad ? env->GetArrayLength(aad) : 0;
    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* nonceData = env->GetByteArrayElements(nonce, nullptr);
    jbyte* aadData = aad ? env->GetByteArrayElements(aad, nullptr) : nullptr;
    jbyte* ctData = env->GetByteArrayElements(ciphertextAndTag, nullptr);
    const size_t bodyLen = static_cast<size_t>(ctLen) - tagLen;
    const unsigned char* tagPtr = reinterpret_cast<const unsigned char*>(ctData) + bodyLen;
    std::vector<uint8_t> out(bodyLen);
    bool ok = xchacha20Poly1305Open(
        reinterpret_cast<const uint8_t*>(keyData),
        reinterpret_cast<const uint8_t*>(nonceData),
        aadData ? reinterpret_cast<const uint8_t*>(aadData) : nullptr, static_cast<size_t>(aadLen),
        reinterpret_cast<const uint8_t*>(ctData), bodyLen,
        reinterpret_cast<const uint8_t*>(tagPtr),
        out.data());
    env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);
    env->ReleaseByteArrayElements(nonce, nonceData, JNI_ABORT);
    if (aadData) env->ReleaseByteArrayElements(aad, aadData, JNI_ABORT);
    env->ReleaseByteArrayElements(ciphertextAndTag, ctData, JNI_ABORT);
    if (!ok) {
        mbedtls_platform_zeroize(out.data(), out.size());
        return nullptr;
    }
    jbyteArray result = env->NewByteArray(static_cast<jsize>(out.size()));
    if (bodyLen > 0) {
        env->SetByteArrayRegion(result, 0, static_cast<jsize>(out.size()), reinterpret_cast<const jbyte*>(out.data()));
    }
    mbedtls_platform_zeroize(out.data(), out.size());
    return result;
    JNI_CATCH_RETURN(nullptr)
}