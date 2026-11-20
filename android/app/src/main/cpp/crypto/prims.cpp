#include "prims.h"

#include "mbedtls/cipher.h"
#include "mbedtls/gcm.h"
#include "mbedtls/md.h"
#include "mbedtls/pkcs5.h"
#include "mbedtls/platform_util.h"

namespace prims {

namespace {

mbedtls_md_type_t mdType(Hash h) {
    switch (h) {
        case Hash::Sha1: return MBEDTLS_MD_SHA1;
        case Hash::Sha256: return MBEDTLS_MD_SHA256;
        case Hash::Sha512: return MBEDTLS_MD_SHA512;
    }
    return MBEDTLS_MD_NONE;
}

// mbedtls rejects a null pointer even for a zero-length buffer in some paths.
const uint8_t* nonNull(const uint8_t* p) {
    static const uint8_t kNone = 0;
    return p ? p : &kNone;
}

void wipe(Bytes& b) {
    if (!b.empty()) mbedtls_platform_zeroize(b.data(), b.size());
}

struct Failed {
    Bytes& out;
    bool done = false;
    explicit Failed(Bytes& o) : out(o) { out.clear(); }
    // Leaves `out` empty (and wiped) unless success() was called.
    ~Failed() {
        if (!done) {
            wipe(out);
            out.clear();
        }
    }
    bool success() {
        done = true;
        return true;
    }
};

struct CipherGuard {
    mbedtls_cipher_context_t c;
    CipherGuard() { mbedtls_cipher_init(&c); }
    ~CipherGuard() { mbedtls_cipher_free(&c); }
};

struct GcmGuard {
    mbedtls_gcm_context c;
    GcmGuard() { mbedtls_gcm_init(&c); }
    ~GcmGuard() { mbedtls_gcm_free(&c); }
};

constexpr size_t kTag = 16;
constexpr size_t kBlock = 16;

bool validAesKey(size_t len, bool allow192) { return len == 16 || len == 32 || (allow192 && len == 24); }

}  // namespace

bool parseHash(std::string_view s, Hash& out) {
    if (s == "sha1") out = Hash::Sha1;
    else if (s == "sha256") out = Hash::Sha256;
    else if (s == "sha512") out = Hash::Sha512;
    else return false;
    return true;
}

bool hmac(Hash h, const uint8_t* key, size_t keyLen, const uint8_t* data, size_t dataLen, Bytes& out) {
    Failed f(out);
    if (!key || keyLen == 0) return false;
    if (!data && dataLen != 0) return false;
    const mbedtls_md_info_t* info = mbedtls_md_info_from_type(mdType(h));
    if (!info) return false;
    Bytes mac(mbedtls_md_get_size(info));
    if (mbedtls_md_hmac(info, key, keyLen, nonNull(data), dataLen, mac.data()) != 0) return false;
    out = std::move(mac);
    return f.success();
}

bool pbkdf2(Hash h, const uint8_t* pw, size_t pwLen, const uint8_t* salt, size_t saltLen, uint32_t iterations,
            size_t outLen, Bytes& out) {
    Failed f(out);
    if (!salt || saltLen == 0 || iterations == 0 || outLen == 0 || outLen > 0xFFFFFFFFu) return false;
    if (!pw && pwLen != 0) return false;
    Bytes dk(outLen);
    const int rc = mbedtls_pkcs5_pbkdf2_hmac_ext(mdType(h), nonNull(pw), pwLen, salt, saltLen, iterations,
                                                  static_cast<uint32_t>(outLen), dk.data());
    if (rc != 0) {
        wipe(dk);
        return false;
    }
    out = std::move(dk);
    return f.success();
}

bool aesGcmSeal(const uint8_t* key, size_t keyLen, const uint8_t* iv, size_t ivLen, const uint8_t* aad, size_t aadLen,
                const uint8_t* pt, size_t ptLen, Bytes& out) {
    Failed f(out);
    if (!key || !validAesKey(keyLen, false) || !iv || ivLen == 0) return false;
    if ((!aad && aadLen != 0) || (!pt && ptLen != 0)) return false;
    GcmGuard g;
    if (mbedtls_gcm_setkey(&g.c, MBEDTLS_CIPHER_ID_AES, key, static_cast<unsigned>(keyLen * 8)) != 0) return false;
    Bytes buf(ptLen + kTag);
    if (mbedtls_gcm_crypt_and_tag(&g.c, MBEDTLS_GCM_ENCRYPT, ptLen, iv, ivLen, nonNull(aad), aadLen, nonNull(pt),
                                  buf.data(), kTag, buf.data() + ptLen) != 0)
        return false;
    out = std::move(buf);
    return f.success();
}

bool aesGcmOpen(const uint8_t* key, size_t keyLen, const uint8_t* iv, size_t ivLen, const uint8_t* aad, size_t aadLen,
                const uint8_t* ctAndTag, size_t ctLen, Bytes& out) {
    Failed f(out);
    if (!key || !validAesKey(keyLen, false) || !iv || ivLen == 0 || !ctAndTag || ctLen < kTag) return false;
    if (!aad && aadLen != 0) return false;
    GcmGuard g;
    if (mbedtls_gcm_setkey(&g.c, MBEDTLS_CIPHER_ID_AES, key, static_cast<unsigned>(keyLen * 8)) != 0) return false;
    const size_t ptLen = ctLen - kTag;
    Bytes pt(ptLen);
    // mbedtls compares the tag in constant time and wipes the output itself when it does not match.
    if (mbedtls_gcm_auth_decrypt(&g.c, ptLen, iv, ivLen, nonNull(aad), aadLen, ctAndTag + ptLen, kTag, ctAndTag,
                                 pt.data()) != 0) {
        wipe(pt);
        return false;
    }
    out = std::move(pt);
    return f.success();
}

namespace {

bool cbc(bool encrypt, const uint8_t* key, size_t keyLen, const uint8_t* iv, size_t ivLen, const uint8_t* in,
         size_t inLen, Bytes& out) {
    Failed f(out);
    if (!key || !validAesKey(keyLen, true) || !iv || ivLen != kBlock) return false;
    if (!in && inLen != 0) return false;
    if (!encrypt && (inLen == 0 || inLen % kBlock != 0)) return false;

    const mbedtls_cipher_info_t* info =
        mbedtls_cipher_info_from_values(MBEDTLS_CIPHER_ID_AES, static_cast<int>(keyLen * 8), MBEDTLS_MODE_CBC);
    if (!info) return false;
    CipherGuard g;
    if (mbedtls_cipher_setup(&g.c, info) != 0) return false;
    if (mbedtls_cipher_setkey(&g.c, key, static_cast<int>(keyLen * 8), encrypt ? MBEDTLS_ENCRYPT : MBEDTLS_DECRYPT) != 0)
        return false;
    if (mbedtls_cipher_set_padding_mode(&g.c, MBEDTLS_PADDING_PKCS7) != 0) return false;

    Bytes buf(inLen + kBlock);   // encryption adds up to one block of padding
    size_t written = 0;
    if (mbedtls_cipher_crypt(&g.c, iv, ivLen, nonNull(in), inLen, buf.data(), &written) != 0) {
        wipe(buf);   // a failed decrypt may have written plaintext before the padding check failed
        return false;
    }
    buf.resize(written);
    out = std::move(buf);
    return f.success();
}

}  // namespace

bool aesCbcEncrypt(const uint8_t* key, size_t keyLen, const uint8_t* iv, size_t ivLen, const uint8_t* pt, size_t ptLen,
                   Bytes& out) {
    return cbc(true, key, keyLen, iv, ivLen, pt, ptLen, out);
}

bool aesCbcDecrypt(const uint8_t* key, size_t keyLen, const uint8_t* iv, size_t ivLen, const uint8_t* ct, size_t ctLen,
                   Bytes& out) {
    return cbc(false, key, keyLen, iv, ivLen, ct, ctLen, out);
}

}  // namespace prims
