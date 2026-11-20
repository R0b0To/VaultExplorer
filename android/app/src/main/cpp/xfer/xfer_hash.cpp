#include "xfer_hash.h"

#include <algorithm>

#include "mbedtls/md.h"

namespace xfer {

namespace {
mbedtls_md_type_t mdType(HashAlgo a) {
    switch (a) {
        case HashAlgo::Md5: return MBEDTLS_MD_MD5;
        case HashAlgo::Sha1: return MBEDTLS_MD_SHA1;
        case HashAlgo::Sha256: return MBEDTLS_MD_SHA256;
        case HashAlgo::Sha512: return MBEDTLS_MD_SHA512;
    }
    return MBEDTLS_MD_NONE;
}
}  // namespace

bool parseHashAlgo(std::string_view s, HashAlgo& out) {
    if (s == "MD5") out = HashAlgo::Md5;
    else if (s == "SHA-1") out = HashAlgo::Sha1;
    else if (s == "SHA-256") out = HashAlgo::Sha256;
    else if (s == "SHA-512") out = HashAlgo::Sha512;
    else return false;
    return true;
}

const char* hashWireName(HashAlgo a) {
    switch (a) {
        case HashAlgo::Md5: return "MD5";
        case HashAlgo::Sha1: return "SHA-1";
        case HashAlgo::Sha256: return "SHA-256";
        case HashAlgo::Sha512: return "SHA-512";
    }
    return "";
}

std::string toHex(const uint8_t* data, size_t n) {
    static const char* kDigits = "0123456789abcdef";
    std::string s;
    s.reserve(n * 2);
    for (size_t i = 0; i < n; ++i) {
        s.push_back(kDigits[data[i] >> 4]);
        s.push_back(kDigits[data[i] & 0x0F]);
    }
    return s;
}

std::string Digest::hex() const { return toHex(bytes.data(), bytes.size()); }

struct MultiHasher::Ctx {
    HashAlgo algo;
    mbedtls_md_context_t md;
    bool ready = false;
    explicit Ctx(HashAlgo a) : algo(a) {
        mbedtls_md_init(&md);
        const mbedtls_md_info_t* info = mbedtls_md_info_from_type(mdType(a));
        if (info && mbedtls_md_setup(&md, info, 0) == 0 && mbedtls_md_starts(&md) == 0) ready = true;
    }
    ~Ctx() { mbedtls_md_free(&md); }
};

MultiHasher::MultiHasher(const std::vector<HashAlgo>& algos) {
    for (HashAlgo a : algos) {
        const bool seen = std::any_of(ctx_.begin(), ctx_.end(), [&](const std::unique_ptr<Ctx>& c) { return c->algo == a; });
        if (seen) continue;
        ctx_.push_back(std::make_unique<Ctx>(a));
        if (!ctx_.back()->ready) ok_ = false;
    }
}

MultiHasher::~MultiHasher() = default;

void MultiHasher::update(const uint8_t* data, size_t n) {
    if (!ok_ || finished_ || n == 0) return;
    for (auto& c : ctx_) mbedtls_md_update(&c->md, data, n);
}

std::vector<Digest> MultiHasher::finish() {
    std::vector<Digest> out;
    if (finished_) return out;
    finished_ = true;
    if (!ok_) return out;
    for (auto& c : ctx_) {
        Digest d;
        d.algo = c->algo;
        d.bytes.resize(mbedtls_md_get_size(mbedtls_md_info_from_ctx(&c->md)));
        if (mbedtls_md_finish(&c->md, d.bytes.data()) != 0) {
            ok_ = false;
            return {};
        }
        out.push_back(std::move(d));
    }
    return out;
}

Result hashStream(ByteSource& src, const std::vector<HashAlgo>& algos, uint64_t totalHint, Observer* obs,
                  std::vector<Digest>& out) {
    out.clear();
    MultiHasher h(algos);
    if (!h.ok()) return Result::Failed;
    std::vector<uint8_t> buf(kChunkBytes);
    uint64_t done = 0;
    for (;;) {
        if (obs && obs->cancelled()) return Result::Cancelled;
        const int64_t n = src.read(buf.data(), buf.size());
        if (n < 0) return Result::Failed;
        if (n == 0) break;
        h.update(buf.data(), static_cast<size_t>(n));
        done += static_cast<uint64_t>(n);
        if (obs) obs->onProgress(done, totalHint);
    }
    std::vector<Digest> digests = h.finish();
    if (digests.empty() && !algos.empty()) return Result::Failed;
    out = std::move(digests);
    return Result::Ok;
}

}  // namespace xfer
