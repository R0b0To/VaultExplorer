// End-to-end host test: a real FAT32/exFAT/NTFS image is encrypted into a synthetic VeraCrypt data area
// (XTS data unit = container offset / 512), then analysed THROUGH the decrypting reader; the result must equal the
// analysis of the plain image. usage: vc_outer_reader_test <plain image>
#include "../vc_outer_reader.h"
#include <cassert>
#include <cstdio>
#include <vector>
int main(int argc, char** argv) {
    FILE* f = fopen(argv[1], "rb"); assert(f);
    std::vector<unsigned char> plain; { unsigned char b[65536]; size_t n; while ((n = fread(b, 1, sizeof b, f)) > 0) plain.insert(plain.end(), b, b + n); }
    fclose(f);
    const uint64_t dataOffset = 131072, volumeBytes = plain.size() - plain.size() % 512;
    for (CascadeId c : {CascadeId::kAes, CascadeId::kSerpentTwofishAes}) {
        unsigned char key[192]; for (int i = 0; i < 192; i++) key[i] = (unsigned char)(i * 7 + 3);
        CascadeContext ctx; assert(cascadeSetKeys(ctx, c, key, cascadeSpecFor(c).layerCount * 64));
        std::vector<unsigned char> container(dataOffset + volumeBytes + 131072, 0x11);
        for (uint64_t o = 0; o < volumeBytes; o += 512) cascadeEncryptSector(ctx, (dataOffset + o) / 512, &plain[o], &container[dataOffset + o]);
        VcReadFn plainRd = [&](uint64_t o, unsigned char* b, size_t n) { if (o + n > plain.size()) return false; memcpy(b, &plain[o], n); return true; };
        VcReadFn encRd = vcMakeOuterReader(&ctx, dataOffset, volumeBytes, [&](uint64_t o, unsigned char* b, size_t n) {
            if (o + n > container.size()) return false; memcpy(b, &container[o], n); return true; });
        VcFsTail a, b;
        assert(vcAnalyzeFsTail(plainRd, &a) && vcAnalyzeFsTail(encRd, &b));
        assert(a.kind == b.kind && a.clusterSize == b.clusterSize && a.freeTailClusters == b.freeTailClusters);
        // unaligned reads across sector boundaries
        unsigned char x[100], y[100];
        assert(plainRd(1000, x, 100) && encRd(1000, y, 100) && !memcmp(x, y, 100));
        assert(!encRd(volumeBytes - 50, y, 100));
    }
    printf("vc_outer_reader_test: ok (%s)\n", argv[1]);
    return 0;
}
