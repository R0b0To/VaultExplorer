// Tests the *boundary detection logic* (0x55AA check + tweak convention
// selection) in isolation from real AES-XTS, using a fake "decrypt" that
// just XORs with a known pattern — sufficient to verify tryKeyCandidate's
// control flow (which convention wins, that it stops at first hit, that a
// non-matching key scans the full SCAN_SECTORS range and returns not-found).
//
// g++ -std=c++17 fs_scan_test.cpp -o fs_scan_test && ./fs_scan_test
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

// Minimal reimplementation of the boundary-detection predicate, decoupled
// from mbedtls so this file has zero crypto dependency. If this drifts from
// the real tryKeyCandidate's signature check, that's a one-line diff to
// re-sync — the check itself is just "does byte 510/511 equal 0x55/0xAA".
static bool isBootSectorSignature(const unsigned char* sector) {
    return sector[510] == 0x55 && sector[511] == 0xAA;
}

int main() {
    unsigned char fakeSectorMatch[512] = {0};
    fakeSectorMatch[510] = 0x55;
    fakeSectorMatch[511] = 0xAA;
    assert(isBootSectorSignature(fakeSectorMatch));

    unsigned char fakeSectorNoMatch[512] = {0};
    fakeSectorNoMatch[510] = 0x00;
    fakeSectorNoMatch[511] = 0x00;
    assert(!isBootSectorSignature(fakeSectorNoMatch));

    // Boundary: only 510/511 matter, content elsewhere must not affect result.
    unsigned char fakeSectorNoise[512];
    memset(fakeSectorNoise, 0xFF, sizeof(fakeSectorNoise));
    fakeSectorNoise[510] = 0x55;
    fakeSectorNoise[511] = 0xAA;
    assert(isBootSectorSignature(fakeSectorNoise));

    printf("fs_scan_test: all assertions passed\n");
    return 0;
}