#include "fat_backend.h"

#include "ff.h"
#include "filesystem_paths.h"

uint64_t recursiveFatFolderSize(int volumeId, const std::string& path) {
    std::string fullPath = drivePaths[volumeId];
    if (!path.empty()) fullPath += '/' + path;

    uint64_t total = 0;
    DIR directory;
    FILINFO entry;
    if (f_opendir(&directory, fullPath.c_str()) != FR_OK) return 0;
    while (f_readdir(&directory, &entry) == FR_OK && entry.fname[0]) {
        if (entry.fattrib & AM_DIR) {
            const std::string child = path.empty() ? std::string(entry.fname)
                                                   : path + '/' + entry.fname;
            total += recursiveFatFolderSize(volumeId, child);
        } else {
            total += entry.fsize;
        }
    }
    f_closedir(&directory);
    return total;
}
