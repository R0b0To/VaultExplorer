/*
 * VaultExplorer addition to the dislocker overlay (not part of upstream).
 *
 * Lets app code read the Volume Master Key of an unlocked dislocker context
 * without including dislocker's private headers from C++. The "Expand
 * BitLocker container" tool needs the VMK to re-seal the FVE metadata's
 * integrity datum (an AES-CCM-encrypted SHA-256 under the VMK) after it has
 * changed the encrypted volume size.
 */
#ifndef VAULTEXPLORER_DISLOCKER_VMK_EXPORT_H
#define VAULTEXPLORER_DISLOCKER_VMK_EXPORT_H

#include <stddef.h>
#include <stdint.h>

#include "dislocker/dislocker.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Copies the raw VMK key bytes of an initialised (unlocked) context into
 * [out]. Returns the key length in bytes (32 for AES-256 VMKs), or 0 if the
 * context holds no VMK or [out_cap] is too small. The caller owns the copy
 * and must wipe it.
 */
size_t dis_export_vmk(dis_context_t ctx, uint8_t* out, size_t out_cap);

#ifdef __cplusplus
}
#endif

#endif /* VAULTEXPLORER_DISLOCKER_VMK_EXPORT_H */
