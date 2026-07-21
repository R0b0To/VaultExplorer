#pragma once

#include <cstddef>
#include <cstdint>

struct VolumeState;

// BitLocker (dislocker-backed) container support.
//
// Migrated from libbde (read-only) to dislocker (https://github.com/Aorimn/
// dislocker), which supports real read-write access via its dis_new()/
// dis_setopt()/dis_initialize()/dislock()/enlock()/dis_destroy() API. Unlike
// VeraCrypt/LUKS -- which this app decrypts sector-by-sector inline (see
// crypto/cascade.h, mbedtls_aes_crypt_xts in vaultexplorer.cpp/
// ntfs_backend.cpp) -- BitLocker's own decryption (FVEK-derived AES-CBC with
// the Elephant diffuser, or AES-XTS on newer volumes) is owned entirely by
// dislocker. This module's job is narrower: give dislocker a real, openable
// path to the encrypted volume and drive its set-option + initialize +
// dislock/enlock calls.
//
// IMPORTANT ARCHITECTURAL DIFFERENCE FROM THE OLD LIBBDE BACKEND: dislocker
// has no libbfio-style pluggable I/O callback abstraction. Its config takes
// a real filesystem path (DIS_OPT_VOLUME_PATH) that IT opens itself via
// open(2) -- there is no supported way to hand it a custom read/write
// callback pair the way libbde's libbfio_handle_t allowed. Two
// consequences:
//
//   1. File-backed containers: trivial. We already have a real fd (opened
//      Kotlin-side); we hand dislocker the magic-symlink path
//      "/proc/self/fd/<fd>" instead of a real path string, which the
//      kernel resolves back to that same open file. No new JNI plumbing.
//
//   2. USB-backed containers: NOT trivial. This app's USB "block device" is
//      not a real kernel block device -- Android apps can't get raw fd/
//      /dev/sdX access to USB mass storage without root, which is exactly
//      why usbReadSectors/usbWriteSectors exist (bulk-transfer JNI calls
//      into Kotlin's UsbMassStorageDevice). libbde tolerated that via its
//      custom io_handle; dislocker can't. The fix: Kotlin-side
//      UsbBlockBridge.openBitlockerProxyFd() uses Android's AppFuse
//      facility (StorageManager.openProxyFileDescriptor(), API 26+) to
//      mint a REAL, kernel-visible, seekable fd backed by a
//      ProxyFileDescriptorCallback that forwards onRead/onWrite to the
//      exact same UsbMassStorageDevice sector transport usbReadSectors/
//      usbWriteSectors already use. That fd is then exposed to dislocker
//      the same way as the file case: "/proc/self/fd/<proxy fd>". See
//      UsbBlockBridge.kt for the callback implementation.
//
// Only the two off-host-meaningful BitLocker key protectors are supported:
// password and the 48-digit numerical recovery key. TPM-backed unlock has
// no meaning off the original Windows host and is not attempted.

// Cheap signature-only probe -- mirrors isLuksContainer()'s role in
// session_prepare.cpp: gates whether it's worth attempting the full
// dislocker open+unlock at all. Implemented as a hand-rolled FVE metadata
// signature check (see bitlocker_backend.cpp) rather than a dislocker call,
// since dis_initialize() doesn't expose a cheap signature-only probe
// separate from a full (credentialed) unlock attempt the way libbde's
// libbde_check_volume_signature_file_io_handle() did.
bool bitlockerDetectFile(int fd);
bool bitlockerDetectUsb(int volId, uint64_t partitionStartSector);

// Full unlock. Mirrors prepareLuksSession/prepareUsbLuksSession's ownership
// contract: the file-based variant always takes ownership of `fd` (closes
// it itself on failure); on any definitive failure (this WAS a BitLocker
// volume, the credential just didn't unlock it) the caller should treat
// that as a hard failure rather than falling through to another format,
// same as a failed LUKS keyslot scan.
//
// `password` is whatever the user typed -- a literal password OR a 48-digit
// recovery key (with or without the usual dash-separated groups-of-6
// formatting); both are tried automatically, in whichever order looks more
// likely given the input shape, the same way this app already auto-tries
// cipher/hash combinations for VeraCrypt rather than asking the user to
// pick up front.
//
// `readOnly` is now honored for real (dislocker supports write) -- unlike
// the old libbde backend, which force-set VolumeState::readOnly = true
// regardless of what the caller asked for.
bool prepareBitLockerSession(int fd, const unsigned char* password, size_t passwordLen,
                             int volId, bool readOnly);
bool prepareUsbBitLockerSession(uint64_t partitionStartSector, uint64_t partitionSizeBytes,
                                const unsigned char* password, size_t passwordLen,
                                int volId, bool readOnly);

// Post-unlock decrypted I/O against volumes[volumeId]'s dis_context_t.
// `logicalOffset`/byteCount are relative to the start of the BitLocker
// volume (same convention as VolumeState::dataOffset-relative reads
// elsewhere, e.g. ntfsPread's `startByte`) -- dislocker owns translating
// that into real encrypted-sector I/O against the fd it opened from
// DIS_OPT_VOLUME_PATH internally.
bool bitlockerRead(int volumeId, uint64_t logicalOffset, unsigned char* outBuf, size_t byteCount);
bool bitlockerWrite(int volumeId, uint64_t logicalOffset, const unsigned char* inBuf, size_t byteCount);

// Releases the dis_context_t owned by this slot (and, for USB sessions, the
// AppFuse proxy fd), if any. Safe to call unconditionally (no-op for
// non-BitLocker or already-closed slots).
//
// Called from VolumeState::reset() specifically -- NOT from
// unmountVolume() alongside the NTFS/ext teardown. lockNative() calls
// v.reset() BEFORE unmountVolume(), and reset() already clears fd/
// containerFormat/ntfsVol as it goes, so by the time unmountVolume() runs
// those fields (and any format-specific branch keyed off them) have
// already been wiped. reset() is where every other owned resource in this
// struct actually gets freed (preservedDerivedKey, the LUKS XTS contexts)
// for the same reason -- follow that precedent rather than the
// unmountVolume() one.
void bitlockerCloseVolume(VolumeState& v);