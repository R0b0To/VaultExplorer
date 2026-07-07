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
#include <cstdio>

extern int iterationsForHash(HashId hash, int clampedPim);

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
        expectIterations(h, 2000, 2015000); // this app's clampPim() ceiling
    }

    printf("kdf_table_test: all assertions passed\n");
    return 0;
}
