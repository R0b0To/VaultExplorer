#pragma once
// Decrypted-range LRU cache for the encrypted-volume block-device layer
// (disk_read/disk_write in virtual_block_device.cpp).
//
// Every disk_read() call re-reads physical sectors over USB and re-runs XTS
// decryption from scratch, even for a byte range that was just read a moment
// ago -- there is no caching anywhere between the FatFs/NTFS/ext filesystem
// layer and the physical transport. This matters most for repeated/backward
// access patterns: re-opening a file, seeking backward, or (for the Media
// Viewer specifically) swiping back to a previously-viewed image on a
// VeraCrypt/LUKS/BitLocker USB volume re-walks the same directory entries,
// FAT chains, and file data from zero every time.
//
// This cache stores decrypted plaintext (post-XTS), keyed by the exact
// aligned physical byte range disk_read's batching already computes, so a
// hit skips both the USB round trip AND the crypto work -- caching
// ciphertext would still leave decryption on the hit path, which is most of
// what makes a cache worthwhile here.
//
// Keyed by (alignedPhysicalByteOffset, byteLength) rather than split into
// fixed-size blocks: disk_read's three decrypt branches (VeraCrypt cascade,
// single-sector LUKS, multi-sector-unit LUKS) each produce one contiguous
// decrypted buffer per aligned batch, and splitting that across independent
// fixed-size cache blocks would require restructuring all three branches to
// operate in cache-block-sized sub-chunks. That's a larger, higher-risk change
// than the latency problem calls for -- most of the benefit here comes from
// repeat reads landing on the same (or a subset of the same) aligned range,
// which whole-batch caching already captures, since disk_read's own batching
// is already deterministic for a given (sector, count) request.
//
// Deliberately header-only and free of Android/JNI/mbedtls dependencies so
// it can be exercised by a host-side g++ test the same way sector_batching.h
// is (see io/test/decrypted_block_cache_test.cpp) -- eviction-order and
// invalidation-range bugs in something read-modify-write callers depend on
// for correctness are exactly the kind of thing worth testing without an
// Android toolchain or real USB hardware in the loop.

#include <cstdint>
#include <cstring>
#include <list>
#include <unordered_map>
#include <vector>

class DecryptedBlockCache {
public:
    // capacityBytes: total decrypted bytes retained across all cached
    // ranges. 16 MiB by default -- small relative to typical device RAM,
    // large enough to hold filesystem metadata plus a handful of
    // recently-viewed files' worth of data for typical browsing/swiping
    // sessions. A single range larger than capacityBytes is not cached at
    // all (see put()), so one huge sequential read can't evict everything
    // else for a cache entry it will only ever hit once.
    explicit DecryptedBlockCache(size_t capacityBytes = 16 * 1024 * 1024)
        : capacityBytes_(capacityBytes), currentBytes_(0) {}

    // Returns true and fills `out` (exactly `length` bytes, caller-owned
    // buffer) if [physicalByteOffset, physicalByteOffset + length) is cached
    // as an exact match for a single previously-stored range. Promotes the
    // entry to most-recently-used on a hit.
    //
    // Deliberately exact-match only (no partial/overlapping-range
    // reconstruction): disk_read's own batching recomputes the same aligned
    // (offset, length) for a given (sector, count) request every time, so
    // exact-match already captures the common repeat-read case (re-opening
    // a file, re-reading a directory sector, swiping back to a previously
    // decoded image) without the complexity of splicing multiple partial
    // ranges together.
    bool get(uint64_t physicalByteOffset, size_t length, unsigned char* out) {
        const Key key{physicalByteOffset, length};
        auto it = index_.find(key);
        if (it == index_.end()) return false;
        lruOrder_.splice(lruOrder_.begin(), lruOrder_, it->second);
        std::memcpy(out, it->second->data.data(), length);
        return true;
    }

    // Stores `data` (exactly `length` bytes) under
    // [physicalByteOffset, physicalByteOffset + length), evicting
    // least-recently-used entries until capacityBytes_ is respected. If
    // `length` alone exceeds capacityBytes_, the entry is not cached.
    void put(uint64_t physicalByteOffset, size_t length, const unsigned char* data) {
        if (length > capacityBytes_) return;

        const Key key{physicalByteOffset, length};
        auto it = index_.find(key);
        if (it != index_.end()) {
            std::memcpy(it->second->data.data(), data, length);
            lruOrder_.splice(lruOrder_.begin(), lruOrder_, it->second);
            return;
        }

        while (currentBytes_ + length > capacityBytes_ && !lruOrder_.empty()) {
            const Entry& victim = lruOrder_.back();
            currentBytes_ -= victim.data.size();
            index_.erase(Key{victim.physicalByteOffset, victim.data.size()});
            lruOrder_.pop_back();
        }

        lruOrder_.push_front(Entry{physicalByteOffset,
                                    std::vector<unsigned char>(data, data + length)});
        index_[key] = lruOrder_.begin();
        currentBytes_ += length;
    }

    // Drops any cached range that overlaps
    // [firstByteOffset, firstByteOffset + byteLength). Callers (disk_write)
    // must invoke this for the aligned range they just wrote ciphertext to,
    // BEFORE any later disk_read can observe a stale cached plaintext range
    // for the same physical bytes.
    void invalidateRange(uint64_t firstByteOffset, uint64_t byteLength) {
        const uint64_t writeEnd = firstByteOffset + byteLength;
        for (auto it = lruOrder_.begin(); it != lruOrder_.end();) {
            const uint64_t entryStart = it->physicalByteOffset;
            const uint64_t entryEnd = entryStart + it->data.size();
            const bool overlaps = entryStart < writeEnd && firstByteOffset < entryEnd;
            if (overlaps) {
                currentBytes_ -= it->data.size();
                index_.erase(Key{entryStart, it->data.size()});
                it = lruOrder_.erase(it);
            } else {
                ++it;
            }
        }
    }

    void clear() {
        lruOrder_.clear();
        index_.clear();
        currentBytes_ = 0;
    }

    size_t entryCount() const { return index_.size(); }
    size_t currentBytes() const { return currentBytes_; }
    size_t capacityBytes() const { return capacityBytes_; }

private:
    struct Key {
        uint64_t physicalByteOffset;
        size_t length;
        bool operator==(const Key& o) const {
            return physicalByteOffset == o.physicalByteOffset && length == o.length;
        }
    };
    struct KeyHash {
        size_t operator()(const Key& k) const {
            return std::hash<uint64_t>()(k.physicalByteOffset) ^
                   (std::hash<size_t>()(k.length) << 1);
        }
    };
    struct Entry {
        uint64_t physicalByteOffset;
        std::vector<unsigned char> data;
    };

    size_t capacityBytes_;
    size_t currentBytes_;
    std::list<Entry> lruOrder_; // front = most-recent, back = least-recent
    std::unordered_map<Key, std::list<Entry>::iterator, KeyHash> index_;
};