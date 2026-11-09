#pragma once
// Free-space initialisation for a newly created VeraCrypt volume ("full
// format"): the data area is overwritten with encrypted zeros so unused space
// looks like ciphertext.
//
// The zeros must be encrypted with a TEMPORARY random key, never the volume's
// real data key (VeraCrypt: Core->RandomizeEncryptionAlgorithmKey before the
// free-space pass). With the real key, untouched free space decrypts to zeros,
// while any area written under another key -- the hidden volume -- decrypts to
// noise; whoever is given the outer password could then see where the hidden
// volume starts and ends. With a throwaway key all unwritten space decrypts to
// noise under the real key as well, and the filesystem formatter's own writes
// (done afterwards with the real key) are the only sectors that decode.
#include <cstddef>
#include <cstdint>
#include <memory>
#include "crypto/cascade.h"
#include "crypto/user_entropy.h"

namespace vcfill {

// Writes encrypted zeros over sectors [firstSector, firstSector + sectorCount)
// of the container (512-byte sectors, numbered from the container's byte 0)
// in batches of `batchSectors`.
//   sink(uint64_t byteOffsetInContainer, const unsigned char* data, size_t n) -> bool
// The temporary key exists only inside this call and is wiped before it returns.
template <typename SinkFn>
bool fillWithRandomizedKey(CascadeId cipher, int masterKeyLen, uint64_t firstSector,
                           uint64_t sectorCount, uint64_t batchSectors, SinkFn&& sink) {
    if (batchSectors == 0) return false;
    CascadeContext fillCtx;
    {
        unsigned char tmpKey[192] = {0};
        const bool ok = masterKeyLen > 0 && masterKeyLen <= static_cast<int>(sizeof(tmpKey)) &&
                        userentropy::fillRandom(tmpKey, static_cast<size_t>(masterKeyLen)) &&
                        cascadeSetKeys(fillCtx, cipher, tmpKey, masterKeyLen);
        volatile unsigned char* q = tmpKey;
        for (size_t i = 0; i < sizeof(tmpKey); ++i) q[i] = 0;
        if (!ok) return false;
    }

    const unsigned char zeroSector[512] = {0};
    std::unique_ptr<unsigned char[]> batch(new unsigned char[static_cast<size_t>(batchSectors) * 512]);
    for (uint64_t done = 0; done < sectorCount;) {
        const uint64_t rem = sectorCount - done;
        const uint64_t count = rem < batchSectors ? rem : batchSectors;
        for (uint64_t i = 0; i < count; ++i) {
            cascadeEncryptSector(fillCtx, firstSector + done + i, zeroSector, batch.get() + i * 512);
        }
        if (!sink((firstSector + done) * 512, batch.get(), static_cast<size_t>(count) * 512)) return false;
        done += count;
    }
    return true;
}

}  // namespace vcfill
