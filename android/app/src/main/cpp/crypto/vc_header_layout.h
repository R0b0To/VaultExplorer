#pragma once
#include <cstdint>
#include <cstddef>

// ── Real VeraCrypt spec constants (Common/Volumes.h) ────────────────────
static constexpr size_t PKCS5_SALT_SIZE                        = 64;
static constexpr int    TC_HEADER_OFFSET_MAGIC                 = 64;
static constexpr int    TC_HEADER_OFFSET_VERSION               = 68;
static constexpr int    TC_HEADER_OFFSET_REQUIRED_VERSION      = 70;
static constexpr int    TC_HEADER_OFFSET_KEY_AREA_CRC          = 72;
static constexpr int    TC_HEADER_OFFSET_HIDDEN_VOLUME_SIZE    = 92;
static constexpr int    TC_HEADER_OFFSET_VOLUME_SIZE           = 100;
static constexpr int    TC_HEADER_OFFSET_ENCRYPTED_AREA_START  = 108;
static constexpr int    TC_HEADER_OFFSET_ENCRYPTED_AREA_LENGTH = 116;
static constexpr int    TC_HEADER_OFFSET_FLAGS                 = 124;
static constexpr int    TC_HEADER_OFFSET_SECTOR_SIZE           = 128;
static constexpr int    TC_HEADER_OFFSET_HEADER_CRC            = 252;
static constexpr size_t HEADER_MASTER_KEYDATA_OFFSET           = 256;
static constexpr size_t MASTER_KEYDATA_SIZE                    = 256;


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
static constexpr uint64_t SCAN_BATCH            = 64;
static constexpr uint64_t SCAN_SECTORS          = 2048;

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


static constexpr uint32_t VC_SUPPORTED_SECTOR_SIZE = 512;