// Desktop C ABI for Check & Repair and the header backup tool (see ve_engine.h). The logic is
// containers/container_repair.cpp, shared with Android's JNI bridge (jni/repair_bridge.cpp); this file only
// carries arguments in and results out. Like the JNI layer it hands a descriptor to the engine, which closes it
// on every path.
#include "ve_engine.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <vector>

#include "../containers/container_repair.h"
#include "../crypto/keyfile_mixing.h"

namespace {

void clearBuf(ve_buffer* b) {
    if (b) {
        b->data = nullptr;
        b->len = 0;
    }
}

// Keyfile fds are owned by the engine: close what a refused call never reached.
void closeAll(const int32_t* fds, int32_t count) {
    if (!fds) return;
    for (int32_t i = 0; i < count; ++i) closeUnusedKeyfileFds(&fds[i], 1);
}

void putU32(std::vector<uint8_t>& out, uint32_t v) {
    for (int i = 0; i < 4; ++i) out.push_back(static_cast<uint8_t>(v >> (8 * i)));
}

}  // namespace

extern "C" VE_API int32_t ve_repair_diagnose_file(int32_t fd, int32_t op_id, int32_t* code_out, int32_t* format_out) {
    if (!code_out || !format_out) return VE_ERR_INVALID_ARG;
    *code_out = 1;
    *format_out = -1;
    try {
        ContainerFormat format = ContainerFormat::kVeraCrypt;
        bool known = false;
        const RepairDiagnosisCode code = diagnoseUnmountedContainerFile(fd, format, known, op_id);
        *code_out = static_cast<int32_t>(code);
        *format_out = known ? static_cast<int32_t>(format) : -1;
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_repair_restore_luks2(int32_t fd, int32_t op_id) {
    try {
        return restoreLuks2BackupHeaderUnmounted(fd, op_id) ? VE_OK : VE_ERR_FAILED;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_repair_restore_veracrypt(int32_t fd, const uint8_t* password, int32_t password_len,
                                                      int32_t pim, int32_t cipher_id, int32_t hash_id, int32_t op_id,
                                                      int32_t* result_out) {
    if (!result_out || password_len < 0 || (password_len > 0 && !password)) return VE_ERR_INVALID_ARG;
    *result_out = static_cast<int32_t>(VeraCryptRestoreResult::kIoError);
    try {
        static const uint8_t kNone = 0;
        *result_out = static_cast<int32_t>(restoreVeraCryptBackupHeaderUnmounted(
            fd, password ? password : &kNone, static_cast<size_t>(password_len), pim, cipher_id, hash_id, op_id));
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_repair_diagnose_mounted(int32_t vol_id, int32_t op_id, int32_t* code_out) {
    if (!code_out) return VE_ERR_INVALID_ARG;
    *code_out = static_cast<int32_t>(RepairDiagnosisCode::kHealthy);
    try {
        *code_out = static_cast<int32_t>(diagnoseMountedVolumeFilesystem(vol_id, op_id));
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_repair_check_mounted(int32_t vol_id, int32_t op_id, int32_t* ok_out) {
    if (!ok_out) return VE_ERR_INVALID_ARG;
    *ok_out = 0;
    try {
        *ok_out = runMountedVolumeFilesystemCheck(vol_id, op_id) ? 1 : 0;
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_header_export(int32_t fd, int32_t op_id, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    clearBuf(out);
    try {
        ContainerFormat format = ContainerFormat::kVeraCrypt;
        std::vector<uint8_t> payload;
        const HeaderExportResult result = exportContainerHeaderRegion(fd, format, payload, op_id);
        const bool formatMeaningful =
            result != HeaderExportResult::kUnrecognizedFile && result != HeaderExportResult::kIoError;

        std::vector<uint8_t> rec;
        putU32(rec, static_cast<uint32_t>(result));
        putU32(rec, formatMeaningful ? static_cast<uint32_t>(format) : 0xFFFFFFFFu);
        putU32(rec, static_cast<uint32_t>(payload.size()));
        rec.insert(rec.end(), payload.begin(), payload.end());
        auto* mem = static_cast<uint8_t*>(std::malloc(rec.size()));
        if (!mem) return VE_ERR_FAILED;
        std::memcpy(mem, rec.data(), rec.size());
        out->data = mem;
        out->len = rec.size();
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_header_restore(int32_t fd, int32_t format, const uint8_t* payload, int32_t payload_len,
                                            const uint8_t* password, int32_t password_len, int32_t pim,
                                            int32_t cipher_id, int32_t hash_id, int32_t op_id,
                                            const int32_t* keyfile_fds, int32_t keyfile_count, int32_t* result_out) {
    if (!result_out) return VE_ERR_INVALID_ARG;
    *result_out = static_cast<int32_t>(HeaderRestoreResult::kIoError);
    if (payload_len < 0 || (payload_len > 0 && !payload) || password_len < 0 || (password_len > 0 && !password) ||
        keyfile_count < 0 || (keyfile_count > 0 && !keyfile_fds)) {
        closeAll(keyfile_fds, keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    try {
        // The password, with the keyfiles mixed into it (which closes each keyfile fd), in a buffer that is wiped
        // on every path -- the same sequence as the JNI bridge.
        unsigned char mixed[MAX_PASSWORD_LEN] = {0};
        ScopeZeroize guard(mixed, sizeof(mixed));
        size_t mixedLen = std::min(static_cast<size_t>(password_len), sizeof(mixed));
        if (mixedLen > 0) std::memcpy(mixed, password, mixedLen);
        if (keyfile_count > 0 &&
            !applyKeyfilesToPassword(keyfile_fds, keyfile_count, mixed, &mixedLen)) {
            return VE_OK;  // *result_out stays kIoError: a keyfile could not be read
        }
        *result_out = static_cast<int32_t>(restoreContainerHeaderRegion(
            fd, static_cast<ContainerFormat>(format), payload, static_cast<size_t>(payload_len), mixed, mixedLen, pim,
            cipher_id, hash_id, op_id));
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}
