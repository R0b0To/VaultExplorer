// Host-side test, no Android toolchain required:
//   g++ -std=c++17 kdf_table_test.cpp kdf_table.cpp -o kdf_table_test && ./kdf_table_test
//
// Pins iterationsForHash() to the exact values produced by upstream
// VeraCrypt's Pkcs5.c::get_pkcs5_iteration_count() on the non-boot path
// (bBoot = false), which is the only path this app exercises. If this
// test starts failing, someone has changed the table to diverge per hash
// again — don't "fix" it back to that; re-read the comment in
// kdf_table.cpp first.
#include "../cipher_shim.h"
#include <cassert>
#include <cstdint>
#include <cstdio>

extern int iterationsForHash(HashId hash, int clampedPim);
extern int clampPim(int pim);
extern void argon2ParamsForPim(int pim, uint32_t& memoryKiB, uint32_t& timeCost, uint32_t& parallelism);

static void expectIterations(HashId hash, int pim, int expected) {
    const int got = iterationsForHash(hash, pim);
    assert(got == expected);
}

int main() {
    const HashId allHashes[] = {
        HashId::kSha512, HashId::kSha256, HashId::kWhirlpool,
        HashId::kStreebog, HashId::kBlake2s256,
    };

    // pim == 0 -> baseline 500,000 for every hash (non-boot path).
    for (HashId h : allHashes) {
        expectIterations(h, 0, 500000);
    }

    // pim > 0 -> 15000 + pim*1000, identical formula for every hash.
    for (HashId h : allHashes) {
        expectIterations(h, 1,    16000);
        expectIterations(h, 12,   27000);   // VeraCrypt's own PIM default
        expectIterations(h, 500,  515000);
        expectIterations(h, 2000, 2015000);
        // PIMs above 2000 used to be silently clamped to 2000, so such volumes
        // could neither be unlocked here nor opened elsewhere after creation.
        expectIterations(h, 2001,    2016000);
        expectIterations(h, 5000,    5015000);
        expectIterations(h, 100000,  100015000);
        // Upstream MAX_PIM_VALUE: the largest PIM whose iteration count is still a positive int.
        expectIterations(h, 2147468, 2147483000);
    }

    // clampPim(): only negatives and values above upstream's MAX_PIM_VALUE are touched.
    assert(clampPim(-7) == 0);
    assert(clampPim(0) == 0);
    assert(clampPim(12) == 12);
    assert(clampPim(2000) == 2000);
    assert(clampPim(2001) == 2001);
    assert(clampPim(5000) == 5000);
    assert(clampPim(2147468) == 2147468);
    assert(clampPim(2147469) == 2147468);
    assert(clampPim(2147483647) == 2147468);

    // Argon2id parameters, pinned to upstream get_argon2_params() (parallelism is always 1).
    struct { int pim; uint32_t t; uint32_t memKiB; } argon[] = {
        {0, 6, 425984}, {1, 3, 65536}, {12, 6, 425984}, {31, 13, 1048576},
        {32, 14, 1048576}, {100, 82, 1048576}, {2001, 1983, 1048576}, {5000, 4982, 1048576},
    };
    for (const auto& a : argon) {
        uint32_t mem = 0, t = 0, par = 0;
        argon2ParamsForPim(clampPim(a.pim), mem, t, par);
        assert(mem == a.memKiB && t == a.t && par == 1);
    }

    printf("kdf_table_test: all assertions passed\n");
    return 0;
}
