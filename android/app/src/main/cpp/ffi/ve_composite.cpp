// Desktop C ABI for composite containers: one VeraCrypt volume spread over several ordinary host files ("carriers")
// that each keep their own content and carry their share of the encrypted volume after it (see ve_engine.h,
// "composite containers"). The logic is containers/carrier_profiler.cpp, composite_map.cpp and
// container_create_composite.cpp, shared with Android's JNI bridge (jni/composite_bridge.cpp, behind
// CompositeContainerHandlers.kt); this file only carries arguments in and results out and repeats that bridge's
// sequence: canonical carrier order, profile, derive the extents, then create or unlock.
//
// Carriers are host PATHS here, not descriptors: the engine's carrier cache opens them itself (io/host_file.h, which
// is Windows-safe), so nothing but the keyfiles is a descriptor and the descriptor ownership rule stays the one the
// other calls follow.
#include "ve_engine.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <string>
#include <vector>

#include "../containers/carrier_profiler.h"
#include "../containers/composite_block_device.h"
#include "../containers/composite_map.h"
#include "../containers/container_create_composite.h"
#include "../crypto/user_entropy.h"
#include "../crypto/vc_header_layout.h"
#include "session_prepare.h"
#include "virtual_block_device.h"
#include "volume_state.h"
#include "ve_fd_util.h"

namespace {

using veffi::closeAll;
using veffi::credentialOk;
using veffi::SecretString;

constexpr int32_t kMaxCarriers = 65536;  // far beyond any picker; only a guard against a corrupt count
constexpr uint64_t kMinCompositeBytes = 300 * 1024;  // the shared create's own floor for a formattable volume

void clearBuf(ve_buffer* b) {
    if (b) {
        b->data = nullptr;
        b->len = 0;
    }
}

// Copies [text] into [out] (no NUL, freed with ve_buffer_free). Best effort: a failed allocation leaves it empty.
void setText(ve_buffer* out, const std::string& text) {
    if (!out || text.empty()) return;
    auto* mem = static_cast<uint8_t*>(std::malloc(text.size()));
    if (!mem) return;
    std::memcpy(mem, text.data(), text.size());
    out->data = mem;
    out->len = text.size();
}

bool pathsOk(const char* const* paths, int32_t count) {
    if (!paths || count <= 0 || count > kMaxCarriers) return false;
    for (int32_t i = 0; i < count; ++i) {
        if (!paths[i] || paths[i][0] == '\0') return false;
    }
    return true;
}

bool validSlot(int32_t vol) { return vol >= 0 && vol < FF_VOLUMES; }

// Path-backed carrier targets in picker order (the sort that makes the order canonical comes next). Path-only: the
// carrier cache opens each file itself.
std::vector<CarrierTarget> makeTargets(const char* const* paths, int32_t count, bool readOnly) {
    std::vector<CarrierTarget> targets;
    targets.reserve(static_cast<size_t>(count));
    for (int32_t i = 0; i < count; ++i) {
        CarrierTarget t;
        t.path = paths[i];
        t.readOnly = readOnly;
        t.inputIndex = static_cast<uint32_t>(i);
        targets.push_back(std::move(t));
    }
    return targets;
}

void putU32(std::vector<uint8_t>& out, uint32_t v) {
    for (int i = 0; i < 4; ++i) out.push_back(static_cast<uint8_t>(v >> (8 * i)));
}

void putU64(std::vector<uint8_t>& out, uint64_t v) {
    for (int i = 0; i < 8; ++i) out.push_back(static_cast<uint8_t>(v >> (8 * i)));
}

void putString(std::vector<uint8_t>& out, const std::string& s) {
    putU32(out, static_cast<uint32_t>(s.size()));
    out.insert(out.end(), s.begin(), s.end());
}

}  // namespace

extern "C" VE_API int32_t ve_composite_profile(const char* const* carrier_paths, int32_t carrier_count,
                                               int32_t safety_margin_pct, ve_buffer* out) {
    if (!out || !pathsOk(carrier_paths, carrier_count)) return VE_ERR_INVALID_ARG;
    clearBuf(out);
    try {
        auto carriers = makeTargets(carrier_paths, carrier_count, /*readOnly=*/true);
        // The same canonical order the create and unlock calls use, so what is shown is what gets built.
        CompositeMap::sortCanonical(carriers);
        const unsigned pct =
            (safety_margin_pct > 0 && safety_margin_pct <= 100) ? static_cast<unsigned>(safety_margin_pct) : 10;
        const CapacityProfile profile = CarrierProfiler::profileForAllocation(carriers, pct);

        std::vector<uint8_t> rec;
        putU64(rec, profile.totalAllocatableBytes);
        putU32(rec, static_cast<uint32_t>(profile.perFile.size()));
        for (const CarrierBudget& b : profile.perFile) {
            putU32(rec, b.fileIndex);
            putU32(rec, b.inputIndex);
            putU32(rec, static_cast<uint32_t>(b.tier));
            putU64(rec, b.fileSize);
            putU64(rec, b.payloadOffset);
            putU64(rec, b.allocatableBytes);
            putString(rec, b.detectedFormat);
            putString(rec, b.path);
        }
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

extern "C" VE_API int32_t ve_composite_create(const ve_composite_create_params* p, ve_buffer* error_out) {
    clearBuf(error_out);
    if (!p || p->struct_size < static_cast<int32_t>(sizeof(ve_composite_create_params))) {
        if (p) closeAll(p->keyfile_fds, p->keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    if (!validSlot(p->vol_id) || !pathsOk(p->carrier_paths, p->carrier_count) || !p->file_system ||
        !credentialOk(p->password, p->password_len, p->keyfile_fds, p->keyfile_count) ||
        (p->password_len == 0 && p->keyfile_count == 0) ||  // a volume nobody has to authenticate to open
        p->user_entropy_len < 0 || (p->user_entropy_len > 0 && !p->user_entropy)) {
        closeAll(p->keyfile_fds, p->keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    const SecretString pass(p->password, p->password_len);
    if (pass.hasEmbeddedNul()) {  // a C string would silently cut the password short
        closeAll(p->keyfile_fds, p->keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    try {
        userentropy::Scope entropy(p->user_entropy, p->user_entropy ? static_cast<size_t>(p->user_entropy_len) : 0);

        auto carriers = makeTargets(p->carrier_paths, p->carrier_count, /*readOnly=*/false);
        CompositeMap::sortCanonical(carriers);

        const unsigned growthPct =
            (p->safety_margin_pct > 0 && p->safety_margin_pct <= 50) ? static_cast<unsigned>(p->safety_margin_pct) : 10;
        const uint64_t requested = p->requested_bytes > 0 ? static_cast<uint64_t>(p->requested_bytes) : 0;
        const CapacityProfile profile = CarrierProfiler::profileForAllocation(carriers, growthPct);
        const std::vector<CarrierExtent> extents = CompositeMap::deriveExtents(profile.perFile, requested);
        if (extents.empty()) {
            closeAll(p->keyfile_fds, p->keyfile_count);
            setText(error_out, "NO_EXTENTS_DERIVED");
            return VE_ERR_FAILED;
        }
        uint64_t derived = 0;
        for (const CarrierExtent& e : extents) derived += e.lengthBytes;
        // The profile the user saw and the files being written must still agree: a carrier that changed in between
        // would otherwise produce a smaller volume than the capacity that was displayed.
        if (requested > 0 && derived != requested) {
            closeAll(p->keyfile_fds, p->keyfile_count);
            setText(error_out, "CARRIER_CAPACITY_CHANGED");
            return VE_ERR_FAILED;
        }

        // createCompositeContainer extends the carrier files first and only then checks the size and the password
        // length, so a volume that cannot be built would leave every carrier grown. Refuse those here, while
        // nothing has been touched.
        if (derived < kMinCompositeBytes) {
            closeAll(p->keyfile_fds, p->keyfile_count);
            setText(error_out, "SIZE_TOO_SMALL");
            return VE_ERR_FAILED;
        }
        if (static_cast<size_t>(p->password_len) > VC_MAX_PASSWORD_BYTES) {
            closeAll(p->keyfile_fds, p->keyfile_count);
            setText(error_out, "PASSWORD_TOO_LONG");
            return VE_ERR_FAILED;
        }

        const CompositeCreateResult result = createCompositeContainer(
            p->vol_id, carriers, extents, pass.c_str(), p->pim, p->file_system, /*containerFormat=*/0, p->cipher_id,
            p->hash_id, p->keyfile_count > 0 ? p->keyfile_fds : nullptr, p->keyfile_count, p->quick_format != 0,
            /*operationId=*/"");
        if (!result.success) {
            // A failure after the slot was prepared leaves it holding the composite device; it is a free slot the
            // caller picked for this call, so wipe it rather than leave a half-built session.
            ve_lock(p->vol_id);
            setText(error_out, result.errorCode);
            return VE_ERR_FAILED;
        }
        return VE_OK;
    } catch (...) {
        ve_lock(p->vol_id);
        return VE_ERR_EXCEPTION;
    }
}

extern "C" VE_API int32_t ve_composite_unlock(const ve_composite_unlock_params* p, ve_buffer* error_out) {
    clearBuf(error_out);
    if (!p || p->struct_size < static_cast<int32_t>(sizeof(ve_composite_unlock_params))) {
        if (p) closeAll(p->keyfile_fds, p->keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    if (!validSlot(p->vol_id) || !pathsOk(p->carrier_paths, p->carrier_count) ||
        !credentialOk(p->password, p->password_len, p->keyfile_fds, p->keyfile_count)) {
        closeAll(p->keyfile_fds, p->keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    try {
        const int volId = p->vol_id;
        clearUnlockCancellation(volId);

        auto carriers = makeTargets(p->carrier_paths, p->carrier_count, p->read_only != 0);
        // The identical canonical order create used, then the extent boundaries come from each carrier's own
        // header-keyed trailer.
        CompositeMap::sortCanonical(carriers);
        const CapacityProfile profile = CarrierProfiler::profileForRecovery(carriers);
        const std::vector<CarrierExtent> extents = CompositeMap::deriveExtents(profile.perFile);
        if (extents.empty()) {
            closeAll(p->keyfile_fds, p->keyfile_count);
            setText(error_out, "NO_EXTENTS_DETECTED");
            return VE_ERR_FAILED;
        }

        static const unsigned char kEmpty[1] = {0};
        const CompositeUnlockResult unlocked = prepareCompositeSession(
            volId, carriers, extents, p->password ? p->password : kEmpty,
            p->password ? static_cast<size_t>(p->password_len) : 0, p->pim, p->cipher_id, p->hash_id,
            p->keyfile_count > 0 ? p->keyfile_fds : nullptr, p->keyfile_count, p->read_only != 0);
        if (!unlocked.success) {
            setText(error_out, unlocked.errorCode);
            return isUnlockCancelled(volId) ? VE_ERR_CANCELLED : VE_ERR_FAILED;
        }

        bool mountOk;
        {
            std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
            mountOk = ensureMounted(volId);
        }
        if (!mountOk) {
            ve_lock(volId);  // never leave a decrypted session behind a failed mount (what ve_unlock does too)
            setText(error_out, "FILESYSTEM_MOUNT_FAILED");
            return VE_ERR_MOUNT_FAILED;
        }
        return VE_OK;
    } catch (...) {
        return VE_ERR_EXCEPTION;
    }
}
