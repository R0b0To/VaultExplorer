// The default engine hooks (platform/engine_hooks_default.cpp) link on their own and behave as
// documented: nothing cancelled, nothing tracked, USB unreachable, progress accepted and ignored.
// Calling the *declarations* from platform/engine_hooks.h also proves that header needs no JNI or
// Android type: this translation unit is built with neither on the include path.
#include <cstdio>
#include <initializer_list>

#include "platform/engine_hooks.h"

static int g_checks = 0, g_failed = 0;
#define CHECK(cond) do { g_checks++; if (!(cond)) { g_failed++; std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); } } while (0)

int main() {
    // progress and notifications are accepted (and dropped); the defaulted trailing arguments compile
    reportUnlockProgress(0, 1, 2, 3, 4);
    reportUnlockProgress(0, 1, 2, 3, 4, 5, 6);
    reportSplitJoinProgress(7, 100, 200);
    notifyHiddenVolumeProtectionTriggered(1);
    reportRepairLog(3, "message");
    reportCopyProgress(1, 10); reportImportChunkProgress(1, 10); reportExportChunkProgress(1, 10);
    reportWriteBackChunkProgress(1, 10); reportExtractChunkProgress(1, 10);
    yieldContainerWriteLock(2); yieldContainerCopyLocks(2, 3);

    // nothing is ever cancelled or tracked
    for (int op : {-1, 0, 1, 99}) {
        CHECK(!isSplitJoinCancelled(op)); CHECK(!isCopyCancelled(op));
        CHECK(!isImportCancelled(op) && !isImportTracking(op));
        CHECK(!isExportCancelled(op) && !isExportTracking(op));
        CHECK(!isWriteBackCancelled(op) && !isExtractCancelled(op));
    }

    // no USB device is reachable: every access reports failure and leaves the buffer alone
    unsigned char buf[512] = {0xAB};
    const unsigned char out[512] = {0};
    CHECK(!usbReadSectors(0, 0, 1, buf) && buf[0] == 0xAB);
    CHECK(!usbWriteSectors(0, 0, 1, out));
    CHECK(!usbSyncDevice(0));

    std::printf("\n%d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
