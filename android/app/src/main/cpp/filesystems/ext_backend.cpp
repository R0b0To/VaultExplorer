#include "ext_backend.h"

#include <algorithm>
#include <android/log.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <memory>
#include <strings.h>
#include <unistd.h>

#include "diskio.h"
#include "volume_state.h"
#include "filesystems/stream_handles.h"

namespace { constexpr size_t kIoBufferSize = 262144; }

#define EXT_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

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
    if (LINUX_S_ISDIR(inode.i_mode)) {
        context->results->push_back("[DIR] " + name + "|0|" + std::to_string(inode.i_mtime));
    } else {
        const uint64_t size = (static_cast<uint64_t>(inode.i_size_high) << 32) | inode.i_size;
        context->results->push_back(name + "|" + std::to_string(size) + "|" + std::to_string(inode.i_mtime));
    }
    return 0;
}

namespace {

// Recursion context for recursiveExtFolderSize(): accumulates the byte
// total of every regular file found under the starting directory,
// descending into subdirectories inline rather than collecting entries
// into a results list the way extDirectoryEntry() does for directory
// listings.
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

} // namespace

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
        if (!create) return false;
        const size_t slash = path.find_last_of('/');
        const std::string parentPath = slash == std::string::npos ? "" : path.substr(0, slash);
        const std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
        ext2_ino_t parent = 0;
        if (name.empty() || !extResolvePath(fs, parentPath, &parent)) return false;
        struct ext2_inode inode{};
        if (ext2fs_new_inode(fs, parent, LINUX_S_IFREG | 0644, nullptr, &inodeNumber) != 0) return false;
        inode.i_mode = LINUX_S_IFREG | 0644;
        inode.i_links_count = 1;
        if (ext2fs_write_new_inode(fs, inodeNumber, &inode) != 0 ||
            ext2fs_link(fs, parent, name.c_str(), inodeNumber, EXT2_FT_REG_FILE) != 0) return false;
        ext2fs_inode_alloc_stats2(fs, inodeNumber, +1, 0);
    }
    return ext2fs_file_open(fs, inodeNumber, write ? EXT2_FILE_WRITE : 0, out) == 0;
}

bool extWriteFromHostFile(ext2_filsys fs, const std::string& path, const char* source) {
    ext2_file_t file = nullptr;
    if (!extOpenFile(fs, path, true, true, &file)) return false;
    bool ok = ext2fs_file_set_size2(file, 0) == 0;
    std::ifstream input(source, std::ios::binary);
    std::unique_ptr<unsigned char[]> buffer(new unsigned char[kIoBufferSize]);
    while (ok && input) {
        input.read(reinterpret_cast<char*>(buffer.get()), kIoBufferSize);
        const std::streamsize count = input.gcount();
        if (count <= 0) break;
        unsigned int written = 0;
        ok = ext2fs_file_write(file, buffer.get(), static_cast<unsigned int>(count), &written) == 0 &&
             written == static_cast<unsigned int>(count);
    }
    ok = ok && input.eof() && ext2fs_file_flush(file) == 0;
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

// libext2fs sees a normal byte-addressable device. This adapter translates
// its block requests into the encrypted FatFs disk I/O layer.
bool extTransfer(int volumeId, uint64_t offset, void* data, size_t bytes, bool write) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES || bytes == 0) return bytes == 0;
    const auto& volume = volumes[volumeId];
    if (offset > volume.dataAreaLengthBytes || bytes > volume.dataAreaLengthBytes - offset)
        return false;
    const uint64_t firstSector = offset / 512;
    const uint64_t lastSector = (offset + bytes + 511) / 512;
    const size_t sectorBytes = static_cast<size_t>(lastSector - firstSector) * 512;
    thread_local std::vector<unsigned char> sectors;
    if (sectors.size() < sectorBytes) sectors.resize(sectorBytes);
    const size_t inSector = static_cast<size_t>(offset % 512);
    const bool wholeSectors = inSector == 0 && bytes % 512 == 0;

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

} // namespace

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
    params.s_feature_incompat = 0x0002; // FILETYPE
    params.s_feature_ro_compat = 0x0001; // SPARSE_SUPER
    params.s_feature_compat = 0x0020; // DIR_INDEX
    if (ext4) params.s_feature_incompat |= 0x0040; // EXTENTS

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

// ----------------------------------------------------------------====
// EXT2/3/4 rename support. ext2fs_link()/ext2fs_unlink() don't update a
// moved directory's own ".." entry, so extRenameFile below repoints it
// via this callback when a directory changes parent. Moved here from
// jni/filesystem_bridge.cpp alongside the rest of the ext rename logic.
// ----------------------------------------------------------------====
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

// ----------------------------------------------------------------====
// The functions below implement filesystems/fs_ops.h's fsXxx() contract
// for ext2/3/4. Several are thin wrappers around extOpenFile/extResolvePath/
// extWriteFromHostFile/extExtractToHostFile above; the rest were extracted
// verbatim (same libext2fs call sequences, same error-handling conditions)
// from what used to be inline `else if (v.fsType == FS_EXT) { ... }`
// branches in jni/filesystem_bridge.cpp.
// ----------------------------------------------------------------====

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
    if (extResolvePath(v.extFs, path, &ino) &&
        ext2fs_read_inode(v.extFs, ino, &inode) == 0)
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

bool extWriteBackFile(int volumeId, const std::string& targetPath, const std::string& sourceHostPath) {
    auto& v = volumes[volumeId];
    ensureExtBitmapsLoaded(volumeId);
    bool success = extWriteFromHostFile(v.extFs, targetPath, sourceHostPath.c_str());
    if (success) success = ext2fs_flush(v.extFs) == 0;
    return success;
}

bool extExtractFile(int volumeId, const std::string& targetPath, const std::string& destHostPath) {
    auto& v = volumes[volumeId];
    return extExtractToHostFile(v.extFs, targetPath, destHostPath.c_str());
}

namespace {

// ext2fs_unlink() only removes the directory entry -- it never touches the
// block/inode bitmaps or the superblock's free counters, which is what
// getSpaceInfo() reads for FS_EXT. If we stop at unlink() (and a manual
// i_links_count--), the inode's data blocks stay marked "in use" forever:
// free space never grows back after a delete, or after a move that
// overwrites an existing destination file. Writes look fine only because
// block *allocation* does update the bitmaps correctly -- deletion just
// never released anything to begin with.
//
// This mirrors what e2fsprogs's own debugfs "rm" (kill_file_by_inode) does:
// walk the inode's blocks and free each one, then free the inode itself.
int extReleaseBlockCallback(ext2_filsys fs, blk64_t* blocknr, e2_blkcnt_t,
                             blk64_t, int, void*) {
    ext2fs_block_alloc_stats2(fs, *blocknr, -1);
    return 0;
}

// Drops one link to `ino`. If that was the last link, reclaims its data
// blocks and frees the inode so free-space counters reflect the deletion.
// Safe to call after ext2fs_unlink() has already removed the directory
// entry. Returns false only on an inode read/write error.
bool extReleaseInodeIfUnlinked(ext2_filsys fs, ext2_ino_t ino, bool isDir) {
    struct ext2_inode inode{};
    if (ext2fs_read_inode(fs, ino, &inode) != 0) return false;
    if (inode.i_links_count) --inode.i_links_count;
    if (inode.i_links_count > 0) {
        // Other hard links still reference this inode -- nothing to free.
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

} // namespace

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
    if (!name.empty() && extResolvePath(v.extFs, parentPath, &parent) &&
        ext2fs_mkdir(v.extFs, parent, 0, name.c_str()) == 0) {
        ext2fs_flush(v.extFs);
        success = true;
    }
    return success;
}

bool extRenameFile(int volumeId, const std::string& oldPath, const std::string& newPath) {
    auto& v = volumes[volumeId];
    bool success = false;
    ensureExtBitmapsLoaded(volumeId);
    const std::string& oldFull = oldPath;
    const std::string& newFull = newPath;
    const size_t oldSlash = oldFull.find_last_of('/');
    const std::string oldParentPath = oldSlash == std::string::npos ? "" : oldFull.substr(0, oldSlash);
    const std::string oldName = oldSlash == std::string::npos ? oldFull : oldFull.substr(oldSlash + 1);
    const size_t newSlash = newFull.find_last_of('/');
    const std::string newParentPath = newSlash == std::string::npos ? "" : newFull.substr(0, newSlash);
    const std::string newName = newSlash == std::string::npos ? newFull : newFull.substr(newSlash + 1);

    ext2_ino_t oldParentIno = 0, newParentIno = 0, srcIno = 0;
    if (!oldName.empty() && !newName.empty() &&
        extResolvePath(v.extFs, oldParentPath, &oldParentIno) &&
        extResolvePath(v.extFs, newParentPath, &newParentIno) &&
        extResolvePath(v.extFs, oldFull, &srcIno)) {

        struct ext2_inode srcInode{};
        const bool isDir = ext2fs_read_inode(v.extFs, srcIno, &srcInode) == 0 &&
                            LINUX_S_ISDIR(srcInode.i_mode);
        const int fileType = isDir ? EXT2_FT_DIR : EXT2_FT_REG_FILE;

        ext2_ino_t destIno = 0;
        if (extResolvePath(v.extFs, newFull, &destIno) && destIno != srcIno) {
            struct ext2_inode destInode{};
            const bool destIsDir = ext2fs_read_inode(v.extFs, destIno, &destInode) == 0 &&
                                    LINUX_S_ISDIR(destInode.i_mode);
            if (ext2fs_unlink(v.extFs, newParentIno, newName.c_str(), destIno, 0) == 0) {
                extReleaseInodeIfUnlinked(v.extFs, destIno, destIsDir);
            }
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
    outTotalBytes = static_cast<uint64_t>(ext2fs_blocks_count(v.extFs->super)) * v.extFs->blocksize;
    outFreeBytes = static_cast<uint64_t>(ext2fs_free_blocks_count(v.extFs->super)) * v.extFs->blocksize;
}

void* extOpenStream(int volumeId, const std::string& path) {
    auto& v = volumes[volumeId];
    ext2_file_t file = nullptr;
    if (extOpenFile(v.extFs, path, false, false, &file)) {
        auto* stream = new ExtStream{file};
        v.openExtStreams.push_back(stream);
        return stream;
    }
    return nullptr;
}

int32_t extReadStream(int volumeId, void* handle, uint64_t offset, uint8_t* dest, size_t length) {
    auto& v = volumes[volumeId];
    ExtStream* stream = reinterpret_cast<ExtStream*>(handle);
    if (std::find(v.openExtStreams.begin(), v.openExtStreams.end(), stream) == v.openExtStreams.end()) return -1;
    __u64 position = 0;
    unsigned int got = 0;
    if (ext2fs_file_llseek(stream->file, static_cast<__u64>(offset), EXT2_SEEK_SET, &position) == 0 &&
        ext2fs_file_read(stream->file, dest, static_cast<unsigned int>(length), &got) == 0)
        return static_cast<int32_t>(got);
    return -1;
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
