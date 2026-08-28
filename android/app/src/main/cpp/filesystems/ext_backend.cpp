#include "ext_backend.h"
#include "dir_entry_wire.h"
#include <algorithm>
#include <android/log.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <memory>
#include <strings.h>
#include <unordered_set>
#include <unistd.h>
#include "diskio.h"
#include "volume_state.h"
#include "filesystems/stream_handles.h"
namespace { constexpr size_t kIoBufferSize = 2097152; }
#define EXT_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)
#define EXT_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "VaultExplorer_C++", __VA_ARGS__)
bool extResolvePath(ext2_filsys fs, const std::string& path, ext2_ino_t* inode) {
    std::string relative = path;
    while (!relative.empty() && relative.front() == '/') relative.erase(relative.begin());
    if (relative.empty()) { *inode = EXT2_ROOT_INO; return true; }
    return ext2fs_namei_follow(fs, EXT2_ROOT_INO, EXT2_ROOT_INO, relative.c_str(), inode) == 0;
}
int extDirectoryEntry(ext2_ino_t, int, struct ext2_dir_entry* entry, int, int, char*, void* data) {
    auto* context = static_cast<ExtDirContext*>(data);
    if (!entry->inode || context->results->size() >= EXT_DIRECTORY_MAX_ENTRIES) return 0;
    std::string name(entry->name, ext2fs_dirent_name_len(entry));
    if (name == "." || name == "..") return 0;
    struct ext2_inode inode{};
    if (ext2fs_read_inode(context->fs, entry->inode, &inode) != 0) return 0;
    const bool isDir = LINUX_S_ISDIR(inode.i_mode);
    const uint64_t size = (static_cast<uint64_t>(inode.i_size_high) << 32) | inode.i_size;
    context->results->push_back(encodeDirEntryWire(name, isDir, size, inode.i_mtime));
    return 0;
}
namespace {
struct ExtSizeContext {
    ext2_filsys fs;
    uint64_t totalSize = 0;
};
int extSizeEntryCallback(ext2_ino_t, int, struct ext2_dir_entry* entry, int, int, char*, void* data) {
    auto* context = static_cast<ExtSizeContext*>(data);
    if (!entry->inode) return 0;
    std::string name(entry->name, ext2fs_dirent_name_len(entry));
    if (name == "." || name == "..") return 0;
    struct ext2_inode inode{};
    if (ext2fs_read_inode(context->fs, entry->inode, &inode) != 0) return 0;
    if (LINUX_S_ISDIR(inode.i_mode)) {
        ExtSizeContext childContext{context->fs, 0};
        ext2fs_dir_iterate2(context->fs, entry->inode, 0, nullptr, extSizeEntryCallback, &childContext);
        context->totalSize += childContext.totalSize;
    } else {
        const uint64_t size = (static_cast<uint64_t>(inode.i_size_high) << 32) | inode.i_size;
        context->totalSize += size;
    }
    return 0;
}
}
uint64_t recursiveExtFolderSize(int volumeId, const std::string& path) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return 0;
    VolumeState& v = volumes[volumeId];
    if (!v.extFs) return 0;
    ext2_ino_t dirIno = 0;
    if (!extResolvePath(v.extFs, path, &dirIno)) return 0;
    ExtSizeContext context{v.extFs, 0};
    ext2fs_dir_iterate2(v.extFs, dirIno, 0, nullptr, extSizeEntryCallback, &context);
    return context.totalSize;
}
bool extOpenFile(ext2_filsys fs, const std::string& path, bool write, bool create, ext2_file_t* out) {
    ext2_ino_t inodeNumber = 0;
    if (!extResolvePath(fs, path, &inodeNumber)) {
        if (!create) {
            EXT_LOGE("extOpenFile: path resolution failed (directory entry missing or unreadable): %s",
                     path.c_str());
            return false;
        }
        const size_t slash = path.find_last_of('/');
        const std::string parentPath = slash == std::string::npos ? "" : path.substr(0, slash);
        const std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
        ext2_ino_t parent = 0;
        if (name.empty() || !extResolvePath(fs, parentPath, &parent)) return false;
        struct ext2_inode inode{};
        if (ext2fs_new_inode(fs, parent, LINUX_S_IFREG | 0644, nullptr, &inodeNumber) != 0) return false;
        inode.i_mode = LINUX_S_IFREG | 0644;
        inode.i_links_count = 1;
        if (ext2fs_write_new_inode(fs, inodeNumber, &inode) != 0) return false;

        errcode_t linkErr = ext2fs_link(fs, parent, name.c_str(), inodeNumber, EXT2_FT_REG_FILE);
        if (linkErr == EXT2_ET_DIR_NO_SPACE) {
            if (ext2fs_expand_dir(fs, parent) == 0) {
                linkErr = ext2fs_link(fs, parent, name.c_str(), inodeNumber, EXT2_FT_REG_FILE);
            }
        }
        if (linkErr != 0) {
            EXT_LOGE("extOpenFile: ext2fs_link failed for '%s' in parent %u err=%lu (%s)",
                     name.c_str(), parent, (unsigned long)linkErr, error_message(linkErr));
            return false;
        }
        ext2fs_inode_alloc_stats2(fs, inodeNumber, +1, 0);
    }
    const errcode_t openErr = ext2fs_file_open(fs, inodeNumber, write ? EXT2_FILE_WRITE : 0, out);
    if (openErr != 0) {
        EXT_LOGE("extOpenFile: ext2fs_file_open failed for '%s' inode=%u err=%lu (%s)",
                 path.c_str(), inodeNumber, (unsigned long)openErr, error_message(openErr));
        return false;
    }
    return true;
}
bool extWriteFromHostFile(ext2_filsys fs, const std::string& path, const char* source,
                           const CopyProgressCallback& onProgress) {
    ext2_file_t file = nullptr;
    if (!extOpenFile(fs, path, true, true, &file)) return false;
    bool ok = ext2fs_file_set_size2(file, 0) == 0;
    std::ifstream input(source, std::ios::binary);
    std::unique_ptr<unsigned char[]> buffer(new unsigned char[kIoBufferSize]);
    bool cancelled = false;
    while (ok && !cancelled && input) {
        input.read(reinterpret_cast<char*>(buffer.get()), kIoBufferSize);
        const std::streamsize count = input.gcount();
        if (count <= 0) break;
        unsigned int written = 0;
        ok = ext2fs_file_write(file, buffer.get(), static_cast<unsigned int>(count), &written) == 0 &&
             written == static_cast<unsigned int>(count);
        if (ok && onProgress && !onProgress(static_cast<uint64_t>(written))) cancelled = true;
    }
    ok = ok && !cancelled && input.eof() && ext2fs_file_flush(file) == 0;
    ext2fs_file_close(file);
    return ok;
}
bool extExtractToHostFile(ext2_filsys fs, const std::string& path, const char* destination) {
    ext2_file_t file = nullptr;
    if (!extOpenFile(fs, path, false, false, &file)) return false;
    std::ofstream output(destination, std::ios::binary | std::ios::trunc);
    std::unique_ptr<unsigned char[]> buffer(new unsigned char[kIoBufferSize]);
    bool ok = output.is_open();
    while (ok) {
        unsigned int got = 0;
        if (ext2fs_file_read(file, buffer.get(), kIoBufferSize, &got) != 0) { ok = false; break; }
        if (!got) break;
        output.write(reinterpret_cast<const char*>(buffer.get()), got);
        ok = output.good();
    }
    ext2fs_file_close(file);
    return ok;
}
namespace {
bool extTransfer(int volumeId, uint64_t offset, void* data, size_t bytes, bool write) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES || bytes == 0) return bytes == 0;
    const auto& volume = volumes[volumeId];
    if (offset > volume.dataAreaLengthBytes || bytes > volume.dataAreaLengthBytes - offset)
        return false;
    const uint32_t sectorSize = (volume.luksSectorSize >= 512) ? volume.luksSectorSize : 512;
    const uint64_t firstSector = offset / sectorSize;
    const uint64_t lastSector = (offset + bytes + sectorSize - 1) / sectorSize;
    const size_t sectorBytes = static_cast<size_t>(lastSector - firstSector) * sectorSize;
    thread_local std::vector<unsigned char> sectors;
    if (sectors.size() < sectorBytes) sectors.resize(sectorBytes);
    const size_t inSector = static_cast<size_t>(offset % sectorSize);
    const bool wholeSectors = inSector == 0 && bytes % sectorSize == 0;
    if (!write || !wholeSectors) {
        if (disk_read(static_cast<BYTE>(volumeId), sectors.data(), firstSector,
                      static_cast<UINT>(lastSector - firstSector)) != RES_OK)
            return false;
    }
    if (write) {
        std::memcpy(sectors.data() + inSector, data, bytes);
        return disk_write(static_cast<BYTE>(volumeId), sectors.data(), firstSector,
                          static_cast<UINT>(lastSector - firstSector)) == RES_OK;
    }
    std::memcpy(data, sectors.data() + inSector, bytes);
    return true;
}
errcode_t extIoOpenBound(const char* name, int flags, io_channel* out);
errcode_t extIoOpen(const char* name, int, io_channel* out) {
    if (!name || !out) return EXT2_ET_INVALID_ARGUMENT;
    char* end = nullptr;
    const long volumeId = std::strtol(name, &end, 10);
    if (!end || *end || volumeId < 0 || volumeId >= FF_VOLUMES) return EXT2_ET_BAD_DEVICE_NAME;
    auto* channel = static_cast<io_channel>(std::calloc(1, sizeof(struct struct_io_channel)));
    auto* privateId = new int(static_cast<int>(volumeId));
    if (!channel || !privateId) { std::free(channel); delete privateId; return EXT2_ET_NO_MEMORY; }
    channel->magic = EXT2_ET_MAGIC_IO_CHANNEL;
    channel->name = strdup(name);
    channel->block_size = 1024;
    channel->refcount = 1;
    channel->private_data = privateId;
    *out = channel;
    return 0;
}
errcode_t extIoClose(io_channel channel) {
    if (!channel) return EXT2_ET_INVALID_ARGUMENT;
    delete static_cast<int*>(channel->private_data);
    std::free(channel->name);
    std::free(channel);
    return 0;
}
errcode_t extIoSetBlockSize(io_channel channel, int size) {
    if (!channel || size < 512 || size % 512 != 0) return EXT2_ET_INVALID_ARGUMENT;
    channel->block_size = size;
    return 0;
}
errcode_t extIoTransfer(io_channel channel, unsigned long long block, int count,
                        void* data, bool write) {
    if (!channel || !channel->private_data || !data || count == 0) return EXT2_ET_INVALID_ARGUMENT;
    const uint64_t bytes = count < 0 ? static_cast<uint64_t>(-static_cast<long long>(count))
        : static_cast<uint64_t>(count) * static_cast<uint64_t>(channel->block_size);
    const uint64_t offset = block * static_cast<uint64_t>(channel->block_size);
    const int volumeId = *static_cast<int*>(channel->private_data);
    if (!extTransfer(volumeId, offset, data, static_cast<size_t>(bytes), write))
        return write ? EXT2_ET_SHORT_WRITE : EXT2_ET_SHORT_READ;
    return 0;
}
errcode_t extIoRead(io_channel c, unsigned long b, int n, void* d) { return extIoTransfer(c, b, n, d, false); }
errcode_t extIoWrite(io_channel c, unsigned long b, int n, const void* d) { return extIoTransfer(c, b, n, const_cast<void*>(d), true); }
errcode_t extIoRead64(io_channel c, unsigned long long b, int n, void* d) { return extIoTransfer(c, b, n, d, false); }
errcode_t extIoWrite64(io_channel c, unsigned long long b, int n, const void* d) { return extIoTransfer(c, b, n, const_cast<void*>(d), true); }
errcode_t extIoWriteByte(io_channel c, unsigned long offset, int n, const void* d) {
    if (!c || !c->private_data || n < 0) return EXT2_ET_INVALID_ARGUMENT;
    return extTransfer(*static_cast<int*>(c->private_data), offset, const_cast<void*>(d), static_cast<size_t>(n), true)
        ? 0 : EXT2_ET_SHORT_WRITE;
}
errcode_t extIoFlush(io_channel c) {
    if (!c || !c->private_data) return EXT2_ET_INVALID_ARGUMENT;
    const auto& volume = volumes[*static_cast<int*>(c->private_data)];
    return (!volume.isUsbSource && volume.fd >= 0 && fsync(volume.fd) != 0) ? EXT2_ET_SHORT_WRITE : 0;
}
struct_io_manager encryptedExtIoManager = {
    EXT2_ET_MAGIC_IO_MANAGER, "vaultexplorer-encrypted", extIoOpenBound, extIoClose,
    extIoSetBlockSize, extIoRead, extIoWrite, extIoFlush, extIoWriteByte,
    nullptr, nullptr, extIoRead64, extIoWrite64, nullptr, nullptr, nullptr, {0}
};
errcode_t extIoOpenBound(const char* name, int flags, io_channel* out) {
    const errcode_t result = extIoOpen(name, flags, out);
    if (!result) (*out)->manager = &encryptedExtIoManager;
    return result;
}
}
bool formatExtVolume(int volumeId, const char* variant) {
    const bool ext3 = strncasecmp(variant, "ext3", 4) == 0;
    const bool ext4 = strncasecmp(variant, "ext4", 4) == 0;
    const uint64_t totalBlocks = volumes[volumeId].dataAreaLengthBytes / 4096;
    if (totalBlocks < 1024) return false;
    ext2_super_block params{};
    params.s_rev_level = EXT2_DYNAMIC_REV;
    params.s_inode_size = 256;
    params.s_first_ino = EXT2_GOOD_OLD_FIRST_INO;
    params.s_log_block_size = 2;
    params.s_blocks_per_group = 32768;
    params.s_inodes_per_group = 2048;
    ext2fs_blocks_count_set(&params, totalBlocks);
    params.s_feature_incompat = 0x0002;
    params.s_feature_ro_compat = 0x0001;
    params.s_feature_compat = 0x0020;
    if (ext4) params.s_feature_incompat |= 0x0040;
    char deviceName[16];
    std::snprintf(deviceName, sizeof(deviceName), "%d", volumeId);
    ext2_filsys fs = nullptr;
    if (ext2fs_initialize(deviceName, 0, &params, &encryptedExtIoManager, &fs) != 0) return false;
    fs->flags |= EXT2_FLAG_RW;
    fs->super->s_state = 1;
    fs->super->s_max_mnt_count = 20;
    fs->super->s_lastcheck = static_cast<uint32_t>(time(nullptr));
    fs->super->s_mtime = static_cast<uint32_t>(time(nullptr));
    fs->super->s_wtime = static_cast<uint32_t>(time(nullptr));
    unsigned char uuid[16];
    if (FILE* random = fopen("/dev/urandom", "rb")) {
        fread(uuid, 1, sizeof(uuid), random);
        uuid[6] = (uuid[6] & 0x0F) | 0x40;
        uuid[8] = (uuid[8] & 0x3F) | 0x80;
        std::memcpy(fs->super->s_uuid, uuid, sizeof(uuid));
        fclose(random);
    }
    std::strncpy(reinterpret_cast<char*>(fs->super->s_last_mounted), "/", sizeof(fs->super->s_last_mounted));
    fs->super->s_r_blocks_count = 0;
    if (ext2fs_allocate_tables(fs) != 0) { ext2fs_close(fs); return false; }
    ext2fs_write_inode_bitmap(fs);
    ext2fs_write_block_bitmap(fs);
    ext2fs_mkdir(fs, EXT2_ROOT_INO, EXT2_ROOT_INO, nullptr);
    ext2_inode root{};
    if (ext2fs_read_inode(fs, EXT2_ROOT_INO, &root) == 0) {
        root.i_mode = LINUX_S_IFDIR | 0777;
        root.i_uid = root.i_gid = 0;
        root.i_links_count = 2;
        root.i_atime = root.i_mtime = root.i_ctime = static_cast<uint32_t>(time(nullptr));
        ext2fs_write_inode(fs, EXT2_ROOT_INO, &root);
    }
    ext2fs_mkdir(fs, EXT2_ROOT_INO, 0, "lost+found");
    if ((ext3 || ext4) && totalBlocks > 2048) {
        ext2fs_journal_params journal{};
        journal.num_journal_blocks = static_cast<blk_t>(std::min<uint64_t>(8192, totalBlocks / 32));
        if (journal.num_journal_blocks < 1024) journal.num_journal_blocks = 1024;
        ext2fs_add_journal_inode3(fs, &journal, 0, 0);
    }
    for (ext2_ino_t inode = EXT2_BAD_INO; inode < fs->super->s_first_ino; ++inode) {
        if (!ext2fs_test_inode_bitmap2(fs->inode_map, inode))
            ext2fs_inode_alloc_stats2(fs, inode, +1, 0);
    }
    ext2fs_mark_ib_dirty(fs);
    ext2fs_mark_bb_dirty(fs);
    ext2fs_mark_super_dirty(fs);
    ext2fs_flush(fs);
    ext2fs_close(fs);
    return true;
}
bool ensureExtBitmapsLoaded(int volumeId) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    VolumeState& volume = volumes[volumeId];
    if (volume.extBitmapsLoaded) return true;
    if (!volume.extFs) return false;
    const errcode_t bitmapError = ext2fs_read_bitmaps(volume.extFs);
    if (bitmapError != 0) {
        EXT_LOGI("ensureExtBitmapsLoaded: ext2fs_read_bitmaps failed on volume %d: %s (err=%lu)",
                 volumeId, error_message(bitmapError), static_cast<unsigned long>(bitmapError));
        return false;
    }
    volume.extBitmapsLoaded = true;
    return true;
}
bool mountExtVolume(int volumeId) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    auto& volume = volumes[volumeId];
    const std::string deviceName = std::to_string(volumeId);
    volume.fsType = VolumeState::FS_EXT;
    const int openFlags = (volume.readOnly ? 0 : EXT2_FLAG_RW) | EXT2_FLAG_64BITS;
    const errcode_t openError = ext2fs_open(deviceName.c_str(), openFlags,
                                             0, 0, &encryptedExtIoManager, &volume.extFs);
    if (openError != 0) {
        EXT_LOGI("mountExtVolume: ext2fs_open failed on volume %d: %s (err=%lu)", volumeId,
                 error_message(openError), static_cast<unsigned long>(openError));
        volume.fsType = VolumeState::FS_UNKNOWN;
        return false;
    }
    volume.extBitmapsLoaded = false;
    volume.fsMounted = true;
    ext2_super_block* superblock = volume.extFs->super;
    const bool needsRecovery = EXT2_HAS_INCOMPAT_FEATURE(superblock, EXT3_FEATURE_INCOMPAT_RECOVER);
    const bool hasJournal = EXT2_HAS_COMPAT_FEATURE(superblock, EXT3_FEATURE_COMPAT_HAS_JOURNAL);
    EXT_LOGI("mountExtVolume: volume %d blockSize=%d blocks=%llu freeBlocks=%llu hasJournal=%d needsRecovery=%d",
             volumeId, EXT2_BLOCK_SIZE(superblock),
             static_cast<unsigned long long>(ext2fs_blocks_count(superblock)),
             static_cast<unsigned long long>(ext2fs_free_blocks_count(superblock)),
             hasJournal ? 1 : 0, needsRecovery ? 1 : 0);
    return true;
}
std::string extGetFilesystemLabel(int volumeId) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return std::string();
    VolumeState& volume = volumes[volumeId];
    if (!volume.extFs || !volume.extFs->super) return std::string();
    ext2_super_block* superblock = volume.extFs->super;
    const bool hasExt4Feature =
        EXT2_HAS_INCOMPAT_FEATURE(superblock, EXT3_FEATURE_INCOMPAT_EXTENTS) ||
        EXT2_HAS_INCOMPAT_FEATURE(superblock, EXT4_FEATURE_INCOMPAT_64BIT) ||
        EXT2_HAS_RO_COMPAT_FEATURE(superblock, EXT4_FEATURE_RO_COMPAT_HUGE_FILE) ||
        EXT2_HAS_RO_COMPAT_FEATURE(superblock, EXT4_FEATURE_RO_COMPAT_GDT_CSUM);
    if (hasExt4Feature) return "ext4";
    if (EXT2_HAS_COMPAT_FEATURE(superblock, EXT3_FEATURE_COMPAT_HAS_JOURNAL)) return "ext3";
    return "ext2";
}

bool extIsDirty(int volumeId) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    VolumeState& volume = volumes[volumeId];
    if (!volume.extFs || !volume.extFs->super) return false;
    ext2_super_block* sb = volume.extFs->super;
    const bool notMarkedValid = (sb->s_state & EXT2_VALID_FS) == 0;
    const bool hasErrorFlag = (sb->s_state & EXT2_ERROR_FS) != 0;
    const bool needsJournalRecovery = EXT2_HAS_INCOMPAT_FEATURE(sb, EXT3_FEATURE_INCOMPAT_RECOVER);
    return notMarkedValid || hasErrorFlag || needsJournalRecovery;
}
bool extClearDirtyState(int volumeId) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    VolumeState& volume = volumes[volumeId];
    if (!volume.extFs || !volume.extFs->super || volume.readOnly) return false;
    ext2_super_block* sb = volume.extFs->super;
    sb->s_state |= EXT2_VALID_FS;
    sb->s_state &= ~EXT2_ERROR_FS;
    sb->s_lastcheck = static_cast<uint32_t>(time(nullptr));
    ext2fs_mark_super_dirty(volume.extFs);
    const errcode_t flushError = ext2fs_flush(volume.extFs);
    if (flushError != 0) {
        EXT_LOGI("extClearDirtyState: ext2fs_flush failed on volume %d: %s (err=%lu)", volumeId,
                 error_message(flushError), static_cast<unsigned long>(flushError));
        return false;
    }
    return true;
}
namespace {
struct ExtBlockBitmapRebuild {
    ext2_filsys fs;
    ext2fs_block_bitmap map;
    bool valid = true;
};
int extMarkRebuiltBlock(ext2_filsys fs, blk64_t* block, e2_blkcnt_t,
                         blk64_t, int, void* data) {
    auto* rebuild = static_cast<ExtBlockBitmapRebuild*>(data);
    if (*block == 0) return 0;
    if (*block < fs->super->s_first_data_block || *block >= ext2fs_blocks_count(fs->super)) {
        rebuild->valid = false;
        return 0;
    }
    ext2fs_mark_block_bitmap2(rebuild->map, *block);
    return 0;
}
bool extBuildAllocatedBlockBitmap(ext2_filsys fs, ext2fs_block_bitmap* outMap) {
    ext2fs_block_bitmap rebuilt = nullptr;
    if (ext2fs_allocate_block_bitmap(fs, "VaultExplorer rebuilt block map", &rebuilt) != 0) return false;
    ext2fs_clear_block_bitmap(rebuilt);
    const blk64_t totalBlocks = ext2fs_blocks_count(fs->super);
    for (dgrp_t group = 0; group < fs->group_desc_count; ++group) {
        ext2fs_reserve_super_and_bgd(fs, group, rebuilt);
        ext2fs_mark_block_bitmap2(rebuilt, ext2fs_block_bitmap_loc(fs, group));
        ext2fs_mark_block_bitmap2(rebuilt, ext2fs_inode_bitmap_loc(fs, group));
        const blk64_t inodeTable = ext2fs_inode_table_loc(fs, group);
        for (unsigned int index = 0; index < fs->inode_blocks_per_group; ++index) {
            if (inodeTable + index < totalBlocks) ext2fs_mark_block_bitmap2(rebuilt, inodeTable + index);
        }
    }
    ExtBlockBitmapRebuild context{fs, rebuilt};
    for (ext2_ino_t ino = 1; ino <= fs->super->s_inodes_count; ++ino) {
        if (!ext2fs_test_inode_bitmap2(fs->inode_map, ino)) continue;
        struct ext2_inode inode{};
        if (ext2fs_read_inode(fs, ino, &inode) != 0) {
            context.valid = false;
            break;
        }
        const blk64_t aclBlock = ext2fs_file_acl_block(fs, &inode);
        if (aclBlock) {
            if (aclBlock < fs->super->s_first_data_block || aclBlock >= totalBlocks) {
                context.valid = false;
                break;
            }
            ext2fs_mark_block_bitmap2(rebuilt, aclBlock);
        }
        const errcode_t iterateError = ext2fs_block_iterate3(fs, ino, BLOCK_FLAG_READ_ONLY, nullptr,
                                                              extMarkRebuiltBlock, &context);
        if (iterateError != 0 && iterateError != EXT2_ET_INLINE_DATA_CANT_ITERATE) {
            context.valid = false;
            break;
        }
    }
    if (!context.valid) {
        ext2fs_free_block_bitmap(rebuilt);
        return false;
    }
    *outMap = rebuilt;
    return true;
}
bool extReconcileFreeBlockCounts(int volumeId, bool apply) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    VolumeState& volume = volumes[volumeId];
    if (!volume.extFs || !volume.extFs->super || (apply && volume.readOnly) ||
        !ensureExtBitmapsLoaded(volumeId) || !volume.extFs->block_map) {
        return false;
    }
    ext2_filsys fs = volume.extFs;
    ext2fs_block_bitmap rebuilt = nullptr;
    if (!extBuildAllocatedBlockBitmap(fs, &rebuilt)) return false;
    const bool bitmapDiffers = ext2fs_compare_block_bitmap(fs->block_map, rebuilt) != 0;
    blk64_t totalFree = 0;
    bool differs = false;
    std::vector<uint32_t> freeCounts(fs->group_desc_count);
    for (dgrp_t group = 0; group < fs->group_desc_count; ++group) {
        const blk64_t first = ext2fs_group_first_block2(fs, group);
        const int count = ext2fs_group_blocks_count(fs, group);
        uint32_t freeInGroup = 0;
        for (int index = 0; index < count; ++index) {
            if (!ext2fs_test_block_bitmap2(rebuilt, first + static_cast<blk64_t>(index))) {
                ++freeInGroup;
            }
        }
        totalFree += freeInGroup;
        freeCounts[group] = freeInGroup;
        if (ext2fs_bg_free_blocks_count(fs, group) != freeInGroup) {
            differs = true;
        }
    }
    if (ext2fs_free_blocks_count(fs->super) != totalFree) {
        differs = true;
    }
    differs = differs || bitmapDiffers;
    if (!apply) {
        ext2fs_free_block_bitmap(rebuilt);
        return differs;
    }
    if (!differs) {
        ext2fs_free_block_bitmap(rebuilt);
        return true;
    }
    ext2fs_block_bitmap oldMap = fs->block_map;
    fs->block_map = rebuilt;
    ext2fs_mark_bb_dirty(fs);
    if (ext2fs_write_block_bitmap(fs) != 0) {
        fs->block_map = oldMap;
        ext2fs_free_block_bitmap(rebuilt);
        return false;
    }
    ext2fs_free_block_bitmap(oldMap);
    for (dgrp_t group = 0; group < fs->group_desc_count; ++group) {
        ext2fs_bg_free_blocks_count_set(fs, group, freeCounts[group]);
        ext2fs_group_desc_csum_set(fs, group);
    }
    ext2fs_free_blocks_count_set(fs->super, totalFree);
    ext2fs_mark_super_dirty(fs);
    return ext2fs_flush(fs) == 0;
}
}
bool extFreeSpaceAccountingNeedsRepair(int volumeId) {
    return extReconcileFreeBlockCounts(volumeId, false);
}
bool extRepairFreeSpaceAccounting(int volumeId) {
    return extReconcileFreeBlockCounts(volumeId, true);
}
int extReleaseBlockCallback(ext2_filsys fs, blk64_t* blocknr, e2_blkcnt_t,
                             blk64_t, int, void*) {
    ext2fs_block_alloc_stats2(fs, *blocknr, -1);
    return 0;
}
namespace {
struct ExtRefCollectContext {
    ext2_filsys fs;
    std::unordered_set<ext2_ino_t>* referenced;
};
int extRefCollectCallback(ext2_ino_t, int, struct ext2_dir_entry* entry, int, int, char*, void* data) {
    if (!entry->inode) return 0;
    auto* context = static_cast<ExtRefCollectContext*>(data);
    context->referenced->insert(entry->inode);
    const unsigned int nameLen = ext2fs_dirent_name_len(entry);
    const bool isDot = nameLen == 1 && entry->name[0] == '.';
    const bool isDotDot = nameLen == 2 && entry->name[0] == '.' && entry->name[1] == '.';
    if (!isDot && !isDotDot) {
        struct ext2_inode inode{};
        if (ext2fs_read_inode(context->fs, entry->inode, &inode) == 0 &&
            LINUX_S_ISDIR(inode.i_mode)) {
            ext2fs_dir_iterate2(context->fs, entry->inode, 0, nullptr,
                                extRefCollectCallback, data);
        }
    }
    return 0;
}
bool extCollectReferencedInodes(ext2_filsys fs, std::unordered_set<ext2_ino_t>& outReferenced) {
    outReferenced.clear();
    outReferenced.insert(EXT2_ROOT_INO);
    ExtRefCollectContext context{fs, &outReferenced};
    const errcode_t err = ext2fs_dir_iterate2(fs, EXT2_ROOT_INO, 0, nullptr,
                                               extRefCollectCallback, &context);
    return err == 0;
}
bool extScanOrphanedInodes(int volumeId, bool reclaim) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    VolumeState& volume = volumes[volumeId];
    if (!volume.extFs || !volume.extFs->super || (reclaim && volume.readOnly) ||
        !ensureExtBitmapsLoaded(volumeId)) {
        return false;
    }
    ext2_filsys fs = volume.extFs;
    std::unordered_set<ext2_ino_t> referenced;
    if (!extCollectReferencedInodes(fs, referenced)) return false;
    const ext2_ino_t firstUserIno = fs->super->s_first_ino;
    bool foundOrphan = false;
    for (ext2_ino_t ino = firstUserIno; ino <= fs->super->s_inodes_count; ++ino) {
        if (!ext2fs_test_inode_bitmap2(fs->inode_map, ino)) continue;
        if (referenced.count(ino)) continue;
        foundOrphan = true;
        if (!reclaim) return true;
        struct ext2_inode inode{};
        if (ext2fs_read_inode(fs, ino, &inode) != 0) continue;
        const bool isDir = LINUX_S_ISDIR(inode.i_mode);
        EXT_LOGI("extReclaimOrphanedInodes: freeing orphaned inode %u (dir=%d, links=%u, blocks=%u)",
                 ino, isDir ? 1 : 0, inode.i_links_count, inode.i_blocks);
        inode.i_links_count = 0;
        inode.i_dtime = static_cast<__u32>(time(nullptr));
        ext2fs_write_inode(fs, ino, &inode);
        if (ext2fs_inode_has_valid_blocks2(fs, &inode)) {
            ext2fs_block_iterate3(fs, ino, BLOCK_FLAG_READ_ONLY, nullptr,
                                   extReleaseBlockCallback, nullptr);
        }
        ext2fs_inode_alloc_stats2(fs, ino, -1, isDir ? 1 : 0);
    }
    if (!reclaim) return foundOrphan;
    if (!foundOrphan) return true;
    ext2fs_mark_ib_dirty(fs);
    ext2fs_mark_bb_dirty(fs);
    ext2fs_mark_super_dirty(fs);
    return ext2fs_flush(fs) == 0;
}
}
bool extHasOrphanedInodes(int volumeId) {
    return extScanOrphanedInodes(volumeId, false);
}
bool extReclaimOrphanedInodes(int volumeId) {
    return extScanOrphanedInodes(volumeId, true);
}
namespace {
struct ExtRepairScan {
    ext2_filsys fs;
    uint64_t capacityBytes;
    uint64_t nowUnix;
    bool remove = false;
    bool found = false;
    bool complete = true;
    std::unordered_set<ext2_ino_t> visited;
};
struct ExtRepairDirectory {
    ExtRepairScan* scan;
    std::vector<ext2_ino_t> childDirectories;
};
bool extRepairEntryLooksCorrupt(ExtRepairScan* scan, ext2_ino_t ino, struct ext2_inode& inode) {
    if (ino == 0 || ext2fs_read_inode(scan->fs, ino, &inode) != 0) return true;
    const uint64_t size = (static_cast<uint64_t>(inode.i_size_high) << 32) | inode.i_size;
    if (!LINUX_S_ISDIR(inode.i_mode) && size > scan->capacityBytes) return true;
    constexpr uint64_t kOneYearSeconds = 366ULL * 24 * 3600;
    return inode.i_mtime > scan->nowUnix + kOneYearSeconds;
}
int extRepairDirectoryEntry(ext2_ino_t, int, struct ext2_dir_entry* entry, int, int, char*, void* data) {
    auto* context = static_cast<ExtRepairDirectory*>(data);
    if (!entry->inode) return 0;
    const unsigned int nameLength = ext2fs_dirent_name_len(entry);
    const bool isDot = nameLength == 1 && entry->name[0] == '.';
    const bool isDotDot = nameLength == 2 && entry->name[0] == '.' && entry->name[1] == '.';
    if (isDot || isDotDot) return 0;
    struct ext2_inode inode{};
    if (extRepairEntryLooksCorrupt(context->scan, entry->inode, inode)) {
        context->scan->found = true;
        if (context->scan->remove) {
            entry->inode = 0;
            return DIRENT_CHANGED;
        }
        return 0;
    }
    if (LINUX_S_ISDIR(inode.i_mode)) context->childDirectories.push_back(entry->inode);
    return 0;
}
void extScanRepairDirectory(ExtRepairScan& scan, ext2_ino_t directory) {
    if (!scan.visited.insert(directory).second) return;
    ExtRepairDirectory context{&scan, {}};
    const errcode_t error = ext2fs_dir_iterate2(scan.fs, directory, 0, nullptr,
                                                  extRepairDirectoryEntry, &context);
    if (error != 0) {
        scan.found = true;
        scan.complete = false;
        return;
    }
    for (const ext2_ino_t child : context.childDirectories) extScanRepairDirectory(scan, child);
}
bool extScanCorruptDirectoryEntries(int volumeId, bool remove) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    VolumeState& volume = volumes[volumeId];
    if (!volume.extFs || !volume.extFs->super || (remove && volume.readOnly)) return false;
    ExtRepairScan scan{
        volume.extFs,
        ext2fs_blocks_count(volume.extFs->super) * static_cast<uint64_t>(volume.extFs->blocksize),
        static_cast<uint64_t>(time(nullptr)),
        remove,
    };
    extScanRepairDirectory(scan, EXT2_ROOT_INO);
    if (!remove) return scan.found;
    if (!scan.complete) return false;
    if (!scan.found) return true;
    ext2fs_mark_super_dirty(volume.extFs);
    return ext2fs_flush(volume.extFs) == 0;
}
}
bool extHasCorruptDirectoryEntries(int volumeId) {
    return extScanCorruptDirectoryEntries(volumeId, false);
}
bool extRemoveCorruptDirectoryEntries(int volumeId) {
    return extScanCorruptDirectoryEntries(volumeId, true);
}
int extDotDotFixupCallback(ext2_ino_t, int, struct ext2_dir_entry* dirent,
                            int, int, char*, void* priv) {
    auto* ctx = static_cast<ExtDotDotFixupContext*>(priv);
    if (ext2fs_dirent_name_len(dirent) == 2 &&
        dirent->name[0] == '.' && dirent->name[1] == '.') {
        dirent->inode = ctx->newParentIno;
        return DIRENT_CHANGED;
    }
    return 0;
}
void extListDirectory(int volumeId, const std::string& pathSuffix, std::vector<std::string>& results) {
    auto& v = volumes[volumeId];
    ext2_ino_t dirInode = 0;
    if (extResolvePath(v.extFs, pathSuffix, &dirInode)) {
        struct ext2_inode dirNodeInfo{};
        const errcode_t readInodeErr = ext2fs_read_inode(v.extFs, dirInode, &dirNodeInfo);
        EXT_LOGI("extListDirectory: ext dir inode=%u readInodeErr=%lu i_size=%u i_blocks=%u i_links_count=%u",
             dirInode, (unsigned long)readInodeErr, dirNodeInfo.i_size,
             dirNodeInfo.i_blocks, dirNodeInfo.i_links_count);
        ExtDirContext context{v.extFs, &results};
        const errcode_t iterErr = ext2fs_dir_iterate2(v.extFs, dirInode, 0, nullptr, extDirectoryEntry, &context);
        EXT_LOGI("extListDirectory: ext2fs_dir_iterate2 return=%lu (%s) entries=%zu",
             (unsigned long)iterErr, iterErr ? error_message(iterErr) : "OK", results.size());
        if (results.size() >= EXT_DIRECTORY_MAX_ENTRIES) results.push_back("System:TRUNCATED");
    }
}
uint64_t extGetFileSize(int volumeId, const std::string& path) {
    auto& v = volumes[volumeId];
    uint64_t size = 0;
    ext2_ino_t ino = 0;
    struct ext2_inode inode{};
    if (!extResolvePath(v.extFs, path, &ino)) {
        EXT_LOGE("extGetFileSize: path resolution failed for %s", path.c_str());
        return 0;
    }
    const errcode_t readErr = ext2fs_read_inode(v.extFs, ino, &inode);
    if (readErr != 0) {
        EXT_LOGE("extGetFileSize: ext2fs_read_inode failed for '%s' inode=%u err=%lu (%s)",
                 path.c_str(), ino, (unsigned long)readErr, error_message(readErr));
        return 0;
    }
    size = (static_cast<uint64_t>(inode.i_size_high) << 32) | inode.i_size;
    return size;
}
bool extReadFileChunk(int volumeId, const std::string& path, uint64_t offset, size_t length, std::vector<uint8_t>& outBuffer) {
    auto& v = volumes[volumeId];
    bool success = false;
    ext2_file_t file = nullptr;
    if (extOpenFile(v.extFs, path, false, false, &file)) {
        __u64 position = 0;
        std::unique_ptr<unsigned char[]> buffer(new unsigned char[length]);
        unsigned int got = 0;
        if (ext2fs_file_llseek(file, static_cast<__u64>(offset), EXT2_SEEK_SET, &position) == 0 &&
            ext2fs_file_read(file, buffer.get(), static_cast<unsigned int>(length), &got) == 0 && got > 0) {
            outBuffer.assign(buffer.get(), buffer.get() + got);
            success = true;
        }
        ext2fs_file_close(file);
    }
    return success;
}
bool extWriteFileChunk(int volumeId, const std::string& path, uint64_t offset, const uint8_t* data, size_t length) {
    auto& v = volumes[volumeId];
    bool success = false;
    ensureExtBitmapsLoaded(volumeId);
    ext2_file_t file = nullptr;
    if (extOpenFile(v.extFs, path, true, true, &file)) {
        __u64 position = 0;
        if (offset == 0) ext2fs_file_set_size2(file, 0);
        unsigned int written = 0;
        if (ext2fs_file_llseek(file, static_cast<__u64>(offset), EXT2_SEEK_SET, &position) == 0 &&
            ext2fs_file_write(file, data, static_cast<unsigned int>(length), &written) == 0 &&
            written == static_cast<unsigned int>(length) && ext2fs_file_flush(file) == 0) {
            ext2fs_flush(v.extFs);
            success = true;
        }
        ext2fs_file_close(file);
    }
    return success;
}
bool extCopyFile(int srcVolId, const std::string& srcPath, int destVolId, const std::string& destPath,
                  const CopyProgressCallback& onProgress) {
    auto& srcV = volumes[srcVolId];
    auto& destV = volumes[destVolId];
    ensureExtBitmapsLoaded(destVolId);
    ext2_file_t srcFile = nullptr;
    if (!extOpenFile(srcV.extFs, srcPath, false, false, &srcFile)) return false;
    ext2_file_t destFile = nullptr;
    if (!extOpenFile(destV.extFs, destPath, true, true, &destFile)) {
        ext2fs_file_close(srcFile);
        return false;
    }
    bool ok = ext2fs_file_set_size2(destFile, 0) == 0;
    constexpr size_t kBufSize = 2097152;
    std::unique_ptr<unsigned char[]> buf(new unsigned char[kBufSize]);
    while (ok) {
        unsigned int got = 0;
        if (ext2fs_file_read(srcFile, buf.get(), kBufSize, &got) != 0 || got == 0) break;
        unsigned int written = 0;
        if (ext2fs_file_write(destFile, buf.get(), got, &written) != 0 || written != got) {
            ok = false;
            break;
        }
        if (onProgress && !onProgress(static_cast<uint64_t>(written))) {
            ok = false;
            break;
        }
    }
    ok = ok && (ext2fs_file_flush(destFile) == 0);
    ext2fs_file_close(destFile);
    ext2fs_file_close(srcFile);
    if (ok) ext2fs_flush(destV.extFs);
    return ok;
}
bool extWriteBackFile(int volumeId, const std::string& targetPath, const std::string& sourceHostPath,
                       const CopyProgressCallback& onProgress) {
    auto& v = volumes[volumeId];
    ensureExtBitmapsLoaded(volumeId);
    bool success = extWriteFromHostFile(v.extFs, targetPath, sourceHostPath.c_str(), onProgress);
    if (success) success = ext2fs_flush(v.extFs) == 0;
    return success;
}
bool extExtractFile(int volumeId, const std::string& targetPath, const std::string& destHostPath) {
    auto& v = volumes[volumeId];
    return extExtractToHostFile(v.extFs, targetPath, destHostPath.c_str());
}
namespace {
bool extReleaseInodeIfUnlinked(ext2_filsys fs, ext2_ino_t ino, bool isDir) {
    struct ext2_inode inode{};
    if (ext2fs_read_inode(fs, ino, &inode) != 0) return false;
    if (inode.i_links_count) --inode.i_links_count;
    if (inode.i_links_count > 0) {
        return ext2fs_write_inode(fs, ino, &inode) == 0;
    }
    inode.i_dtime = static_cast<__u32>(time(nullptr));
    if (ext2fs_write_inode(fs, ino, &inode) != 0) return false;
    if (ext2fs_inode_has_valid_blocks2(fs, &inode)) {
        ext2fs_block_iterate3(fs, ino, BLOCK_FLAG_READ_ONLY, nullptr,
                               extReleaseBlockCallback, nullptr);
    }
    ext2fs_inode_alloc_stats2(fs, ino, -1, isDir ? 1 : 0);
    return true;
}
}
bool extDeleteFile(int volumeId, const std::string& path) {
    auto& v = volumes[volumeId];
    bool success = false;
    ensureExtBitmapsLoaded(volumeId);
    const size_t slash = path.find_last_of('/');
    const std::string parentPath = slash == std::string::npos ? "" : path.substr(0, slash);
    const std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
    ext2_ino_t parent = 0, ino = 0;
    if (!name.empty() && extResolvePath(v.extFs, parentPath, &parent) &&
        extResolvePath(v.extFs, path, &ino)) {
        struct ext2_inode inode{};
        const bool isDir = ext2fs_read_inode(v.extFs, ino, &inode) == 0 &&
                            LINUX_S_ISDIR(inode.i_mode);
        if (ext2fs_unlink(v.extFs, parent, name.c_str(), ino, 0) == 0) {
            success = extReleaseInodeIfUnlinked(v.extFs, ino, isDir);
            ext2fs_flush(v.extFs);
        }
    }
    return success;
}
bool extCreateDirectory(int volumeId, const std::string& path) {
    auto& v = volumes[volumeId];
    bool success = false;
    ensureExtBitmapsLoaded(volumeId);
    const size_t slash = path.find_last_of('/');
    const std::string parentPath = slash == std::string::npos ? "" : path.substr(0, slash);
    const std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
    ext2_ino_t parent = 0;
    if (!name.empty() && extResolvePath(v.extFs, parentPath, &parent)) {
        errcode_t mkdirErr = ext2fs_mkdir(v.extFs, parent, 0, name.c_str());
        if (mkdirErr == EXT2_ET_DIR_NO_SPACE) {
            if (ext2fs_expand_dir(v.extFs, parent) == 0) {
                mkdirErr = ext2fs_mkdir(v.extFs, parent, 0, name.c_str());
            }
        }
        if (mkdirErr == 0) {
            ext2fs_flush(v.extFs);
            success = true;
        } else {
            EXT_LOGE("extCreateDirectory: ext2fs_mkdir failed for '%s' in parent %u err=%lu (%s)",
                     name.c_str(), parent, (unsigned long)mkdirErr, error_message(mkdirErr));
        }
    }
    return success;
}
bool extRenameFile(int volumeId, const std::string& oldPath, const std::string& newPath) {
    auto& v = volumes[volumeId];
    bool success = false;
    ensureExtBitmapsLoaded(volumeId);
    const size_t oldSlash = oldPath.find_last_of('/');
    const std::string oldParentPath = oldSlash == std::string::npos ? "" : oldPath.substr(0, oldSlash);
    const std::string oldName = oldSlash == std::string::npos ? oldPath : oldPath.substr(oldSlash + 1);
    const size_t newSlash = newPath.find_last_of('/');
    const std::string newParentPath = newSlash == std::string::npos ? "" : newPath.substr(0, newSlash);
    const std::string newName = newSlash == std::string::npos ? newPath : newPath.substr(newSlash + 1);
    ext2_ino_t oldParentIno = 0, newParentIno = 0, srcIno = 0;
    if (!oldName.empty() && !newName.empty() &&
        extResolvePath(v.extFs, oldParentPath, &oldParentIno) &&
        extResolvePath(v.extFs, newParentPath, &newParentIno) &&
        extResolvePath(v.extFs, oldPath, &srcIno)) {
        struct ext2_inode srcInode{};
        const bool isDir = ext2fs_read_inode(v.extFs, srcIno, &srcInode) == 0 &&
                            LINUX_S_ISDIR(srcInode.i_mode);
        const int fileType = isDir ? EXT2_FT_DIR : EXT2_FT_REG_FILE;
        ext2_ino_t destIno = 0;
        if (extResolvePath(v.extFs, newPath, &destIno) && destIno != srcIno) {
            return false;
        }
        errcode_t linkErr = ext2fs_link(v.extFs, newParentIno, newName.c_str(), srcIno, fileType);
        if (linkErr == EXT2_ET_DIR_NO_SPACE) {
            if (ext2fs_expand_dir(v.extFs, newParentIno) == 0) {
                linkErr = ext2fs_link(v.extFs, newParentIno, newName.c_str(), srcIno, fileType);
            }
        }
        if (linkErr == 0) {
            if (ext2fs_unlink(v.extFs, oldParentIno, oldName.c_str(), srcIno, 0) == 0) {
                success = true;
                if (isDir && oldParentIno != newParentIno) {
                    ExtDotDotFixupContext ctx{newParentIno};
                    ext2fs_dir_iterate2(v.extFs, srcIno, 0, nullptr, extDotDotFixupCallback, &ctx);
                    struct ext2_inode oldParentInode{};
                    if (ext2fs_read_inode(v.extFs, oldParentIno, &oldParentInode) == 0 &&
                        oldParentInode.i_links_count) {
                        --oldParentInode.i_links_count;
                        ext2fs_write_inode(v.extFs, oldParentIno, &oldParentInode);
                    }
                    struct ext2_inode newParentInode{};
                    if (ext2fs_read_inode(v.extFs, newParentIno, &newParentInode) == 0) {
                        ++newParentInode.i_links_count;
                        ext2fs_write_inode(v.extFs, newParentIno, &newParentInode);
                    }
                }
            } else {
                ext2fs_unlink(v.extFs, newParentIno, newName.c_str(), srcIno, 0);
            }
        }
        if (success) ext2fs_flush(v.extFs);
    }
    return success;
}
bool extSetLastModifiedTime(int volumeId, const std::string& path, uint64_t epochSeconds) {
    auto& v = volumes[volumeId];
    bool success = false;
    ext2_ino_t ino = 0;
    if (extResolvePath(v.extFs, path, &ino)) {
        struct ext2_inode inode = {};
        if (ext2fs_read_inode(v.extFs, ino, &inode) == 0) {
            inode.i_mtime = static_cast<__u32>(epochSeconds);
            inode.i_atime = static_cast<__u32>(epochSeconds);
            inode.i_ctime = static_cast<__u32>(epochSeconds);
            if (ext2fs_write_inode(v.extFs, ino, &inode) == 0) {
                ext2fs_flush(v.extFs);
                success = true;
            }
        }
    }
    return success;
}
void extGetSpaceInfo(int volumeId, uint64_t& outTotalBytes, uint64_t& outFreeBytes) {
    auto& v = volumes[volumeId];
    ext2_filsys fs = v.extFs;
    if (!fs || !fs->super) {
        outTotalBytes = 0;
        outFreeBytes = 0;
        return;
    }
    outTotalBytes = static_cast<uint64_t>(ext2fs_blocks_count(fs->super)) * fs->blocksize;
    if (ensureExtBitmapsLoaded(volumeId) && fs->block_map) {
        blk64_t freeBlocks = 0;
        for (dgrp_t group = 0; group < fs->group_desc_count; ++group) {
            const blk64_t first = ext2fs_group_first_block2(fs, group);
            const int count = ext2fs_group_blocks_count(fs, group);
            for (int index = 0; index < count; ++index) {
                if (!ext2fs_test_block_bitmap2(fs->block_map, first + static_cast<blk64_t>(index))) {
                    ++freeBlocks;
                }
            }
        }
        outFreeBytes = freeBlocks * fs->blocksize;
    } else {
        outFreeBytes = static_cast<uint64_t>(ext2fs_free_blocks_count(fs->super)) * fs->blocksize;
    }
}
void* extOpenStream(int volumeId, const std::string& path) {
    auto& v = volumes[volumeId];
    ext2_file_t file = nullptr;
    if (extOpenFile(v.extFs, path, false, false, &file)) {
        auto* stream = new ExtStream{file};
        v.openExtStreams.push_back(stream);
        return stream;
    }
    EXT_LOGE("extOpenStream: failed to open '%s' on volume %d", path.c_str(), volumeId);
    return nullptr;
}
int32_t extReadStream(int volumeId, void* handle, uint64_t offset, uint8_t* dest, size_t length) {
    auto& v = volumes[volumeId];
    ExtStream* stream = reinterpret_cast<ExtStream*>(handle);
    if (std::find(v.openExtStreams.begin(), v.openExtStreams.end(), stream) == v.openExtStreams.end()) return -1;
    __u64 position = 0;
    unsigned int got = 0;
    const errcode_t seekErr = ext2fs_file_llseek(stream->file, static_cast<__u64>(offset), EXT2_SEEK_SET, &position);
    if (seekErr != 0) {
        EXT_LOGE("extReadStream: llseek to offset=%llu failed err=%lu (%s)",
                 (unsigned long long)offset, (unsigned long)seekErr, error_message(seekErr));
        return -1;
    }
    const errcode_t readErr = ext2fs_file_read(stream->file, dest, static_cast<unsigned int>(length), &got);
    if (readErr != 0) {
        EXT_LOGE("extReadStream: read at offset=%llu length=%zu failed err=%lu (%s)",
                 (unsigned long long)offset, length, (unsigned long)readErr, error_message(readErr));
        return -1;
    }
    return static_cast<int32_t>(got);
}
void extCloseStream(int volumeId, void* handle) {
    auto& v = volumes[volumeId];
    ExtStream* stream = reinterpret_cast<ExtStream*>(handle);
    auto it = std::find(v.openExtStreams.begin(), v.openExtStreams.end(), stream);
    if (it == v.openExtStreams.end()) return;
    v.openExtStreams.erase(it);
    ext2fs_file_close(stream->file);
    delete stream;
}