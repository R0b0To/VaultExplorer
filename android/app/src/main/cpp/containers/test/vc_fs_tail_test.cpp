// vc_fs_tail_test <image>   prints:  <kind> <clusterSize> <freeTailClusters>
// (verification/oracle_fs_tail.py builds the images and compares with an independent parser).
#include "../vc_fs_tail.h"
#include <algorithm>
#include <cstdio>
int main(int argc, char** argv) {
    if (argc < 2) return 2;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 2;
    VcReadFn rd = [f](uint64_t off, unsigned char* b, size_t n) {
        return fseeko(f, (off_t)off, SEEK_SET) == 0 && fread(b, 1, n, f) == n; };
    VcFsTail t;
    if (!vcAnalyzeFsTail(rd, &t)) { printf("unsupported\n"); return 1; }
    printf("%d %llu %llu\n", (int)t.kind, (unsigned long long)t.clusterSize, (unsigned long long)t.freeTailClusters);
    return 0;
}
