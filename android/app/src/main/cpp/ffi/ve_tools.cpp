// Desktop C ABI for the container tools: expanding a container file, growing the file system inside it, and adding
// a hidden volume to an existing standard volume (see ve_engine.h, "container tools"). The logic is
// containers/container_create.cpp and containers/container_expand_bitlocker.cpp, shared with Android's JNI bridge
// (jni/container_lifecycle_bridge.cpp, behind VeraCryptToolsHandlers.kt); this file only carries arguments in and
// results out. Like the JNI layer it hands descriptors to the engine, which closes them on every path.
#include "ve_engine.h"

#include <cstdint>
#include <cstring>
#include <exception>
#include <string>

#include "../containers/container_create.h"
#include "../crypto/user_entropy.h"
#include "ve_fd_util.h"

namespace {

using veffi::closeAll;
using veffi::closeFd;
using veffi::credentialOk;
using veffi::SecretString;

// File-system kind code for the result record: the label fsGetFilesystemLabel reports ("NTFS", "ext4", ...), as the
// JNI bridge's fsKindCode maps it (jni/container_lifecycle_bridge.cpp).
int32_t fsKindCode(const FsGrowReport& report) {
    static const char* const kNames[] = {"", "FAT12", "FAT16", "FAT32", "exFAT", "NTFS", "ext2", "ext3", "ext4"};
    for (int32_t i = 1; i < 9; ++i) {
        if (std::strcmp(report.fsLabel, kNames[i]) == 0) return i;
    }
    return 0;
}

void initExpandResult(int32_t* out) {
    out[0] = static_cast<int32_t>(ExpandOutcome::kIoError);
    out[1] = -1;
    out[2] = 0;
}

void packExpandResult(ExpandOutcome outcome, const FsGrowReport& report, int32_t* out) {
    out[0] = static_cast<int32_t>(outcome);
    out[1] = report.attempted ? static_cast<int32_t>(report.status) : -1;
    out[2] = fsKindCode(report);
}

}  // namespace

extern "C" VE_API int32_t ve_expand_veracrypt(int32_t fd, const uint8_t* password, int32_t password_len, int32_t pim,
                                              int32_t cipher_id, int32_t hash_id, const int32_t* keyfile_fds,
                                              int32_t keyfile_count, int64_t new_size_bytes, int32_t init_free_space,
                                              int32_t grow_file_system, int32_t* result_out) {
    if (!result_out || !credentialOk(password, password_len, keyfile_fds, keyfile_count)) {
        closeFd(fd);
        closeAll(keyfile_fds, keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    initExpandResult(result_out);
    try {
        const SecretString pass(password, password_len);
        FsGrowReport report;
        const ExpandOutcome outcome = expandVeraCryptContainer(
            fd, pass.c_str(), pim, cipher_id, hash_id, keyfile_count > 0 ? keyfile_fds : nullptr, keyfile_count,
            new_size_bytes, init_free_space != 0, grow_file_system != 0, &report);
        packExpandResult(outcome, report, result_out);
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_expand_luks(int32_t fd, const uint8_t* password, int32_t password_len,
                                         const int32_t* keyfile_fds, int32_t keyfile_count, int64_t new_size_bytes,
                                         int32_t init_free_space, int32_t grow_file_system, int32_t* result_out) {
    if (!result_out || !credentialOk(password, password_len, keyfile_fds, keyfile_count)) {
        closeFd(fd);
        closeAll(keyfile_fds, keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    initExpandResult(result_out);
    try {
        const SecretString pass(password, password_len);
        FsGrowReport report;
        const ExpandOutcome outcome =
            expandLuksContainer(fd, pass.c_str(), keyfile_count > 0 ? keyfile_fds : nullptr, keyfile_count,
                                new_size_bytes, init_free_space != 0, grow_file_system != 0, &report);
        packExpandResult(outcome, report, result_out);
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_expand_bitlocker(int32_t fd, const uint8_t* password, int32_t password_len,
                                              int64_t new_size_bytes, int32_t init_free_space,
                                              int32_t grow_file_system, int32_t* result_out) {
    if (!result_out || !credentialOk(password, password_len, nullptr, 0)) {
        closeFd(fd);
        return VE_ERR_INVALID_ARG;
    }
    initExpandResult(result_out);
    try {
        const SecretString pass(password, password_len);
        FsGrowReport report;
        const ExpandOutcome outcome = expandBitLockerContainer(fd, pass.c_str(), new_size_bytes,
                                                               init_free_space != 0, grow_file_system != 0, &report);
        packExpandResult(outcome, report, result_out);
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_grow_veracrypt_fs(int32_t fd, const uint8_t* password, int32_t password_len, int32_t pim,
                                               int32_t cipher_id, int32_t hash_id, const int32_t* keyfile_fds,
                                               int32_t keyfile_count, int32_t* result_out) {
    if (!result_out || !credentialOk(password, password_len, keyfile_fds, keyfile_count)) {
        closeFd(fd);
        closeAll(keyfile_fds, keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    initExpandResult(result_out);
    try {
        const SecretString pass(password, password_len);
        FsGrowReport report;
        const ExpandOutcome outcome = growVeraCryptFileSystem(
            fd, pass.c_str(), pim, cipher_id, hash_id, keyfile_count > 0 ? keyfile_fds : nullptr, keyfile_count,
            &report);
        packExpandResult(outcome, report, result_out);
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_grow_luks_fs(int32_t fd, const uint8_t* password, int32_t password_len,
                                          const int32_t* keyfile_fds, int32_t keyfile_count, int32_t* result_out) {
    if (!result_out || !credentialOk(password, password_len, keyfile_fds, keyfile_count)) {
        closeFd(fd);
        closeAll(keyfile_fds, keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    initExpandResult(result_out);
    try {
        const SecretString pass(password, password_len);
        FsGrowReport report;
        const ExpandOutcome outcome =
            growLuksFileSystem(fd, pass.c_str(), keyfile_count > 0 ? keyfile_fds : nullptr, keyfile_count, &report);
        packExpandResult(outcome, report, result_out);
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_grow_bitlocker_fs(int32_t fd, const uint8_t* password, int32_t password_len,
                                               int32_t* result_out) {
    if (!result_out || !credentialOk(password, password_len, nullptr, 0)) {
        closeFd(fd);
        return VE_ERR_INVALID_ARG;
    }
    initExpandResult(result_out);
    try {
        const SecretString pass(password, password_len);
        FsGrowReport report;
        const ExpandOutcome outcome = growBitLockerFileSystem(fd, pass.c_str(), &report);
        packExpandResult(outcome, report, result_out);
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_hidden_analyze(int32_t fd, const uint8_t* password, int32_t password_len, int32_t pim,
                                            int32_t cipher_id, int32_t hash_id, const int32_t* keyfile_fds,
                                            int32_t keyfile_count, int64_t* result_out) {
    if (!result_out || !credentialOk(password, password_len, keyfile_fds, keyfile_count)) {
        closeFd(fd);
        closeAll(keyfile_fds, keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    result_out[0] = static_cast<int64_t>(HiddenHostOutcome::kIoError);
    result_out[1] = 0;
    result_out[2] = 0;
    result_out[3] = 0;
    try {
        const SecretString pass(password, password_len);
        HiddenHostAnalysis analysis;
        const HiddenHostOutcome outcome =
            analyzeHiddenVolumeHost(fd, pass.c_str(), pim, cipher_id, hash_id,
                                    keyfile_count > 0 ? keyfile_fds : nullptr, keyfile_count, &analysis);
        result_out[0] = static_cast<int64_t>(outcome);
        result_out[1] = static_cast<int64_t>(analysis.fsKind);
        result_out[2] = static_cast<int64_t>(analysis.clusterSize);
        result_out[3] = static_cast<int64_t>(analysis.maxHiddenBytes);
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_hidden_create_in_existing(const ve_hidden_in_existing_params* p, int32_t* outcome_out) {
    if (!p || p->struct_size < static_cast<int32_t>(sizeof(ve_hidden_in_existing_params))) return VE_ERR_INVALID_ARG;
    if (!outcome_out || !p->hidden_file_system || p->hidden_size_bytes <= 0 ||
        !credentialOk(p->outer_password, p->outer_password_len, p->outer_keyfile_fds, p->outer_keyfile_count) ||
        !credentialOk(p->hidden_password, p->hidden_password_len, p->hidden_keyfile_fds, p->hidden_keyfile_count) ||
        (p->outer_password_len == 0 && p->outer_keyfile_count == 0) ||
        (p->hidden_password_len == 0 && p->hidden_keyfile_count == 0)) {
        closeFd(p->fd);
        closeAll(p->outer_keyfile_fds, p->outer_keyfile_count);
        closeAll(p->hidden_keyfile_fds, p->hidden_keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    *outcome_out = static_cast<int32_t>(HiddenHostOutcome::kIoError);
    try {
        userentropy::Scope entropy(p->user_entropy, p->user_entropy ? static_cast<size_t>(p->user_entropy_len) : 0);
        const SecretString outerPass(p->outer_password, p->outer_password_len);
        const SecretString hiddenPass(p->hidden_password, p->hidden_password_len);
        const HiddenHostOutcome outcome = createHiddenVolumeInExisting(
            p->fd, outerPass.c_str(), p->outer_pim, p->outer_cipher_id, p->outer_hash_id,
            p->outer_keyfile_count > 0 ? p->outer_keyfile_fds : nullptr, p->outer_keyfile_count, hiddenPass.c_str(),
            p->hidden_pim, p->hidden_file_system, p->hidden_size_bytes, p->hidden_cipher_id, p->hidden_hash_id,
            p->hidden_keyfile_count > 0 ? p->hidden_keyfile_fds : nullptr, p->hidden_keyfile_count,
            p->quick_format != 0);
        *outcome_out = static_cast<int32_t>(outcome);
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}
