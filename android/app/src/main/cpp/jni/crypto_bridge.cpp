#include <jni.h>
#include <cstring>
#include <vector>
#include <mutex>
#include <thread>
#include <future>
#include <memory>
#include <openssl/aead.h>
#include <openssl/evp.h>
#include "mbedtls/md.h"
#include "mbedtls/pkcs5.h"
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

// -------------------------------------------------------------------------
// BORINGSSL WRAPPER FOR CIPHER-AGNOSTIC GCM / XCHACHA20 SUPPORT
// -------------------------------------------------------------------------

class CryptoContext {
public:
    virtual ~CryptoContext() {}
    virtual bool seal(const uint8_t* nonce, size_t nonceLen, const uint8_t* pt, size_t ptLen, const uint8_t* aad, size_t aadLen, uint8_t* out, size_t* outLen) = 0;
    virtual bool open(const uint8_t* nonce, size_t nonceLen, const uint8_t* ct, size_t ctLen, const uint8_t* aad, size_t aadLen, uint8_t* out, size_t* outLen) = 0;
};

class AeadContext : public CryptoContext {
    EVP_AEAD_CTX ctx;
    bool valid = false;
public:
    AeadContext(const EVP_AEAD* aead, const uint8_t* key, size_t keyLen) {
        valid = (EVP_AEAD_CTX_init(&ctx, aead, key, keyLen, 16, nullptr) == 1);
    }
    ~AeadContext() override { if (valid) EVP_AEAD_CTX_cleanup(&ctx); }
    bool isValid() const { return valid; }

    bool seal(const uint8_t* nonce, size_t nonceLen, const uint8_t* pt, size_t ptLen, const uint8_t* aad, size_t aadLen, uint8_t* out, size_t* outLen) override {
        return EVP_AEAD_CTX_seal(&ctx, out, outLen, ptLen + 16, nonce, nonceLen, pt, ptLen, aad, aadLen) == 1;
    }
    bool open(const uint8_t* nonce, size_t nonceLen, const uint8_t* ct, size_t ctLen, const uint8_t* aad, size_t aadLen, uint8_t* out, size_t* outLen) override {
        return EVP_AEAD_CTX_open(&ctx, out, outLen, ctLen, nonce, nonceLen, ct, ctLen, aad, aadLen) == 1;
    }
};

class CipherContext : public CryptoContext {
    EVP_CIPHER_CTX* ctx;
    const EVP_CIPHER* cipher;
    const uint8_t* key;
    size_t keyLen;
public:
    CipherContext(const EVP_CIPHER* cipher, const uint8_t* key, size_t keyLen) 
        : cipher(cipher), key(key), keyLen(keyLen) {
        ctx = EVP_CIPHER_CTX_new();
    }
    ~CipherContext() override { if (ctx) EVP_CIPHER_CTX_free(ctx); }

    bool seal(const uint8_t* nonce, size_t nonceLen, const uint8_t* pt, size_t ptLen, const uint8_t* aad, size_t aadLen, uint8_t* out, size_t* outLen) override {
        int len = 0;
        bool ok = EVP_EncryptInit_ex(ctx, cipher, nullptr, nullptr, nullptr) == 1 &&
                  EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_IVLEN, nonceLen, nullptr) == 1 &&
                  EVP_EncryptInit_ex(ctx, nullptr, nullptr, key, nonce) == 1;

        if (ok && aad && aadLen > 0) ok = EVP_EncryptUpdate(ctx, nullptr, &len, aad, aadLen) == 1;
        if (ok && pt && ptLen > 0) {
            ok = EVP_EncryptUpdate(ctx, out, &len, pt, ptLen) == 1;
            *outLen = len;
        } else if (ok) *outLen = 0;

        if (ok) {
            ok = EVP_EncryptFinal_ex(ctx, out + *outLen, &len) == 1;
            *outLen += len;
        }
        if (ok) {
            ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_GET_TAG, 16, out + *outLen) == 1;
            *outLen += 16;
        }
        return ok;
    }

    bool open(const uint8_t* nonce, size_t nonceLen, const uint8_t* ctAndTag, size_t ctLen, const uint8_t* aad, size_t aadLen, uint8_t* out, size_t* outLen) override {
        if (ctLen < 16) return false;
        size_t ptLenExpected = ctLen - 16;
        int len = 0;
        
        bool ok = EVP_DecryptInit_ex(ctx, cipher, nullptr, nullptr, nullptr) == 1 &&
                  EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_IVLEN, nonceLen, nullptr) == 1 &&
                  EVP_DecryptInit_ex(ctx, nullptr, nullptr, key, nonce) == 1;

        if (ok && aad && aadLen > 0) ok = EVP_DecryptUpdate(ctx, nullptr, &len, aad, aadLen) == 1;
        if (ok && ptLenExpected > 0) {
            ok = EVP_DecryptUpdate(ctx, out, &len, ctAndTag, ptLenExpected) == 1;
            *outLen = len;
        } else if (ok) *outLen = 0;

        if (ok) {
            void* tagPtr = const_cast<void*>(reinterpret_cast<const void*>(ctAndTag + ptLenExpected));
            ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_TAG, 16, tagPtr) == 1;
        }
        if (ok) {
            ok = EVP_DecryptFinal_ex(ctx, out + *outLen, &len) == 1;
            *outLen += len;
        }
        return ok;
    }
};

static std::unique_ptr<CryptoContext> createCryptoContext(jsize keyLen, jint nonceLen, const uint8_t* key) {
    if (keyLen == 32 && nonceLen == 24) {
        auto ctx = std::make_unique<AeadContext>(EVP_aead_xchacha20_poly1305(), key, keyLen);
        if (ctx->isValid()) return ctx;
        return nullptr;
    }
    if (keyLen == 16) return std::make_unique<CipherContext>(EVP_aes_128_gcm(), key, keyLen);
    if (keyLen == 32) return std::make_unique<CipherContext>(EVP_aes_256_gcm(), key, keyLen);
    return nullptr;
}


// -------------------------------------------------------------------------
// ORIGINAL JNI METHODS
// -------------------------------------------------------------------------

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

// -------------------------------------------------------------------------
// FAST STREAM AND CHUNK JNI METHODS (MULTI-THREADED SUPPORT)
// -------------------------------------------------------------------------

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_aesGcmEncryptStreamNative(
        JNIEnv* env, jobject,
        jbyteArray key, jint nonceLen, jint cleartextChunkSize,
        jbyteArray fileIdOrHeaderNonce, jlong startChunkNumber, jbyteArray inputBuffer) {
    JNI_TRY
    if (!key || !fileIdOrHeaderNonce || !inputBuffer || nonceLen <= 0 || cleartextChunkSize <= 0) return nullptr;
    jsize keyLen = env->GetArrayLength(key);
    jsize idLen = env->GetArrayLength(fileIdOrHeaderNonce);
    jsize inLen = env->GetArrayLength(inputBuffer);
    if (inLen == 0) return nullptr;

    constexpr size_t tagLen = 16;
    size_t numFullChunks = static_cast<size_t>(inLen) / static_cast<size_t>(cleartextChunkSize);
    size_t partialLen = static_cast<size_t>(inLen) % static_cast<size_t>(cleartextChunkSize);
    size_t ctChunkSize = static_cast<size_t>(nonceLen) + static_cast<size_t>(cleartextChunkSize) + tagLen;
    size_t outTotalLen = numFullChunks * ctChunkSize;
    if (partialLen > 0) {
        outTotalLen += static_cast<size_t>(nonceLen) + partialLen + tagLen;
    }

    jbyteArray result = env->NewByteArray(static_cast<jsize>(outTotalLen));
    if (!result) return nullptr;

    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* idData = env->GetByteArrayElements(fileIdOrHeaderNonce, nullptr);
    jbyte* inData = reinterpret_cast<jbyte*>(env->GetPrimitiveArrayCritical(inputBuffer, nullptr));
    jbyte* outData = reinterpret_cast<jbyte*>(env->GetPrimitiveArrayCritical(result, nullptr));

    bool ok = keyData && idData && inData && outData;

    if (ok) {
        size_t totalChunks = numFullChunks + (partialLen > 0 ? 1 : 0);
        
        std::vector<uint8_t> batchNonces(totalChunks * static_cast<size_t>(nonceLen));
        arc4random_buf(batchNonces.data(), batchNonces.size());

        uint8_t* outBytes = reinterpret_cast<uint8_t*>(outData);
        const uint8_t* inBytes = reinterpret_cast<const uint8_t*>(inData);

        auto processChunkRange = [&](size_t startIdx, size_t endIdx) -> bool {
            auto ctx = createCryptoContext(keyLen, nonceLen, reinterpret_cast<const uint8_t*>(keyData));
            if (!ctx) return false;

            for (size_t c = startIdx; c < endIdx; c++) {
                size_t ptLen = (c < numFullChunks) ? static_cast<size_t>(cleartextChunkSize) : partialLen;
                size_t outOffset = c * ctChunkSize;
                size_t inOffset = c * static_cast<size_t>(cleartextChunkSize);
                
                uint8_t* noncePtr = outBytes + outOffset;
                memcpy(noncePtr, batchNonces.data() + (c * static_cast<size_t>(nonceLen)), static_cast<size_t>(nonceLen));

                uint64_t chunkNum = static_cast<uint64_t>(startChunkNumber) + c;
                uint8_t aad[32];
                aad[0] = static_cast<uint8_t>(chunkNum >> 56);
                aad[1] = static_cast<uint8_t>(chunkNum >> 48);
                aad[2] = static_cast<uint8_t>(chunkNum >> 40);
                aad[3] = static_cast<uint8_t>(chunkNum >> 32);
                aad[4] = static_cast<uint8_t>(chunkNum >> 24);
                aad[5] = static_cast<uint8_t>(chunkNum >> 16);
                aad[6] = static_cast<uint8_t>(chunkNum >> 8);
                aad[7] = static_cast<uint8_t>(chunkNum);
                memcpy(aad + 8, idData, static_cast<size_t>(idLen));
                size_t aadLen = 8 + static_cast<size_t>(idLen);

                size_t writtenLen = 0;
                if (!ctx->seal(noncePtr, static_cast<size_t>(nonceLen),
                               inBytes + inOffset, ptLen,
                               aad, aadLen,
                               noncePtr + nonceLen, &writtenLen)) {
                    return false;
                }
            }
            return true;
        };

        unsigned int numThreads = std::thread::hardware_concurrency();
        if (numThreads == 0) numThreads = 4;
        if (numThreads > totalChunks) numThreads = static_cast<unsigned int>(totalChunks);

        if (numThreads <= 1 || totalChunks < 8) {
            ok = processChunkRange(0, totalChunks);
        } else {
            std::vector<std::future<bool>> futures;
            size_t chunksPerThread = totalChunks / numThreads;
            for (unsigned int t = 0; t < numThreads; t++) {
                size_t startIdx = t * chunksPerThread;
                size_t endIdx = (t == numThreads - 1) ? totalChunks : (startIdx + chunksPerThread);
                futures.push_back(std::async(std::launch::async, processChunkRange, startIdx, endIdx));
            }
            for (auto& f : futures) {
                if (!f.get()) ok = false;
            }
        }
    }

    if (outData) env->ReleasePrimitiveArrayCritical(result, outData, 0);
    if (inData) env->ReleasePrimitiveArrayCritical(inputBuffer, inData, JNI_ABORT);
    if (keyData) env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);
    if (idData) env->ReleaseByteArrayElements(fileIdOrHeaderNonce, idData, JNI_ABORT);

    return ok ? result : nullptr;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_aesGcmDecryptStreamNative(
        JNIEnv* env, jobject,
        jbyteArray key, jint nonceLen, jint cleartextChunkSize,
        jbyteArray fileIdOrHeaderNonce, jlong startChunkNumber, jbyteArray inputBuffer) {
    JNI_TRY
    if (!key || !fileIdOrHeaderNonce || !inputBuffer || nonceLen <= 0 || cleartextChunkSize <= 0) return nullptr;
    jsize keyLen = env->GetArrayLength(key);
    jsize idLen = env->GetArrayLength(fileIdOrHeaderNonce);
    jsize inLen = env->GetArrayLength(inputBuffer);
    if (inLen == 0) return nullptr;

    constexpr size_t tagLen = 16;
    size_t ctChunkSize = static_cast<size_t>(nonceLen) + static_cast<size_t>(cleartextChunkSize) + tagLen;
    size_t numFullChunks = static_cast<size_t>(inLen) / ctChunkSize;
    size_t partialCtLen = static_cast<size_t>(inLen) % ctChunkSize;
    size_t partialPtLen = 0;
    if (partialCtLen > 0) {
        if (partialCtLen < static_cast<size_t>(nonceLen + tagLen)) return nullptr;
        partialPtLen = partialCtLen - static_cast<size_t>(nonceLen + tagLen);
    }

    size_t outTotalLen = numFullChunks * static_cast<size_t>(cleartextChunkSize) + partialPtLen;
    jbyteArray result = env->NewByteArray(static_cast<jsize>(outTotalLen));
    if (!result) return nullptr;

    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* idData = env->GetByteArrayElements(fileIdOrHeaderNonce, nullptr);
    jbyte* inData = reinterpret_cast<jbyte*>(env->GetPrimitiveArrayCritical(inputBuffer, nullptr));
    jbyte* outData = reinterpret_cast<jbyte*>(env->GetPrimitiveArrayCritical(result, nullptr));

    bool ok = keyData && idData && inData && outData;

    if (ok) {
        size_t totalChunks = numFullChunks + (partialCtLen > 0 ? 1 : 0);

        uint8_t* outBytes = reinterpret_cast<uint8_t*>(outData);
        const uint8_t* inBytes = reinterpret_cast<const uint8_t*>(inData);

        auto processDecryptRange = [&](size_t startIdx, size_t endIdx) -> bool {
            auto ctx = createCryptoContext(keyLen, nonceLen, reinterpret_cast<const uint8_t*>(keyData));
            if (!ctx) return false;

            for (size_t c = startIdx; c < endIdx; c++) {
                size_t ptLen = (c < numFullChunks) ? static_cast<size_t>(cleartextChunkSize) : partialPtLen;
                size_t thisCtChunkSize = static_cast<size_t>(nonceLen) + ptLen + tagLen;

                size_t inOffset = c * ctChunkSize;
                size_t outOffset = c * static_cast<size_t>(cleartextChunkSize);

                const uint8_t* chunkPtr = inBytes + inOffset;
                const uint8_t* noncePtr = chunkPtr;
                const uint8_t* ctAndTagPtr = chunkPtr + nonceLen;
                size_t ctAndTagLen = ptLen + tagLen;

                uint64_t chunkNum = static_cast<uint64_t>(startChunkNumber) + c;
                uint8_t aad[32];
                aad[0] = static_cast<uint8_t>(chunkNum >> 56);
                aad[1] = static_cast<uint8_t>(chunkNum >> 48);
                aad[2] = static_cast<uint8_t>(chunkNum >> 40);
                aad[3] = static_cast<uint8_t>(chunkNum >> 32);
                aad[4] = static_cast<uint8_t>(chunkNum >> 24);
                aad[5] = static_cast<uint8_t>(chunkNum >> 16);
                aad[6] = static_cast<uint8_t>(chunkNum >> 8);
                aad[7] = static_cast<uint8_t>(chunkNum);
                memcpy(aad + 8, idData, static_cast<size_t>(idLen));
                size_t aadLen = 8 + static_cast<size_t>(idLen);

                size_t writtenLen = 0;
                if (!ctx->open(noncePtr, static_cast<size_t>(nonceLen),
                               ctAndTagPtr, ctAndTagLen,
                               aad, aadLen,
                               outBytes + outOffset, &writtenLen)) {
                    return false;
                }
            }
            return true;
        };

        unsigned int numThreads = std::thread::hardware_concurrency();
        if (numThreads == 0) numThreads = 4;
        if (numThreads > totalChunks) numThreads = static_cast<unsigned int>(totalChunks);

        if (numThreads <= 1 || totalChunks < 8) {
            ok = processDecryptRange(0, totalChunks);
        } else {
            std::vector<std::future<bool>> futures;
            size_t chunksPerThread = totalChunks / numThreads;
            for (unsigned int t = 0; t < numThreads; t++) {
                size_t startIdx = t * chunksPerThread;
                size_t endIdx = (t == numThreads - 1) ? totalChunks : (startIdx + chunksPerThread);
                futures.push_back(std::async(std::launch::async, processDecryptRange, startIdx, endIdx));
            }
            for (auto& f : futures) {
                if (!f.get()) ok = false;
            }
        }
    }

    if (outData) env->ReleasePrimitiveArrayCritical(result, outData, 0);
    if (inData) env->ReleasePrimitiveArrayCritical(inputBuffer, inData, JNI_ABORT);
    if (keyData) env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);
    if (idData) env->ReleaseByteArrayElements(fileIdOrHeaderNonce, idData, JNI_ABORT);

    return ok ? result : nullptr;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_aesGcmEncryptFastNative(
        JNIEnv* env, jobject,
        jbyteArray key, jint nonceLen, jbyteArray aad, jbyteArray plaintext) {
    JNI_TRY
    if (!key || !plaintext || nonceLen <= 0) return nullptr;
    jsize keyLen = env->GetArrayLength(key);
    jsize ptLen = env->GetArrayLength(plaintext);
    jsize aadLen = aad ? env->GetArrayLength(aad) : 0;

    constexpr size_t tagLen = 16;
    const size_t outLen = static_cast<size_t>(nonceLen) + static_cast<size_t>(ptLen) + tagLen;

    jbyteArray result = env->NewByteArray(static_cast<jsize>(outLen));
    if (!result) return nullptr;

    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* aadData = aadLen > 0 ? env->GetByteArrayElements(aad, nullptr) : nullptr;
    jbyte* ptData = ptLen > 0 ? reinterpret_cast<jbyte*>(env->GetPrimitiveArrayCritical(plaintext, nullptr)) : nullptr;
    jbyte* outData = reinterpret_cast<jbyte*>(env->GetPrimitiveArrayCritical(result, nullptr));

    bool ok = keyData && outData;
    if (ok) {
        auto ctx = createCryptoContext(keyLen, nonceLen, reinterpret_cast<const uint8_t*>(keyData));
        if (ctx) {
            uint8_t* outBytes = reinterpret_cast<uint8_t*>(outData);
            arc4random_buf(outBytes, static_cast<size_t>(nonceLen));

            size_t writtenLen = 0;
            ok = ctx->seal(outBytes, static_cast<size_t>(nonceLen),
                           ptData ? reinterpret_cast<const uint8_t*>(ptData) : nullptr, static_cast<size_t>(ptLen),
                           aadData ? reinterpret_cast<const uint8_t*>(aadData) : nullptr, static_cast<size_t>(aadLen),
                           outBytes + nonceLen, &writtenLen);
        } else {
            ok = false;
        }
    }

    if (outData) env->ReleasePrimitiveArrayCritical(result, outData, 0);
    if (ptData) env->ReleasePrimitiveArrayCritical(plaintext, ptData, JNI_ABORT);
    if (aadData) env->ReleaseByteArrayElements(aad, aadData, JNI_ABORT);
    if (keyData) env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);

    return ok ? result : nullptr;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_aesGcmDecryptFastNative(
        JNIEnv* env, jobject,
        jbyteArray key, jint nonceLen, jbyteArray aad, jbyteArray ciphertextAndNonce) {
    JNI_TRY
    if (!key || !ciphertextAndNonce || nonceLen <= 0) return nullptr;
    jsize keyLen = env->GetArrayLength(key);
    jsize totalLen = env->GetArrayLength(ciphertextAndNonce);
    jsize aadLen = aad ? env->GetArrayLength(aad) : 0;
    constexpr size_t tagLen = 16;
    if (totalLen < static_cast<jsize>(nonceLen + tagLen)) return nullptr;

    const size_t ptLen = static_cast<size_t>(totalLen) - nonceLen - tagLen;
    jbyteArray result = env->NewByteArray(static_cast<jsize>(ptLen));
    if (!result) return nullptr;

    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* aadData = aadLen > 0 ? env->GetByteArrayElements(aad, nullptr) : nullptr;
    jbyte* ctData = reinterpret_cast<jbyte*>(env->GetPrimitiveArrayCritical(ciphertextAndNonce, nullptr));
    jbyte* outData = ptLen > 0 ? reinterpret_cast<jbyte*>(env->GetPrimitiveArrayCritical(result, nullptr)) : nullptr;

    bool ok = keyData && ctData && (ptLen == 0 || outData);
    if (ok) {
        auto ctx = createCryptoContext(keyLen, nonceLen, reinterpret_cast<const uint8_t*>(keyData));
        if (ctx) {
            const uint8_t* ctBytes = reinterpret_cast<const uint8_t*>(ctData);
            size_t writtenLen = 0;
            ok = ctx->open(ctBytes, static_cast<size_t>(nonceLen),
                           ctBytes + nonceLen, static_cast<size_t>(totalLen) - nonceLen,
                           aadData ? reinterpret_cast<const uint8_t*>(aadData) : nullptr, static_cast<size_t>(aadLen),
                           outData ? reinterpret_cast<uint8_t*>(outData) : nullptr, &writtenLen);
        } else {
            ok = false;
        }
    }

    if (outData) env->ReleasePrimitiveArrayCritical(result, outData, 0);
    if (ctData) env->ReleasePrimitiveArrayCritical(ciphertextAndNonce, ctData, JNI_ABORT);
    if (aadData) env->ReleaseByteArrayElements(aad, aadData, JNI_ABORT);
    if (keyData) env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);

    return ok ? result : nullptr;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_aesGcmEncryptNative(
        JNIEnv* env, jobject,
        jbyteArray key, jbyteArray iv, jbyteArray aad, jbyteArray plaintext) {
    JNI_TRY
    if (!key || !iv || !plaintext) return nullptr;
    jsize keyLen = env->GetArrayLength(key);
    jsize ivLen = env->GetArrayLength(iv);
    jsize ptLen = env->GetArrayLength(plaintext);
    jsize aadLen = aad ? env->GetArrayLength(aad) : 0;

    constexpr size_t tagLen = 16;
    size_t outMaxLen = static_cast<size_t>(ptLen) + tagLen;
    jbyteArray result = env->NewByteArray(static_cast<jsize>(outMaxLen));
    if (!result) return nullptr;

    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* ivData = env->GetByteArrayElements(iv, nullptr);
    jbyte* aadData = aadLen > 0 ? env->GetByteArrayElements(aad, nullptr) : nullptr;
    jbyte* ptData = ptLen > 0 ? reinterpret_cast<jbyte*>(env->GetPrimitiveArrayCritical(plaintext, nullptr)) : nullptr;
    jbyte* outData = reinterpret_cast<jbyte*>(env->GetPrimitiveArrayCritical(result, nullptr));

    bool ok = keyData && ivData && outData;
    if (ok) {
        auto ctx = createCryptoContext(keyLen, ivLen, reinterpret_cast<const uint8_t*>(keyData));
        if (ctx) {
            size_t writtenLen = 0;
            ok = ctx->seal(reinterpret_cast<const uint8_t*>(ivData), static_cast<size_t>(ivLen),
                           ptData ? reinterpret_cast<const uint8_t*>(ptData) : nullptr, static_cast<size_t>(ptLen),
                           aadData ? reinterpret_cast<const uint8_t*>(aadData) : nullptr, static_cast<size_t>(aadLen),
                           reinterpret_cast<uint8_t*>(outData), &writtenLen);
        } else {
            ok = false;
        }
    }

    if (outData) env->ReleasePrimitiveArrayCritical(result, outData, 0);
    if (ptData) env->ReleasePrimitiveArrayCritical(plaintext, ptData, JNI_ABORT);
    if (aadData) env->ReleaseByteArrayElements(aad, aadData, JNI_ABORT);
    if (ivData) env->ReleaseByteArrayElements(iv, ivData, JNI_ABORT);
    if (keyData) env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);

    return ok ? result : nullptr;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_aesGcmDecryptNative(
        JNIEnv* env, jobject,
        jbyteArray key, jbyteArray iv, jbyteArray aad, jbyteArray ciphertextAndTag) {
    JNI_TRY
    if (!key || !iv || !ciphertextAndTag) return nullptr;
    jsize keyLen = env->GetArrayLength(key);
    jsize ivLen = env->GetArrayLength(iv);
    jsize ctLen = env->GetArrayLength(ciphertextAndTag);
    jsize aadLen = aad ? env->GetArrayLength(aad) : 0;

    constexpr size_t tagLen = 16;
    if (ctLen < static_cast<jsize>(tagLen) || ivLen == 0) return nullptr;

    const size_t ptLen = static_cast<size_t>(ctLen) - tagLen;
    jbyteArray result = env->NewByteArray(static_cast<jsize>(ptLen));
    if (!result) return nullptr;

    jbyte* keyData = env->GetByteArrayElements(key, nullptr);
    jbyte* ivData = env->GetByteArrayElements(iv, nullptr);
    jbyte* aadData = aadLen > 0 ? env->GetByteArrayElements(aad, nullptr) : nullptr;
    jbyte* ctData = reinterpret_cast<jbyte*>(env->GetPrimitiveArrayCritical(ciphertextAndTag, nullptr));
    jbyte* outData = ptLen > 0 ? reinterpret_cast<jbyte*>(env->GetPrimitiveArrayCritical(result, nullptr)) : nullptr;

    bool ok = keyData && ivData && ctData && (ptLen == 0 || outData);
    if (ok) {
        auto ctx = createCryptoContext(keyLen, ivLen, reinterpret_cast<const uint8_t*>(keyData));
        if (ctx) {
            size_t writtenLen = 0;
            ok = ctx->open(reinterpret_cast<const uint8_t*>(ivData), static_cast<size_t>(ivLen),
                           reinterpret_cast<const uint8_t*>(ctData), static_cast<size_t>(ctLen),
                           aadData ? reinterpret_cast<const uint8_t*>(aadData) : nullptr, static_cast<size_t>(aadLen),
                           outData ? reinterpret_cast<uint8_t*>(outData) : nullptr, &writtenLen);
        } else {
            ok = false;
        }
    }

    if (outData) env->ReleasePrimitiveArrayCritical(result, outData, 0);
    if (ctData) env->ReleasePrimitiveArrayCritical(ciphertextAndTag, ctData, JNI_ABORT);
    if (aadData) env->ReleaseByteArrayElements(aad, aadData, JNI_ABORT);
    if (ivData) env->ReleaseByteArrayElements(iv, ivData, JNI_ABORT);
    if (keyData) env->ReleaseByteArrayElements(key, keyData, JNI_ABORT);

    return ok ? result : nullptr;
    JNI_CATCH_RETURN(nullptr)
}