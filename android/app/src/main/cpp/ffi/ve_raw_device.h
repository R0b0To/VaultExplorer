// Desktop raw block-device access: whole disks and partitions (BitLocker, VeraCrypt, LUKS) opened
// straight from the OS, the desktop counterpart of Android's USB host-mode mass-storage bridge.
//
// The engine already unlocks a raw device (session/session_prepare.cpp: prepareUsbSession scans the
// MBR/GPT partitions for LUKS and BitLocker, then tries VeraCrypt at the start of the device and of
// every partition). It reads and writes through three hooks (platform/engine_hooks.h:
// usbReadSectors / usbWriteSectors / usbSyncDevice) in 512-byte sectors, addressed by volume slot. On
// Android those call into Kotlin; on desktop ffi/ve_callbacks.cpp forwards them here.
//
// Layering (kept so that <windows.h> never meets the engine's FatFs headers, which clash with it):
//   ve_raw_device.cpp      this header's veraw:: API: the per-slot registry, the 512-byte-sector view of
//                          a device whose real sector is larger (4Kn), format probing. No OS headers.
//   ve_rawdev_posix.cpp    veraw::plat:: on Linux (and other POSIX hosts): open / size / pread / pwrite /
//                          fsync / enumeration through /sys/block.
//   ve_rawdev_win.cpp      veraw::plat:: on Windows: \\.\PhysicalDriveN.
//
// A "device" may also be a regular file (a disk image): the POSIX layer accepts it, which is what the
// smoke test uses, and is handy for opening a raw disk dump.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace veraw {

constexpr uint32_t kEngineSector = 512;  // the unit of the engine's hooks

struct DeviceInfo {
    std::string path;       // what ve_unlock_device takes; on Linux a stable /dev/disk/by-id path when one exists
    std::string name;       // "Vendor Model", may be empty
    std::string bus;        // "usb" | "nvme" | "sata" | "mmc" | "scsi" | "virtual" | "file" | ""
    uint64_t sizeBytes = 0;
    uint32_t sectorSize = 512;
    bool removable = false;
    bool readable = false;  // this process may open it for reading right now
    bool writable = false;  // ... and for writing
    bool inUse = false;     // a file system on it (or one of its partitions) is mounted by the OS
    bool system = false;    // it carries the running operating system
    std::vector<std::string> formats;  // "bitlocker" | "luks" found at the start of a partition (best effort)
};

namespace plat {

using Handle = intptr_t;
constexpr Handle kInvalid = -1;

enum class OpenResult { kOk = 0, kNotFound, kPermission, kBusy, kUnsupported, kFailed };

// Opens [path] (UTF-8). A writable open of a block device is exclusive where the OS offers that
// (Linux O_EXCL: refused with kBusy while any of its partitions is mounted). On success fills the size
// in bytes and the device's logical sector size. [osError] gets errno / GetLastError() on failure.
OpenResult open(const std::string& path, bool writable, Handle* handle, uint64_t* sizeBytes,
                uint32_t* sectorSize, int* osError);
// Reads / writes exactly [len] bytes at [offset]. Offset and length are multiples of the sector size
// (the caller, veraw::read / write, guarantees it: raw Windows handles require it).
bool pread(Handle h, void* buf, size_t len, uint64_t offset);
bool pwrite(Handle h, const void* buf, size_t len, uint64_t offset);
bool sync(Handle h);
void close(Handle h);
// A path that two openings of the same device share (realpath on POSIX, upper-cased on Windows).
std::string canonical(const std::string& path);
// Every disk the OS lists (no partitions, no unreadable-size entries). Best effort, never throws.
std::vector<DeviceInfo> enumerate();

}  // namespace plat

enum class AttachResult { kOk = 0, kNotFound, kPermission, kBusy, kAlreadyOpen, kUnsupported, kFailed };

// Opens [path] for volume slot [vol] and keeps it until detach(). [sizeBytes] is the device size.
AttachResult attach(int vol, const std::string& path, bool writable, uint64_t* sizeBytes, int* osError);
// Flushes and closes slot [vol]'s device. Safe when nothing is attached.
void detach(int vol);
bool isAttached(int vol);

// The engine's hooks: 512-byte sectors, whatever the device's own sector size is.
bool readSectors(int vol, uint64_t startSector, uint32_t count, unsigned char* out);
bool writeSectors(int vol, uint64_t startSector, uint32_t count, const unsigned char* in);
bool syncDevice(int vol);

// Disks the OS lists, with the formats probed at the start of each partition (readable ones only).
std::vector<DeviceInfo> listDevices();
// The same list as a UTF-8 JSON array (what ve_list_block_devices hands to the host).
std::string devicesToJson(const std::vector<DeviceInfo>& devices);

// Formats found at the start of the device and of each of its MBR/GPT partitions: "bitlocker", "luks".
// Reads through [h] only. Exposed for the tests.
std::vector<std::string> probeFormats(plat::Handle h, uint64_t sizeBytes, uint32_t sectorSize);

}  // namespace veraw
