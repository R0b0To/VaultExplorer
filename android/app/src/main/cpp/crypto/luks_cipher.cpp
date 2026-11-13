#include "luks_cipher.h"
#include "xts_tweak.h"
#include <cstring>
#include <algorithm>
#include "mbedtls/md.h"
#include "mbedtls/platform_util.h"

static bool cipherFromName(const std::string& name, CipherId& out) {
    if (name == "aes") { out = CipherId::kAes; return true; }
    if (name == "serpent") { out = CipherId::kSerpent; return true; }
    if (name == "twofish") { out = CipherId::kTwofish; return true; }
    if (name == "camellia") { out = CipherId::kCamellia; return true; }
    if (name == "kuznyechik") { out = CipherId::kKuznyechik; return true; }
    return false;
}

// Valid per-key byte length for a block cipher key (CBC key, or one XTS half).
static bool validKeyLen(CipherId c, size_t len) {
    if (c == CipherId::kAes) return len == 16 || len == 32;   // AES-192 is not wired up in blockCipherSetKey()
    return len == 32;                                          // the VeraCrypt primitives take 256-bit keys only
}

bool luksParseCipherSpec(const std::string& cipherName, const std::string& cipherMode,
                         uint32_t keyBytes, LuksCipherSpec& out) {
    LuksCipherSpec s;
    if (!cipherFromName(cipherName, s.cipher)) return false;
    s.keyBytes = keyBytes;

    std::string chain = cipherMode, iv;
    const size_t dash = cipherMode.find('-');
    if (dash != std::string::npos) { chain = cipherMode.substr(0, dash); iv = cipherMode.substr(dash + 1); }

    if (chain == "xts") {
        s.chain = LuksChain::kXts;
        if (keyBytes % 2 != 0 || !validKeyLen(s.cipher, keyBytes / 2)) return false;
        if (iv == "plain64") s.iv = LuksIvMode::kPlain64;
        else if (iv == "plain") s.iv = LuksIvMode::kPlain;
        else return false;
    } else if (chain == "cbc") {
        s.chain = LuksChain::kCbc;
        if (!validKeyLen(s.cipher, keyBytes)) return false;
        if (iv == "plain64") s.iv = LuksIvMode::kPlain64;
        else if (iv == "plain") s.iv = LuksIvMode::kPlain;
        else if (iv == "essiv:sha256") s.iv = LuksIvMode::kEssivSha256;
        else return false;
    } else {
        return false;
    }
    out = s;
    return true;
}

bool luksParseCipherString(const std::string& encryption, uint32_t keyBytes, LuksCipherSpec& out) {
    const size_t dash = encryption.find('-');
    if (dash == std::string::npos || dash == 0) return false;
    return luksParseCipherSpec(encryption.substr(0, dash), encryption.substr(dash + 1), keyBytes, out);
}

bool luksCipherInit(LuksCipherContext& ctx, const LuksCipherSpec& spec,
                    const uint8_t* key, size_t keyLen) {
    ctx.initialized = false;
    if (!key || keyLen != spec.keyBytes) return false;
    ctx.spec = spec;
    if (spec.chain == LuksChain::kXts) {
        if (keyLen % 2 != 0) return false;
        const size_t half = keyLen / 2;
        if (!validKeyLen(spec.cipher, half)) return false;
        if (!blockCipherSetKey(ctx.xts.dataKeyEnc, spec.cipher, key, half)) return false;
        if (!blockCipherSetKey(ctx.xts.dataKeyDec, spec.cipher, key, half)) return false;
        if (!blockCipherSetKey(ctx.xts.tweakKey, spec.cipher, key + half, half)) return false;
    } else {
        if (!validKeyLen(spec.cipher, keyLen)) return false;
        if (!blockCipherSetKey(ctx.cbcEnc, spec.cipher, key, keyLen)) return false;
        if (!blockCipherSetKey(ctx.cbcDec, spec.cipher, key, keyLen)) return false;
        if (spec.iv == LuksIvMode::kEssivSha256) {
            uint8_t salt[32];
            const mbedtls_md_info_t* md = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
            if (!md || mbedtls_md(md, key, keyLen, salt) != 0) return false;
            const bool ok = blockCipherSetKey(ctx.essiv, spec.cipher, salt, 32);
            mbedtls_platform_zeroize(salt, sizeof(salt));
            if (!ok) return false;
        }
    }
    ctx.initialized = true;
    return true;
}

void luksCipherWipe(LuksCipherContext& ctx) {
    mbedtls_platform_zeroize(&ctx, sizeof(ctx));
}

static inline void ivSeed(uint8_t out[16], uint64_t sector, bool low32Only) {
    std::memset(out, 0, 16);
    const uint64_t v = low32Only ? (sector & 0xFFFFFFFFull) : sector;
    for (int i = 0; i < (low32Only ? 4 : 8); i++) out[i] = static_cast<uint8_t>(v >> (8 * i));
}

static void xtsUnit(const LuksCipherContext& ctx, bool encrypt, uint64_t iv512,
                    const uint8_t* in, uint8_t* out, size_t len) {
    uint8_t seed[16], T[16];
    ivSeed(seed, iv512, ctx.spec.iv == LuksIvMode::kPlain);
    blockCipherEncryptBlock(ctx.xts.tweakKey, seed, T);
    for (size_t b = 0; b < len / 16; b++) {
        uint8_t tmp[16];
        for (int j = 0; j < 16; j++) tmp[j] = in[b * 16 + j] ^ T[j];
        if (encrypt) blockCipherEncryptBlock(ctx.xts.dataKeyEnc, tmp, tmp);
        else         blockCipherDecryptBlock(ctx.xts.dataKeyDec, tmp, tmp);
        for (int j = 0; j < 16; j++) out[b * 16 + j] = tmp[j] ^ T[j];
        xtsMultiplyTweak(T);
    }
}

static void cbcUnit(const LuksCipherContext& ctx, bool encrypt, uint64_t iv512,
                    const uint8_t* in, uint8_t* out, size_t len) {
    uint8_t iv[16];
    ivSeed(iv, iv512, ctx.spec.iv == LuksIvMode::kPlain);
    if (ctx.spec.iv == LuksIvMode::kEssivSha256) {
        uint8_t enc[16];
        blockCipherEncryptBlock(ctx.essiv, iv, enc);
        std::memcpy(iv, enc, 16);
    }
    uint8_t prev[16];
    std::memcpy(prev, iv, 16);
    if (encrypt) {
        for (size_t b = 0; b < len / 16; b++) {
            uint8_t tmp[16];
            for (int j = 0; j < 16; j++) tmp[j] = in[b * 16 + j] ^ prev[j];
            blockCipherEncryptBlock(ctx.cbcEnc, tmp, prev);
            std::memcpy(out + b * 16, prev, 16);
        }
    } else {
        for (size_t b = 0; b < len / 16; b++) {
            uint8_t cur[16], tmp[16];
            std::memcpy(cur, in + b * 16, 16);          // save ciphertext first: in == out is allowed
            blockCipherDecryptBlock(ctx.cbcDec, cur, tmp);
            for (int j = 0; j < 16; j++) out[b * 16 + j] = tmp[j] ^ prev[j];
            std::memcpy(prev, cur, 16);
        }
    }
}

bool luksCipherCrypt(const LuksCipherContext& ctx, bool encrypt, uint64_t iv512Start,
                     uint32_t sectorSize, const uint8_t* in, uint8_t* out, size_t len) {
    if (!ctx.initialized || !in || !out) return false;
    if (sectorSize < 512 || sectorSize > 4096 || (sectorSize & (sectorSize - 1)) != 0) return false;
    if (len == 0 || len % sectorSize != 0) return false;
    const uint64_t step = sectorSize / 512;
    const size_t sectors = len / sectorSize;
    for (size_t s = 0; s < sectors; s++) {
        const uint64_t iv = iv512Start + static_cast<uint64_t>(s) * step;
        const uint8_t* i = in + s * sectorSize;
        uint8_t* o = out + s * sectorSize;
        if (ctx.spec.chain == LuksChain::kXts) xtsUnit(ctx, encrypt, iv, i, o, sectorSize);
        else                                    cbcUnit(ctx, encrypt, iv, i, o, sectorSize);
    }
    return true;
}
