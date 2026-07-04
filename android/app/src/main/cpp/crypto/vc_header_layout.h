// crypto/vc_header_layout.h
//
// Named VeraCrypt volume-header field offsets/sizes, cross-checked against
// upstream VeraCrypt (Common/Volumes.h / Common/Volumes.c — the vendored
// copies attached to this project were used as the reference). This header
// is a drop-in: it defines the SAME names vaultexplorer.cpp already used
// (VC_HDR_OFF_*, VC_KEY_OFFSET_MASTER, VC_SALT_SIZE, ...) so the old local
// `static constexpr` block in vaultexplorer.cpp can simply be deleted and
// replaced with `#include "crypto/vc_header_layout.h"` — see the patch
// notes for the exact block to remove.
//
// All TC_HEADER_OFFSET_* constants below are ABSOLUTE offsets from byte 0
// of the 512-byte on-disk header sector (byte 0 == first byte of the
// 64-byte PKCS5 salt). vaultexplorer.cpp works on the already-salt-stripped
// decrypted BODY buffer instead (body[0] == header byte 64), so the
// VC_HDR_OFF_* constants it actually indexes with are those ABSOLUTE
// offsets minus PKCS5_SALT_SIZE, computed once here via VC_BODY_OFFSET so
// there is exactly one source of truth for each field position.
#pragma once
#include <cstdint>
#include <cstddef>

// ── Real VeraCrypt spec constants (Common/Volumes.h) ────────────────────
static constexpr size_t PKCS5_SALT_SIZE                       = 64;
static constexpr int    TC_HEADER_OFFSET_MAGIC                = 64;
static constexpr int    TC_HEADER_OFFSET_VERSION              = 68;
static constexpr int    TC_HEADER_OFFSET_REQUIRED_VERSION     = 70;
static constexpr int    TC_HEADER_OFFSET_KEY_AREA_CRC         = 72;
static constexpr int    TC_HEADER_OFFSET_HIDDEN_VOLUME_SIZE   = 92;
static constexpr int    TC_HEADER_OFFSET_VOLUME_SIZE          = 100;
static constexpr int    TC_HEADER_OFFSET_ENCRYPTED_AREA_START  = 108;
static constexpr int    TC_HEADER_OFFSET_ENCRYPTED_AREA_LENGTH = 116;
static constexpr int    TC_HEADER_OFFSET_FLAGS                = 124;
static constexpr int    TC_HEADER_OFFSET_SECTOR_SIZE          = 128;
static constexpr int    TC_HEADER_OFFSET_HEADER_CRC           = 252;
static constexpr size_t HEADER_MASTER_KEYDATA_OFFSET          = 256;
static constexpr size_t MASTER_KEYDATA_SIZE                   = 256;

// Container/device layout (Common/Volumes.h: TC_VOLUME_HEADER_SIZE,
// TC_VOLUME_HEADER_GROUP_SIZE, TC_VOLUME_DATA_OFFSET,
// TC_HIDDEN_VOLUME_HEADER_OFFSET). Layout of a container file:
//
//   [0,                      65536)   primary header slot   (header @ 0)
//   [65536,                 131072)   hidden-volume header slot (header @ 65536)
//   [131072,      size-131072)        data area (outer/normal volume)
//   [size-131072, size-65536)         backup primary header
//   [size-65536,  size)               backup hidden-volume header
//
// A hidden volume's OWN data area is NOT anchored to 131072 — its start is
// wherever EncryptedAreaStart in ITS header says (VeraCrypt picks a spot
// near the end of the outer volume's free space at format time). That
// value is read out of the header directly; it is never guessed.
static constexpr uint64_t TC_VOLUME_HEADER_SIZE          = 64ULL * 1024;              // 65536
static constexpr uint64_t TC_VOLUME_HEADER_GROUP_SIZE    = 2 * TC_VOLUME_HEADER_SIZE; // 131072
static constexpr uint64_t TC_VOLUME_DATA_OFFSET          = TC_VOLUME_HEADER_GROUP_SIZE;
static constexpr uint64_t TC_HIDDEN_VOLUME_HEADER_OFFSET = TC_VOLUME_HEADER_SIZE;

// ── Body-relative constants this codebase actually indexes with ────────
#define VC_BODY_OFFSET(absolute) (static_cast<int>((absolute) - PKCS5_SALT_SIZE))

static constexpr size_t   VC_SALT_SIZE             = PKCS5_SALT_SIZE;               // 64
static constexpr size_t   VC_HEADER_BODY_SIZE      = 512 - PKCS5_SALT_SIZE;         // 448
static constexpr size_t   VC_FULL_HEADER_SIZE      = 512;
static constexpr uint64_t VC_DATA_AREA_OFFSET      = TC_VOLUME_DATA_OFFSET;         // 131072
static constexpr uint64_t VC_HIDDEN_HEADER_OFFSET  = TC_HIDDEN_VOLUME_HEADER_OFFSET; // 65536

static constexpr int VC_KEY_OFFSET_MASTER        = VC_BODY_OFFSET(HEADER_MASTER_KEYDATA_OFFSET);          // 192
static constexpr int VC_HDR_OFF_KEY_CRC          = VC_BODY_OFFSET(TC_HEADER_OFFSET_KEY_AREA_CRC);          // 8
static constexpr int VC_HDR_OFF_HIDDEN_VOL_SIZE  = VC_BODY_OFFSET(TC_HEADER_OFFSET_HIDDEN_VOLUME_SIZE);    // 28
static constexpr int VC_HDR_OFF_VOLUME_SIZE      = VC_BODY_OFFSET(TC_HEADER_OFFSET_VOLUME_SIZE);           // 36
static constexpr int VC_HDR_OFF_KEY_SCOPE_START  = VC_BODY_OFFSET(TC_HEADER_OFFSET_ENCRYPTED_AREA_START);  // 44
static constexpr int VC_HDR_OFF_KEY_SCOPE_SIZE   = VC_BODY_OFFSET(TC_HEADER_OFFSET_ENCRYPTED_AREA_LENGTH); // 52
static constexpr int VC_HDR_OFF_SECTOR_SIZE      = VC_BODY_OFFSET(TC_HEADER_OFFSET_SECTOR_SIZE);           // 64
static constexpr int VC_HDR_OFF_HEADER_CRC       = VC_BODY_OFFSET(TC_HEADER_OFFSET_HEADER_CRC);            // 188
static constexpr int VC_HDR_CRC_COVERAGE_LEN     = TC_HEADER_OFFSET_HEADER_CRC - TC_HEADER_OFFSET_MAGIC;   // 188
static constexpr int VC_HDR_KEY_CRC_COVERAGE_LEN = static_cast<int>(MASTER_KEYDATA_SIZE);                  // 256

#undef VC_BODY_OFFSET

// FatFs in this project is fixed at FF_MIN_SS == FF_MAX_SS == 512 (see
// ffconf.h) — a perfectly valid VeraCrypt volume with a different
// SectorSize field simply can't be mounted by this app, and we should say
// so cleanly rather than silently misinterpreting sector boundaries.
static constexpr uint32_t VC_SUPPORTED_SECTOR_SIZE = 512;
