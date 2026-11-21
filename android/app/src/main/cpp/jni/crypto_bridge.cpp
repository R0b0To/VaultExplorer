#include <jni.h>
#include <cstring>
#include <vector>
#include <mutex>
#include <shared_mutex>
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
#include "session_guard_jni.h"
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
    std::shared_lock<std::shared_mutex> lock(v.mutex);
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
    const char* nativePass = vcGetPasswordUtf8(env, password);
    unsigned char headerBuf[VC_FULL_HEADER_SIZE];
    if (pread(fd, headerBuf, VC_FULL_HEADER_SIZE, 0) != VC_FULL_HEADER_SIZE) {
        vcReleasePasswordUtf8(nativePass);
        closeUnusedKeyfileFds(kfFds.data(), static_cast<int>(kfFds.size()));
        return nullptr;
    }
    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = std::min(strlen(nativePass), sizeof(mixedPassword));
    memcpy(mixedPassword, nativePass, mixedPasswordLen);
    vcReleasePasswordUtf8(nativePass);
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

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_argon2idNative(
        JNIEnv* env, jobject,
        jbyteArray password, jbyteArray salt,
        jint memoryKiB, jint iterations, jint parallelism, jint outputLen) {
    JNI_TRY
    if (password == nullptr || salt == nullptr || outputLen <= 0) return nullptr;
    jsize pwLen = env->GetArrayLength(password);
    jsize saltLen = env->GetArrayLength(salt);
    jbyte* pwData = env->GetByteArrayElements(password, nullptr);
    jbyte* saltData = env->GetByteArrayElements(salt, nullptr);
    std::vector<uint8_t> out(static_cast<size_t>(outputLen));

    bool ok = argon2idDeriveKey(
        reinterpret_cast<const unsigned char*>(pwData), static_cast<size_t>(pwLen),
        reinterpret_cast<const unsigned char*>(saltData), static_cast<size_t>(saltLen),
        static_cast<uint32_t>(memoryKiB), static_cast<uint32_t>(iterations), static_cast<uint32_t>(parallelism),
        out.data(), out.size(), nullptr
    );

    mbedtls_platform_zeroize(pwData, pwLen);
    env->ReleaseByteArrayElements(password, pwData, JNI_ABORT);
    env->ReleaseByteArrayElements(salt, saltData, JNI_ABORT);

    if (!ok) {
        mbedtls_platform_zeroize(out.data(), out.size());
        return nullptr;
    }
    jbyteArray result = env->NewByteArray(outputLen);
    env->SetByteArrayRegion(result, 0, outputLen, reinterpret_cast<const jbyte*>(out.data()));
    mbedtls_platform_zeroize(out.data(), out.size());
    return result;
    JNI_CATCH_RETURN(nullptr)
}

// Same as scryptNative, but keeps at most 256 MiB of scrypt memory (time-memory trade-off), so CryFS vaults created
// with official settings (up to 1 GiB) can be handled. See scrypt_crypto_lowmem.
extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_scryptLowMemNative(
        JNIEnv* env, jobject,
        jbyteArray passphrase, jbyteArray salt, jint N, jint r, jint p, jint dkLen) {
    JNI_TRY
    if (passphrase == nullptr || salt == nullptr || dkLen <= 0 || N <= 0 || r <= 0 || p <= 0) return nullptr;
    jsize pwLen = env->GetArrayLength(passphrase);
    jsize saltLen = env->GetArrayLength(salt);
    jbyte* pwData = env->GetByteArrayElements(passphrase, nullptr);
    jbyte* saltData = env->GetByteArrayElements(salt, nullptr);
    std::vector<uint8_t> out(static_cast<size_t>(dkLen));
    bool ok = scrypt_crypto_lowmem(
        reinterpret_cast<const uint8_t*>(pwData), static_cast<size_t>(pwLen),
        reinterpret_cast<const uint8_t*>(saltData), static_cast<size_t>(saltLen),
        static_cast<uint32_t>(N), static_cast<uint32_t>(r), static_cast<uint32_t>(p),
        out.data(), static_cast<size_t>(dkLen), 256u * 1024 * 1024
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

// PBKDF2-HMAC over a raw *byte-array* password, SHA-1 or SHA-256.
//
// Added for importing other authenticator apps' encrypted backups (andOTP
// needs PBKDF2WithHmacSHA1, 2FAS needs PBKDF2-HMAC-SHA256). Two deliberate
// choices vs. the existing hashPassword*Native functions above:
//  * SHA-1 is NOT added to HashId (cipher_shim.h) -- that enum is walked by
//    the VeraCrypt header-probing code, and adding it would make volume
//    unlock try SHA-1 header KDFs too. This function is standalone.
//  * The password arrives as UTF-8 bytes from Dart, not a jstring:
//    GetStringUTFChars returns *modified* UTF-8 (supplementary characters,
//    e.g. emoji, as 6-byte surrogate pairs), which would derive the wrong
//    key for a backup made with a password containing one.
// hashKind: 1 = SHA-1, 2 = SHA-256.
extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_pbkdf2Native(
        JNIEnv* env, jobject,
        jbyteArray password, jbyteArray salt, jint iterations, jint outputLen, jint hashKind) {
    JNI_TRY
    if (password == nullptr || salt == nullptr || outputLen <= 0 || iterations <= 0) return nullptr;
    const EVP_MD* md = nullptr;
    if (hashKind == 1) md = EVP_sha1();
    else if (hashKind == 2) md = EVP_sha256();
    if (md == nullptr) return nullptr;

    const jsize pwLen   = env->GetArrayLength(password);
    const jsize saltLen = env->GetArrayLength(salt);
    if (saltLen == 0) return nullptr;
    jbyte* pwData   = env->GetByteArrayElements(password, nullptr);
    jbyte* saltData = env->GetByteArrayElements(salt, nullptr);
    std::vector<unsigned char> out(static_cast<size_t>(outputLen), 0);
    const int rc = PKCS5_PBKDF2_HMAC(
        reinterpret_cast<const char*>(pwData), static_cast<size_t>(pwLen),
        reinterpret_cast<const uint8_t*>(saltData), static_cast<size_t>(saltLen),
        static_cast<unsigned>(iterations), md, out.size(), out.data());
    mbedtls_platform_zeroize(pwData, static_cast<size_t>(pwLen));
    env->ReleaseByteArrayElements(password, pwData, JNI_ABORT);
    env->ReleaseByteArrayElements(salt, saltData, JNI_ABORT);
    if (rc != 1) {
        mbedtls_platform_zeroize(out.data(), out.size());
        return nullptr;
    }
    jbyteArray result = env->NewByteArray(static_cast<jsize>(out.size()));
    env->SetByteArrayRegion(result, 0, static_cast<jsize>(out.size()),
                            reinterpret_cast<jbyte*>(out.data()));
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