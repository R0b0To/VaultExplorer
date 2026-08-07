// Host-side test, no Android toolchain required:
//   g++ -std=c++17 decrypted_block_cache_test.cpp -o decrypted_block_cache_test && ./decrypted_block_cache_test
//
// Referenced by the "see io/test/decrypted_block_cache_test.cpp" comment in
// ../decrypted_block_cache.h but never actually written until now. Covers
// the contract disk_read/disk_write depend on: exact-match hits, LRU
// eviction, the oversized-entry bypass, and invalidateRange's overlap
// semantics -- a bug in the latter is exactly what caused writes to appear
// to succeed while a subsequent read kept serving stale cached plaintext
// until relock.
#include "../decrypted_block_cache.h"
#include <cassert>
#include <cstdio>
#include <cstring>

static std::vector<unsigned char> bytesOf(unsigned char fill, size_t n) {
    return std::vector<unsigned char>(n, fill);
}

// --- get()/put(): exact-match only, miss on any offset/length mismatch ---
static void testExactMatchOnly() {
    DecryptedBlockCache cache;
    auto data = bytesOf(0xAB, 512);
    cache.put(1024, 512, data.data());

    unsigned char out[512];
    assert(cache.get(1024, 512, out));
    assert(std::memcmp(out, data.data(), 512) == 0);

    // Same offset, different length -> miss (no partial-range reconstruction).
    assert(!cache.get(1024, 256, out));
    // Overlapping but not identical offset -> miss.
    assert(!cache.get(1000, 512, out));
    // Never-written offset -> miss.
    assert(!cache.get(2048, 512, out));
}

// --- put(): re-storing the same key overwrites data and updates recency,
// without double-counting currentBytes(). ---
static void testPutOverwriteSameKey() {
    DecryptedBlockCache cache;
    auto first = bytesOf(0x11, 256);
    auto second = bytesOf(0x22, 256);

    cache.put(0, 256, first.data());
    assert(cache.entryCount() == 1);
    assert(cache.currentBytes() == 256);

    cache.put(0, 256, second.data());
    assert(cache.entryCount() == 1);          // still one entry, not two
    assert(cache.currentBytes() == 256);      // not double-counted

    unsigned char out[256];
    assert(cache.get(0, 256, out));
    assert(std::memcmp(out, second.data(), 256) == 0); // overwritten, not stale first write
}

// --- put(): an entry larger than total capacity is never cached, and does
// not evict/corrupt whatever was already present. ---
static void testOversizedEntryBypassesCache() {
    DecryptedBlockCache cache(1024);
    auto small = bytesOf(0x33, 100);
    cache.put(0, 100, small.data());

    auto huge = bytesOf(0x44, 2000);
    cache.put(500, 2000, huge.data());

    assert(cache.entryCount() == 1);
    unsigned char out[2000];
    assert(!cache.get(500, 2000, out));   // never stored
    assert(cache.get(0, 100, out));        // untouched
    assert(cache.currentBytes() == 100);
}

// --- put(): eviction is strictly least-recently-used, and get() promotes. ---
static void testLruEvictionOrder() {
    DecryptedBlockCache cache(300); // capacity fits exactly 3x100-byte entries
    auto a = bytesOf('A', 100), b = bytesOf('B', 100), c = bytesOf('C', 100), d = bytesOf('D', 100);

    cache.put(0, 100, a.data());
    cache.put(100, 100, b.data());
    cache.put(200, 100, c.data());
    assert(cache.entryCount() == 3);

    // Touch A so B becomes the least-recently-used entry.
    unsigned char out[100];
    assert(cache.get(0, 100, out));

    // Inserting D must evict B (LRU), not A (just touched) or C (newest).
    cache.put(300, 100, d.data());
    assert(cache.entryCount() == 3);
    assert(cache.get(0, 100, out));    // A survives
    assert(!cache.get(100, 100, out)); // B evicted
    assert(cache.get(200, 100, out));  // C survives
    assert(cache.get(300, 100, out));  // D present
}

// --- invalidateRange(): drops any entry whose byte range overlaps the
// write range at all, including partial overlap at either edge, and never
// touches entries strictly outside it. This is the exact contract
// disk_write depends on to prevent a later disk_read cache hit from
// serving stale plaintext for bytes that were just overwritten. ---
static void testInvalidateRangeOverlapSemantics() {
    DecryptedBlockCache cache;
    auto mk = [](unsigned char fill) { return bytesOf(fill, 100); };

    cache.put(0, 100, mk(1).data());     // [0, 100)
    cache.put(100, 100, mk(2).data());   // [100, 200) -- adjacent, not overlapping a write to [50,150)
    cache.put(300, 100, mk(3).data());   // [300, 400) -- fully separate
    cache.put(140, 20, mk(4).data());    // [140, 160) -- fully inside [100,200)'s neighbor range

    // Write to [50, 150): must invalidate [0,100) (overlaps) and [100,200)
    // (overlaps) and [140,160) (overlaps), but leave [300,400) untouched.
    cache.invalidateRange(50, 100);

    unsigned char out[100];
    assert(!cache.get(0, 100, out));
    assert(!cache.get(100, 100, out));
    assert(!cache.get(140, 20, out));
    assert(cache.get(300, 100, out)); // untouched, disjoint from [50,150)
    assert(cache.entryCount() == 1);
}

// --- invalidateRange(): a write range that exactly abuts a cached range
// (touching but not overlapping) must NOT invalidate it -- half-open
// interval semantics at the boundary. ---
static void testInvalidateRangeAdjacentNotOverlapping() {
    DecryptedBlockCache cache;
    auto data = bytesOf(9, 100);
    cache.put(100, 100, data.data()); // [100, 200)

    // Write to [200, 300): starts exactly where the cached range ends.
    // [100,200) and [200,300) do not overlap under half-open semantics.
    cache.invalidateRange(200, 100);

    unsigned char out[100];
    assert(cache.get(100, 100, out)); // must survive
}

// --- clear(): drops everything and resets accounting. ---
static void testClearResetsState() {
    DecryptedBlockCache cache;
    auto data = bytesOf(7, 64);
    cache.put(0, 64, data.data());
    cache.put(64, 64, data.data());
    assert(cache.entryCount() == 2);

    cache.clear();
    assert(cache.entryCount() == 0);
    assert(cache.currentBytes() == 0);
    unsigned char out[64];
    assert(!cache.get(0, 64, out));
}

int main() {
    testExactMatchOnly();
    testPutOverwriteSameKey();
    testOversizedEntryBypassesCache();
    testLruEvictionOrder();
    testInvalidateRangeOverlapSemantics();
    testInvalidateRangeAdjacentNotOverlapping();
    testClearResetsState();
    std::printf("decrypted_block_cache_test: all tests passed\n");
    return 0;
}
