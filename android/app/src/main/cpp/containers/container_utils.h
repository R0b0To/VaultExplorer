#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

#include "ff.h"
#include "crypto/cascade.h"

void sanitizeString(std::string& value);
uint32_t readUint32LE(const unsigned char* data);
uint64_t readUint64LE(const unsigned char* data);
uint64_t fatToUnixTimestamp(WORD date, WORD time);
void unixToFatTimestamp(uint64_t unixTime, WORD& date, WORD& time);
uint32_t crc32(const unsigned char* data, size_t length);

// Encrypts a VeraCrypt header body (the VC_HEADER_BODY_SIZE-byte structure
// holding the master key and volume parameters) using cascade-XTS with the
// given cipher and header key -- the same on-disk header encryption used
// for every VC-format header write path (fresh create, hidden-volume
// create, and password change). This was previously duplicated verbatim in
// five places across container_create.cpp and container_create_usb.cpp;
// pulled out as a pure function (no I/O, no session/volume state) so a
// future fix only needs to happen once.
//
// `body` and `encBody` must each point to VC_HEADER_BODY_SIZE bytes (see
// crypto/vc_header_layout.h); they may not overlap. Returns false if
// cascadeSetKeys fails for the given cipher/key combination, in which case
// encBody's contents are unspecified and must not be used.
bool encryptVeraCryptHeaderBody(CascadeId cipher, const unsigned char* headerKey,
                                 int masterKeyLen, int layerCount,
                                 const unsigned char* body, unsigned char* encBody);
