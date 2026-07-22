// JNI bridge: filesystem operations inside an unlocked container --
// directory listing, file read/write/delete/rename/create, streaming
// read (for media playback), and free-space queries -- across all three
// supported filesystem families (FAT/exFAT via FatFs, NTFS via NTFS-3G,
// ext2/3/4 via e2fsprogs's libext2fs). See crypto_bridge.cpp's header
// comment for why splitting vaultexplorer.cpp this way doesn't require any
// Kotlin/Dart changes.
//
// Per-filesystem-type branching happens inline in most of these functions
// rather than through a shared interface -- that mirrors the original
// vaultexplorer.cpp structure and callers/backends (filesystems/ext_backend.*,
// filesystems/fat_backend.*, filesystems/ntfs_backend.*) unchanged; this
// file only relocates the JNI entry points themselves, it does not
// restructure the FS-dispatch logic within them.

#include <jni.h>
#include <cstdio>
#include <string>
#include <vector>
#include <fstream>
#include <android/log.h>
#include <sstream>
#include <cstring>
#include <cstdlib>
#include <unistd.h>
#include <sys/stat.h>
#include <memory>
#include <algorithm>
#include <fcntl.h>

#include "ff.h"
#include "diskio.h"
#include "session_prepare.h"
#include "container_format.h"
#include "container_utils.h"
#include "ext_backend.h"
#include "fat_backend.h"
#include "filesystem_paths.h"
#include "ntfs_backend.h"
#include "session_guard.h"
#include "volume_state.h"
#include "filesystems/stream_handles.h"
#include "virtual_block_device.h"

#include "jni_bridge_common.h"

extern "C" {
#include "device.h"
#include "volume.h"
#include "inode.h"
#include "dir.h"
#include "attrib.h"
#include "layout.h"
#include <ext2fs/ext2fs.h>
#include <ext2fs/ext2_io.h>
#include <et/com_err.h>
}

// Undefine conflicting macros defined by NTFS-3G support.h
#undef min
#undef max

#include "jni_bridge_common.h"

static constexpr size_t MAX_DIR_ENTRIES = 50000;
static constexpr size_t MAX_CHUNK_SIZE = 64 * 1024 * 1024;  // 64 MB per JNI read/write call
static constexpr size_t IO_BUFFER_SIZE = 262144;  // 256 KB staging buffer for extract/write-back

// ----------------------------------------------------------------====
// SHARED: Directory listing
// ----------------------------------------------------------------====

static jobjectArray buildDirectoryListing(JNIEnv* env, int volId, const char* pathSuffix) {
    std::vector<std::string> results;
    results.reserve(256);
    auto& v = volumes[volId];

    if (v.fsType == VolumeState::FS_FATFS) {
        std::string fullPath = drivePaths[volId];
        if (pathSuffix && pathSuffix[0] != '\0') {
            fullPath += '/';
            fullPath += pathSuffix;
        }
        DIR dir;
        FILINFO fno;
        if (f_opendir(&dir, fullPath.c_str()) == FR_OK) {
            while (f_readdir(&dir, &fno) == FR_OK && fno.fname[0]) {
                if (results.size() >= MAX_DIR_ENTRIES) {
                    results.push_back("System:TRUNCATED");
                    break;
                }
                const char* name = fno.fname;
                if (strcmp(name, "SYSTEM~1") == 0 || strcmp(name, "$RECYCLE.BIN") == 0) continue;

                const uint64_t ts = fatToUnixTimestamp(fno.fdate, fno.ftime);
                if (fno.fattrib & AM_DIR) {
                    results.push_back("[DIR] " + std::string(name) + "|0|" + std::to_string(ts));
                } else {
                    results.push_back(std::string(name) + "|" + std::to_string(fno.fsize) + "|" + std::to_string(ts));
                }
            }
            f_closedir(&dir);
        }
    } else if (v.fsType == VolumeState::FS_NTFS) {
        listNtfsDirectory(volId, pathSuffix ? pathSuffix : "", results);
    } else if (v.fsType == VolumeState::FS_EXT) {
        ext2_ino_t dirInode = 0;
        if (extResolvePath(v.extFs, pathSuffix ? pathSuffix : "", &dirInode)) {
            struct ext2_inode dirNodeInfo{};
            const errcode_t readInodeErr = ext2fs_read_inode(v.extFs, dirInode, &dirNodeInfo);
            LOGI("buildDirectoryListing: ext dir inode=%u readInodeErr=%lu i_size=%u i_blocks=%u i_links_count=%u",
                 dirInode, (unsigned long)readInodeErr, dirNodeInfo.i_size,
                 dirNodeInfo.i_blocks, dirNodeInfo.i_links_count);
            ExtDirContext context{v.extFs, &results};
            const errcode_t iterErr = ext2fs_dir_iterate2(v.extFs, dirInode, 0, nullptr, extDirectoryEntry, &context);
            LOGI("buildDirectoryListing: ext2fs_dir_iterate2 return=%lu (%s) entries=%zu",
                 (unsigned long)iterErr, iterErr ? error_message(iterErr) : "OK", results.size());
            if (results.size() >= MAX_DIR_ENTRIES) results.push_back("System:TRUNCATED");
        }
    }

    jclass strClass = env->FindClass("java/lang/String");
    jobjectArray retArr = env->NewObjectArray(static_cast<jsize>(results.size()), strClass, nullptr);
    for (size_t i = 0; i < results.size(); i++) {
        sanitizeString(results[i]);
        jstring js = env->NewStringUTF(results[i].c_str());
        env->SetObjectArrayElement(retArr, i, js);
        env->DeleteLocalRef(js);
    }
    return retArr;
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_listDirectory(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    if (!requireActiveSession(volId, "listDirectory")) {
        throwNotUnlocked(env, volId, "listDirectory"); return nullptr;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    jobjectArray result = nullptr;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId))
            result = buildDirectoryListing(env, volId, nativePath);
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return result;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getFileSize(
        JNIEnv* env, jobject, jstring fileName, jint volId) {
    if (!requireActiveSession(volId, "getFileSize")) {
        throwNotUnlocked(env, volId, "getFileSize"); return 0L;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jlong size = 0;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                FIL f;
                std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
                if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
                    size = static_cast<jlong>(f_size(&f));
                    f_close(&f);
                }
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(targetName);
                ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
                if (ni) {
                    size = static_cast<jlong>(ni->data_size);
                    ntfs_inode_close(ni);
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                ext2_ino_t ino = 0;
                struct ext2_inode inode{};
                if (extResolvePath(v.extFs, targetName, &ino) &&
                    ext2fs_read_inode(v.extFs, ino, &inode) == 0)
                    size = static_cast<jlong>((static_cast<uint64_t>(inode.i_size_high) << 32) | inode.i_size);
            }
        }
    }
    env->ReleaseStringUTFChars(fileName, targetName);
    return size;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getFolderSize(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    if (!requireActiveSession(volId, "getFolderSize")) {
        throwNotUnlocked(env, volId, "getFolderSize"); return 0L;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    jlong total = 0;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                total = static_cast<jlong>(recursiveFatFolderSize(volId, nativePath));
            } else if (v.fsType == VolumeState::FS_NTFS) {
                total = static_cast<jlong>(recursiveNtfsFolderSize(volId, nativePath));
            } else if (v.fsType == VolumeState::FS_EXT) {
                total = static_cast<jlong>(recursiveExtFolderSize(volId, nativePath));
            }
        }
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return total;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_readFileChunk(
        JNIEnv* env, jobject,
        jstring fileName, jlong offset, jint length, jint volId) {
    if (length <= 0 || static_cast<size_t>(length) > MAX_CHUNK_SIZE) return nullptr;
    if (!requireActiveSession(volId, "readFileChunk")) {
        throwNotUnlocked(env, volId, "readFileChunk"); return nullptr;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jbyteArray retArray = nullptr;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                FIL f;
                std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
                if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
                    f_lseek(&f, static_cast<FSIZE_t>(offset));
                    std::unique_ptr<unsigned char[]> buffer(new unsigned char[length]);
                    UINT br = 0;
                    if (f_read(&f, buffer.get(), static_cast<UINT>(length), &br) == FR_OK && br > 0) {
                        retArray = env->NewByteArray(static_cast<jsize>(br));
                        env->SetByteArrayRegion(retArray, 0, static_cast<jsize>(br),
                                                reinterpret_cast<jbyte*>(buffer.get()));
                    }
                    f_close(&f);
                }
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(targetName);
                ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
                if (ni) {
                    ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    if (na) {
                        std::unique_ptr<unsigned char[]> buffer(new unsigned char[length]);
                        s64 br = ntfs_attr_pread(na, offset, length, buffer.get());
                        if (br > 0) {
                            retArray = env->NewByteArray(static_cast<jsize>(br));
                            env->SetByteArrayRegion(retArray, 0, static_cast<jsize>(br),
                                                    reinterpret_cast<jbyte*>(buffer.get()));
                        }
                        ntfs_attr_close(na);
                    }
                    ntfs_inode_close(ni);
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                ext2_file_t file = nullptr;
                if (extOpenFile(v.extFs, targetName, false, false, &file)) {
                    __u64 position = 0;
                    std::unique_ptr<unsigned char[]> buffer(new unsigned char[length]);
                    unsigned int got = 0;
                    if (ext2fs_file_llseek(file, static_cast<__u64>(offset), EXT2_SEEK_SET, &position) == 0 &&
                        ext2fs_file_read(file, buffer.get(), static_cast<unsigned int>(length), &got) == 0 && got > 0) {
                        retArray = env->NewByteArray(static_cast<jsize>(got));
                        env->SetByteArrayRegion(retArray, 0, static_cast<jsize>(got),
                                                reinterpret_cast<jbyte*>(buffer.get()));
                    }
                    ext2fs_file_close(file);
                }
            }
        }
    }
    env->ReleaseStringUTFChars(fileName, targetName);
    return retArray;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_writeFileChunk(
        JNIEnv* env, jobject,
        jstring fileName, jlong offset, jbyteArray data, jint volId) {
    jsize len = env->GetArrayLength(data);
    if (len <= 0 || static_cast<size_t>(len) > MAX_CHUNK_SIZE) return JNI_FALSE;
    if (!requireActiveSession(volId, "writeFileChunk")) {
        throwNotUnlocked(env, volId, "writeFileChunk"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {
        throwReadOnly(env, volId, "writeFileChunk"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jbyte* body = env->GetByteArrayElements(data, nullptr);
    bool success = false;

    auto& v = volumes[volId];
    std::lock_guard<std::mutex> fsLock(v.mutex);
    if (ensureMounted(volId)) {
        if (v.fsType == VolumeState::FS_FATFS) {
            FIL f;
            std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
            BYTE openMode = (offset == 0) ? (FA_WRITE | FA_CREATE_ALWAYS) : (FA_WRITE | FA_OPEN_ALWAYS);
            if (f_open(&f, fatPath.c_str(), openMode) == FR_OK) {
                if (f_lseek(&f, static_cast<FSIZE_t>(offset)) == FR_OK) {
                    UINT bw = 0;
                    if (f_write(&f, body, static_cast<UINT>(len), &bw) == FR_OK && bw == static_cast<UINT>(len))
                        success = true;
                }
                f_close(&f);
            }
        } else if (v.fsType == VolumeState::FS_NTFS) {
            std::string fullPath = "/" + std::string(targetName);
            ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());

            if (!ni) { // Create file
                ni = createNtfsFile(v.ntfsVol, fullPath);
            }

            if (ni) {
                    ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    if (!na) {
                        ntfs_attr_add(ni, AT_DATA, AT_UNNAMED, 0, NULL, 0);
                        na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    }
                    if (na) {
                        if (offset == 0) {
                            ntfs_attr_truncate(na, 0);
                        }
                        s64 bw = ntfs_attr_pwrite(na, offset, len, body);
                        if (bw == static_cast<s64>(len)) success = true;
                        ntfs_attr_close(na);
                    }
                    ntfs_inode_close(ni);
                }
        } else if (v.fsType == VolumeState::FS_EXT) {
            ensureExtBitmapsLoaded(volId);
            ext2_file_t file = nullptr;
            if (extOpenFile(v.extFs, targetName, true, true, &file)) {
                __u64 position = 0;
                if (offset == 0) ext2fs_file_set_size2(file, 0);
                unsigned int written = 0;
                if (ext2fs_file_llseek(file, static_cast<__u64>(offset), EXT2_SEEK_SET, &position) == 0 &&
                    ext2fs_file_write(file, body, static_cast<unsigned int>(len), &written) == 0 &&
                    written == static_cast<unsigned int>(len) && ext2fs_file_flush(file) == 0) {
                    ext2fs_flush(v.extFs);
                    success = true;
                }
                ext2fs_file_close(file);
            }
        }
    }

    env->ReleaseByteArrayElements(data, body, JNI_ABORT);
    env->ReleaseStringUTFChars(fileName, targetName);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_writeBackFile(
        JNIEnv* env, jobject,
        jstring targetFileName, jstring sourcePath, jint volId) {
    if (!requireActiveSession(volId, "writeBackFile")) {
        throwNotUnlocked(env, volId, "writeBackFile"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {                                   
        throwReadOnly(env, volId, "writeBackFile"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    const char* source     = env->GetStringUTFChars(sourcePath, nullptr);
    bool success = false;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                FIL f;
                std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
                if (f_open(&f, fatPath.c_str(), FA_WRITE | FA_CREATE_ALWAYS) == FR_OK) {
                    std::ifstream inFile(source, std::ios::binary);
                    if (inFile.is_open()) {
                        std::unique_ptr<char[]> buf(new char[IO_BUFFER_SIZE]);
                        UINT bw;
                        bool writeError = false;
                        while (inFile && !writeError) {
                            inFile.read(buf.get(), IO_BUFFER_SIZE);
                            std::streamsize n = inFile.gcount();
                            if (n > 0) {
                                FRESULT res = f_write(&f, buf.get(), static_cast<UINT>(n), &bw);
                                if (res != FR_OK || bw != static_cast<UINT>(n)) {
                                    writeError = true;
                                }
                            }
                        }
                        if (!writeError) {
                            success = true;
                        }
                    }
                    f_close(&f);
                    if (!success) {
                        f_unlink(fatPath.c_str());
                    }
                }
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(targetName);
                ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
                if (!ni) {
                    ni = createNtfsFile(v.ntfsVol, fullPath);
                }

                if (ni) {
                    ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    if (!na) {
                        ntfs_attr_add(ni, AT_DATA, AT_UNNAMED, 0, NULL, 0);
                        na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    }
                    if (na) {
                        ntfs_attr_truncate(na, 0);
                        std::ifstream inFile(source, std::ios::binary);
                        if (inFile.is_open()) {
                            std::unique_ptr<char[]> buf(new char[IO_BUFFER_SIZE]);
                            s64 offset = 0;
                            bool writeError = false;
                            while (inFile && !writeError) {
                                inFile.read(buf.get(), IO_BUFFER_SIZE);
                                std::streamsize n = inFile.gcount();
                                if (n > 0) {
                                    s64 bw = ntfs_attr_pwrite(na, offset, n, buf.get());
                                    if (bw != n) {
                                        writeError = true;
                                    } else {
                                        offset += bw;
                                    }
                                }
                            }
                            if (!writeError) {
                                success = true;
                            }
                        }
                        ntfs_attr_close(na);
                    }
                    ntfs_inode_close(ni);
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                ensureExtBitmapsLoaded(volId);
                success = extWriteFromHostFile(v.extFs, targetName, source);
                if (success) success = ext2fs_flush(v.extFs) == 0;
            }
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    env->ReleaseStringUTFChars(sourcePath, source);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_extractFile(
        JNIEnv* env, jobject,
        jstring targetFileName, jstring destPath, jint volId) {
    if (!requireActiveSession(volId, "extractFile")) {
        throwNotUnlocked(env, volId, "extractFile"); return JNI_FALSE;
    }
    const char* targetName  = env->GetStringUTFChars(targetFileName, nullptr);
    const char* destination = env->GetStringUTFChars(destPath, nullptr);
    bool success = false;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                FIL f;
                std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
                if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
                    std::ofstream outFile(destination, std::ios::binary);
                    if (outFile.is_open()) {
                        std::unique_ptr<unsigned char[]> buf(new unsigned char[IO_BUFFER_SIZE]);
                        UINT br;
                        while (f_read(&f, buf.get(), IO_BUFFER_SIZE, &br) == FR_OK && br > 0)
                            outFile.write(reinterpret_cast<char*>(buf.get()), br);
                        success = true;
                    }
                    f_close(&f);
                }
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(targetName);
                ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
                if (ni) {
                    ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    if (na) {
                        std::ofstream outFile(destination, std::ios::binary);
                        if (outFile.is_open()) {
                            std::unique_ptr<unsigned char[]> buf(new unsigned char[IO_BUFFER_SIZE]);
                            s64 offset = 0;
                            while (true) {
                                s64 br = ntfs_attr_pread(na, offset, IO_BUFFER_SIZE, buf.get());
                                if (br <= 0) break;
                                outFile.write(reinterpret_cast<char*>(buf.get()), br);
                                offset += br;
                            }
                            success = true;
                        }
                        ntfs_attr_close(na);
                    }
                    ntfs_inode_close(ni);
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                success = extExtractToHostFile(v.extFs, targetName, destination);
            }
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    env->ReleaseStringUTFChars(destPath, destination);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_deleteFile(
        JNIEnv* env, jobject, jstring targetFileName, jint volId) {
    if (!requireActiveSession(volId, "deleteFile")) {
        throwNotUnlocked(env, volId, "deleteFile"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {                                   
        throwReadOnly(env, volId, "deleteFile"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    bool success = false;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
                success = (f_unlink(fatPath.c_str()) == FR_OK);
            } else if (v.fsType == VolumeState::FS_NTFS) {
    std::string fullPath = "/" + std::string(targetName);
    ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
    size_t slashPos = fullPath.find_last_of('/');
    std::string parentPath = fullPath.substr(0, slashPos);
    std::string childName = fullPath.substr(slashPos + 1);
    if (parentPath.empty()) parentPath = "/";

    ntfs_inode* dir_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, parentPath.c_str());
    if (dir_ni && ni) {
        ntfschar* uname = nullptr;
        int uname_len = ntfs_mbstoucs(childName.c_str(), &uname);
        if (uname_len >= 0) {
            // ntfs_delete() unconditionally closes BOTH ni and dir_ni before
            // returning (success or failure) — closing them again below was
            // a double-free of already-released MFT-record state, which is
            // what corrupted the heap and crashed the app right after delete.
            success = (ntfs_delete(v.ntfsVol, fullPath.c_str(), ni, dir_ni,
                                    uname, static_cast<u8>(uname_len)) == 0);
            free(uname);
            ni = nullptr;
            dir_ni = nullptr;
        }
    }
    if (ni) ntfs_inode_close(ni);
    if (dir_ni) ntfs_inode_close(dir_ni);
}
            else if (v.fsType == VolumeState::FS_EXT) {
                const std::string path(targetName);
                const size_t slash = path.find_last_of('/');
                const std::string parentPath = slash == std::string::npos ? "" : path.substr(0, slash);
                const std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
                ext2_ino_t parent = 0, ino = 0;
                if (!name.empty() && extResolvePath(v.extFs, parentPath, &parent) &&
                    extResolvePath(v.extFs, path, &ino) &&
                    ext2fs_unlink(v.extFs, parent, name.c_str(), ino, 0) == 0) {
                    struct ext2_inode inode{};
                    if (ext2fs_read_inode(v.extFs, ino, &inode) == 0 && inode.i_links_count) {
                        --inode.i_links_count;
                        ext2fs_write_inode(v.extFs, ino, &inode);
                    }
                    ext2fs_flush(v.extFs);
                    success = true;
                }
            }
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_createDirectory(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    if (!requireActiveSession(volId, "createDirectory")) {
        throwNotUnlocked(env, volId, "createDirectory"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {                                   
        throwReadOnly(env, volId, "createDirectory"); return JNI_FALSE;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    bool success = false;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                std::string fullPath = std::string(drivePaths[volId]) + "/" + nativePath;
                success = (f_mkdir(fullPath.c_str()) == FR_OK);
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(nativePath);
                size_t slashPos = fullPath.find_last_of('/');
                std::string parentPath = fullPath.substr(0, slashPos);
                std::string childName = fullPath.substr(slashPos + 1);
                if (parentPath.empty()) parentPath = "/";

                ntfs_inode* parentNi = ntfs_pathname_to_inode(v.ntfsVol, NULL, parentPath.c_str());
                if (parentNi) {
                    ntfschar* uChild = nullptr;
                    int uChildLen = ntfs_mbstoucs(childName.c_str(), &uChild);
                    if (uChildLen >= 0) {
                        ntfs_inode* ni = ntfs_create(parentNi, 0, uChild, uChildLen, S_IFDIR);
                        if (ni) {
                            success = true;
                            ntfs_inode_close(ni);
                        }
                        free(uChild);
                    }
                    ntfs_inode_close(parentNi);
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                ensureExtBitmapsLoaded(volId);
                const std::string path(nativePath);
                const size_t slash = path.find_last_of('/');
                const std::string parentPath = slash == std::string::npos ? "" : path.substr(0, slash);
                const std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
                ext2_ino_t parent = 0;
                if (!name.empty() && extResolvePath(v.extFs, parentPath, &parent) &&
                    ext2fs_mkdir(v.extFs, parent, 0, name.c_str()) == 0) {
                    ext2fs_flush(v.extFs);
                    success = true;
                }
            }
        }
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return success ? JNI_TRUE : JNI_FALSE;
}

// ── EXT2/3/4 rename support ──────────────────────────────────────────────
struct ExtDotDotFixupContext {
    ext2_ino_t newParentIno;
};

static int extDotDotFixupCallback(ext2_ino_t, int, struct ext2_dir_entry* dirent,
                                   int, int, char*, void* priv) {
    auto* ctx = static_cast<ExtDotDotFixupContext*>(priv);
    if (ext2fs_dirent_name_len(dirent) == 2 &&
        dirent->name[0] == '.' && dirent->name[1] == '.') {
        dirent->inode = ctx->newParentIno;
        return DIRENT_CHANGED;
    }
    return 0;
}


extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_renameFile(
        JNIEnv* env, jobject,
        jstring oldPath, jstring newPath, jint volId) {
    if (!requireActiveSession(volId, "renameFile")) {
        throwNotUnlocked(env, volId, "renameFile"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {                                   
        throwReadOnly(env, volId, "renameFile"); return JNI_FALSE;
    }
    const char* nativeOld = env->GetStringUTFChars(oldPath, nullptr);
    const char* nativeNew = env->GetStringUTFChars(newPath, nullptr);
    bool success = false;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                std::string fullOld = std::string(drivePaths[volId]) + "/" + nativeOld;
                std::string fullNew = std::string(drivePaths[volId]) + "/" + nativeNew;
                success = (f_rename(fullOld.c_str(), fullNew.c_str()) == FR_OK);
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string oldFullPath = "/" + std::string(nativeOld);
                std::string newFullPath = "/" + std::string(nativeNew);

                size_t slashPosOld = oldFullPath.find_last_of('/');
                std::string parentOldPath = oldFullPath.substr(0, slashPosOld);
                std::string oldChildName = oldFullPath.substr(slashPosOld + 1);
                if (parentOldPath.empty()) parentOldPath = "/";

                size_t slashPosNew = newFullPath.find_last_of('/');
                std::string parentNewPath = newFullPath.substr(0, slashPosNew);
                std::string newChildName = newFullPath.substr(slashPosNew + 1);
                if (parentNewPath.empty()) parentNewPath = "/";

                ntfschar* uOld = nullptr;
                int uOldLen = ntfs_mbstoucs(oldChildName.c_str(), &uOld);
                ntfschar* uNew = nullptr;
                int uNewLen = ntfs_mbstoucs(newChildName.c_str(), &uNew);

                if (uOldLen >= 0 && uNewLen >= 0) {
                    // Step 1: if something already exists at the destination, overwrite it
                    ntfs_inode* dest_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, newFullPath.c_str());
                    if (dest_ni) {
                        ntfs_inode* dest_dir_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, parentNewPath.c_str());
                        if (dest_dir_ni) {
                            ntfs_delete(v.ntfsVol, newFullPath.c_str(), dest_ni, dest_dir_ni,
                                        uNew, static_cast<u8>(uNewLen));
                        } else {
                            ntfs_inode_close(dest_ni);
                        }
                    }

                    // Step 2: pre-open all necessary inodes
                    ntfs_inode* old_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, oldFullPath.c_str());
                    ntfs_inode* dir_new_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, parentNewPath.c_str());
                    ntfs_inode* dir_old_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, parentOldPath.c_str());

                    if (old_ni && dir_new_ni && dir_old_ni) {
                        // Link source under the new name
                        if (ntfs_link(old_ni, dir_new_ni, uNew, static_cast<u8>(uNewLen)) == 0) {
                            // Unlink the old name
                            success = (ntfs_delete(v.ntfsVol, oldFullPath.c_str(), old_ni, dir_old_ni,
                                                    uOld, static_cast<u8>(uOldLen)) == 0);
                            old_ni = nullptr; // pointer consumed by ntfs_delete
                            dir_old_ni = nullptr; // pointer consumed by ntfs_delete
                        }
                        
                        // Close whatever didn't get consumed
                        if (old_ni) ntfs_inode_close(old_ni);
                        if (dir_old_ni) ntfs_inode_close(dir_old_ni);
                        ntfs_inode_close(dir_new_ni);
                    } else {
                        if (old_ni) ntfs_inode_close(old_ni);
                        if (dir_new_ni) ntfs_inode_close(dir_new_ni);
                        if (dir_old_ni) ntfs_inode_close(dir_old_ni);
                    }
                }
                if (uOld) free(uOld);
                if (uNew) free(uNew);
            } else if (v.fsType == VolumeState::FS_EXT) {
                ensureExtBitmapsLoaded(volId);
                const std::string oldFull(nativeOld);
                const std::string newFull(nativeNew);
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
                        if (ext2fs_unlink(v.extFs, newParentIno, newName.c_str(), destIno, 0) == 0) {
                            struct ext2_inode destInode{};
                            if (ext2fs_read_inode(v.extFs, destIno, &destInode) == 0 && destInode.i_links_count) {
                                --destInode.i_links_count;
                                ext2fs_write_inode(v.extFs, destIno, &destInode);
                            }
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
            }
        }
    }
    env->ReleaseStringUTFChars(oldPath, nativeOld);
    env->ReleaseStringUTFChars(newPath, nativeNew);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_setLastModifiedTime(
        JNIEnv* env, jobject,
        jstring path, jlong epochSeconds, jint volId) {
    if (!requireActiveSession(volId, "setLastModifiedTime")) {
        throwNotUnlocked(env, volId, "setLastModifiedTime"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {                                   
        throwReadOnly(env, volId, "setLastModifiedTime"); return JNI_FALSE;
    }
    const char* nativePath = env->GetStringUTFChars(path, nullptr);
    bool success = false;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                WORD fdate = 0, ftime = 0;
                unixToFatTimestamp(static_cast<uint64_t>(epochSeconds), fdate, ftime);
                std::string fatPath = std::string(drivePaths[volId]) + "/" + nativePath;
                FILINFO fno = {};
                fno.fdate = fdate;
                fno.ftime = ftime;
                success = (f_utime(fatPath.c_str(), &fno) == FR_OK);
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(nativePath);
                ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
                if (ni) {
                    uint64_t ntfsTime = (static_cast<uint64_t>(epochSeconds) * 10000000ULL) + 116444736000000000ULL;
                    ni->last_data_change_time = ntfsTime;
                    ni->last_access_time = ntfsTime;
                    ni->last_mft_change_time = ntfsTime;
                    NInoSetDirty(ni);
                    success = (ntfs_inode_close(ni) == 0);
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                ext2_ino_t ino = 0;
                if (extResolvePath(v.extFs, nativePath, &ino)) {
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
            }
        }
    }
    env->ReleaseStringUTFChars(path, nativePath);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getSpaceInfo(
        JNIEnv* env, jobject, jint volId) {
    if (!requireActiveSession(volId, "getSpaceInfo")) {
        throwNotUnlocked(env, volId, "getSpaceInfo"); return nullptr;
    }
    jlong totalBytes = 0, freeBytes = 0;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                FATFS* fs;
                DWORD fre_clust;
                if (f_getfree(drivePaths[volId], &fre_clust, &fs) == FR_OK) {
                    totalBytes = static_cast<jlong>(fs->n_fatent - 2) * fs->csize * 512;
                    freeBytes  = static_cast<jlong>(fre_clust) * fs->csize * 512;
                }
            } else if (v.fsType == VolumeState::FS_NTFS) {
                ntfs_volume* vol = v.ntfsVol;
                s64 total_clusters = vol->nr_clusters;
                s64 free_cl = ntfs_attr_get_free_bits(vol->lcnbmp_na);
                totalBytes = total_clusters * vol->cluster_size;
                freeBytes  = free_cl * vol->cluster_size;
            } else if (v.fsType == VolumeState::FS_EXT) {
                totalBytes = static_cast<jlong>(ext2fs_blocks_count(v.extFs->super)) * v.extFs->blocksize;
                freeBytes = static_cast<jlong>(ext2fs_free_blocks_count(v.extFs->super)) * v.extFs->blocksize;
            }
        }
    }
    jlongArray ret = env->NewLongArray(2);
    if (!ret) return nullptr;
    const jlong tmp[2] = {totalBytes, freeBytes};
    env->SetLongArrayRegion(ret, 0, 2, tmp);
    return ret;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_openStream(
        JNIEnv* env, jobject, jstring targetFileName, jint volId) {
    if (!requireActiveSession(volId, "openStream")) {
        throwNotUnlocked(env, volId, "openStream"); return 0L;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    jlong streamPtr = 0;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            auto& v = volumes[volId];
            if (v.fsType == VolumeState::FS_FATFS) {
                FIL* f = new FIL();
                std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
                if (f_open(f, fatPath.c_str(), FA_READ) == FR_OK) {
                    streamPtr = reinterpret_cast<jlong>(f);
                    v.openStreams.push_back(f);
                } else {
                    delete f;
                }
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(targetName);
                ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
                if (ni) {
                    ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    if (na) {
                        NtfsStream* ns = new NtfsStream();
                        ns->inode = ni;
                        ns->attr = na;
                        streamPtr = reinterpret_cast<jlong>(ns);
                        v.openNtfsStreams.push_back(ns);
                    } else {
                        ntfs_inode_close(ni);
                    }
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                ext2_file_t file = nullptr;
                if (extOpenFile(v.extFs, targetName, false, false, &file)) {
                    auto* stream = new ExtStream{file};
                    streamPtr = reinterpret_cast<jlong>(stream);
                    v.openExtStreams.push_back(stream);
                }
            }
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    return streamPtr;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_readStream(
        JNIEnv* env, jobject,
        jlong streamPtr, jlong offset, jbyteArray outBuffer, jint length, jint volId) {
    if (streamPtr == 0 || length <= 0) return -1;
    if (volId < 0 || volId >= MAX_VOLUMES) return -1;
    jint bytesRead = -1;

    std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
    auto& v = volumes[volId];
    if (v.fsType == VolumeState::FS_FATFS) {
        FIL* f = reinterpret_cast<FIL*>(streamPtr);
        auto& streams = v.openStreams;
        if (std::find(streams.begin(), streams.end(), f) == streams.end()) return -1;

        f_lseek(f, static_cast<FSIZE_t>(offset));
        jbyte* destBuf = env->GetByteArrayElements(outBuffer, nullptr);
        if (destBuf != nullptr) {
            UINT br = 0;
            if (f_read(f, destBuf, static_cast<UINT>(length), &br) == FR_OK)
                bytesRead = static_cast<jint>(br);
            env->ReleaseByteArrayElements(outBuffer, destBuf, 0);
        }
    } else if (v.fsType == VolumeState::FS_NTFS) {
        NtfsStream* ns = reinterpret_cast<NtfsStream*>(streamPtr);
        auto& streams = v.openNtfsStreams;
        if (std::find(streams.begin(), streams.end(), ns) == streams.end()) return -1;

        jbyte* destBuf = env->GetByteArrayElements(outBuffer, nullptr);
        if (destBuf != nullptr) {
            s64 br = ntfs_attr_pread(ns->attr, offset, length, destBuf);
            if (br >= 0) bytesRead = static_cast<jint>(br);
            env->ReleaseByteArrayElements(outBuffer, destBuf, 0);
        }
    } else if (v.fsType == VolumeState::FS_EXT) {
        ExtStream* stream = reinterpret_cast<ExtStream*>(streamPtr);
        if (std::find(v.openExtStreams.begin(), v.openExtStreams.end(), stream) == v.openExtStreams.end()) return -1;
        jbyte* destBuf = env->GetByteArrayElements(outBuffer, nullptr);
        if (destBuf != nullptr) {
            __u64 position = 0;
            unsigned int got = 0;
            if (ext2fs_file_llseek(stream->file, static_cast<__u64>(offset), EXT2_SEEK_SET, &position) == 0 &&
                ext2fs_file_read(stream->file, destBuf, static_cast<unsigned int>(length), &got) == 0)
                bytesRead = static_cast<jint>(got);
            env->ReleaseByteArrayElements(outBuffer, destBuf, 0);
        }
    }
    return bytesRead;
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_closeStream(
        JNIEnv* env, jobject, jlong streamPtr, jint volId) {
    if (streamPtr == 0) return;
    if (volId < 0 || volId >= MAX_VOLUMES) return;

    std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
    auto& v = volumes[volId];
    if (v.fsType == VolumeState::FS_FATFS) {
        FIL* f = reinterpret_cast<FIL*>(streamPtr);
        auto& streams = v.openStreams;
        auto it = std::find(streams.begin(), streams.end(), f);
        if (it == streams.end()) return;
        streams.erase(it);
        f_close(f);
        delete f;
    } else if (v.fsType == VolumeState::FS_NTFS) {
        NtfsStream* ns = reinterpret_cast<NtfsStream*>(streamPtr);
        auto& streams = v.openNtfsStreams;
        auto it = std::find(streams.begin(), streams.end(), ns);
        if (it == streams.end()) return;
        streams.erase(it);
        ntfs_attr_close(ns->attr);
        ntfs_inode_close(ns->inode);
        delete ns;
    } else if (v.fsType == VolumeState::FS_EXT) {
        ExtStream* stream = reinterpret_cast<ExtStream*>(streamPtr);
        auto it = std::find(v.openExtStreams.begin(), v.openExtStreams.end(), stream);
        if (it == v.openExtStreams.end()) return;
        v.openExtStreams.erase(it);
        ext2fs_file_close(stream->file);
        delete stream;
    }
}
