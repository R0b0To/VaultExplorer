// Content hashing: MD5, SHA-1, SHA-256 and SHA-512, any number of them in one pass.
//
// The algorithm set and wire names are exactly those of the Kotlin HashVerifierHandlers
// ("MD5", "SHA-1", "SHA-256", "SHA-512"); digests are rendered as lowercase hex. Built on the
// mbedtls the folder-vault core already links, so it adds no dependency to either build.
// These are integrity checksums for the user's files -- MD5 and SHA-1 are offered because
// published checksums still use them, not as security primitives.
#pragma once

#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "xfer_io.h"

namespace xfer {

enum class HashAlgo { Md5, Sha1, Sha256, Sha512 };

// Exact wire names only; anything else (other case, "SHA256", "SHA-384") is rejected.
bool parseHashAlgo(std::string_view wireName, HashAlgo& out);
const char* hashWireName(HashAlgo a);

struct Digest {
    HashAlgo algo;
    std::vector<uint8_t> bytes;
    std::string hex() const;   // lowercase, two digits per byte
};

std::string toHex(const uint8_t* data, size_t n);

// Incremental hasher over several algorithms at once, so a file is read a single time.
// Duplicate algorithms in the request are collapsed (first occurrence wins).
class MultiHasher {
public:
    explicit MultiHasher(const std::vector<HashAlgo>& algos);
    ~MultiHasher();
    MultiHasher(const MultiHasher&) = delete;
    MultiHasher& operator=(const MultiHasher&) = delete;

    bool ok() const { return ok_; }                 // false if the crypto library lacks an algorithm
    void update(const uint8_t* data, size_t n);
    // The digests in request order. The hasher is finished afterwards.
    std::vector<Digest> finish();

private:
    struct Ctx;
    std::vector<std::unique_ptr<Ctx>> ctx_;
    bool ok_ = true;
    bool finished_ = false;
};

// Streams `src` to its end through every algorithm. `totalHint` (0 = unknown) only feeds
// progress. Cancelled when obs->cancelled() says so; Failed on a read error or an unusable
// algorithm. `out` is only filled on Ok.
Result hashStream(ByteSource& src, const std::vector<HashAlgo>& algos, uint64_t totalHint, Observer* obs,
                  std::vector<Digest>& out);

}  // namespace xfer
