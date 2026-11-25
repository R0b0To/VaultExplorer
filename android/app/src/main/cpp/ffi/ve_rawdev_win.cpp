// Windows half of the raw-device layer (see ve_raw_device.h): \\.\PhysicalDriveN. This file includes
// <windows.h> and only ve_raw_device.h (no engine headers), like ve_win_platform.cpp, because the
// engine's FatFs headers clash with the Windows ones.
//
// Raw disk access needs an elevated process (Run as administrator); without it CreateFile fails with
// ERROR_ACCESS_DENIED, reported as kPermission so the UI can say so. Reads and writes on a raw handle
// must be a whole number of sectors at sector-aligned offsets: veraw::readSectors / writeSectors
// (ve_raw_device.cpp) guarantee that.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <winioctl.h>

#include <algorithm>
#include <cctype>
#include <cwchar>
#include <cstring>

#include "ve_raw_device.h"

namespace veraw::plat {

namespace {

HANDLE asHandle(Handle h) { return reinterpret_cast<HANDLE>(h); }

std::wstring widen(const std::string& utf8) {
    if (utf8.empty()) return std::wstring();
    const int n = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
    if (n <= 0) return std::wstring();
    std::wstring w(static_cast<size_t>(n), L'\0');
    ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), &w[0], n);
    return w;
}

std::string trimAscii(std::string s) {
    while (!s.empty() && (s.back() == ' ' || s.back() == '\0')) s.pop_back();
    size_t b = 0;
    while (b < s.size() && s[b] == ' ') ++b;
    return s.substr(b);
}

// Size and logical sector size of an open disk handle (works with a no-access query handle too).
bool diskGeometry(HANDLE h, uint64_t* size, uint32_t* sector) {
    alignas(8) unsigned char buf[1024];
    DWORD got = 0;
    if (!::DeviceIoControl(h, IOCTL_DISK_GET_DRIVE_GEOMETRY_EX, nullptr, 0, buf, sizeof(buf), &got, nullptr)) {
        return false;
    }
    const DISK_GEOMETRY_EX* g = reinterpret_cast<const DISK_GEOMETRY_EX*>(buf);
    *size = static_cast<uint64_t>(g->DiskSize.QuadPart);
    *sector = g->Geometry.BytesPerSector ? g->Geometry.BytesPerSector : 512;
    return true;
}

// The disk number that carries the running Windows (the one holding %SystemDrive%), or -1.
int systemDiskNumber() {
    wchar_t drive[8] = L"C:";
    if (::GetEnvironmentVariableW(L"SystemDrive", drive, 8) == 0) std::wcscpy(drive, L"C:");
    std::wstring path = L"\\\\.\\";
    path += drive;
    HANDLE h = ::CreateFileW(path.c_str(), 0, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
    if (h == INVALID_HANDLE_VALUE) return -1;
    alignas(8) unsigned char buf[512];
    DWORD got = 0;
    int number = -1;
    if (::DeviceIoControl(h, IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, nullptr, 0, buf, sizeof(buf), &got, nullptr)) {
        const VOLUME_DISK_EXTENTS* e = reinterpret_cast<const VOLUME_DISK_EXTENTS*>(buf);
        if (e->NumberOfDiskExtents > 0) number = static_cast<int>(e->Extents[0].DiskNumber);
    }
    ::CloseHandle(h);
    return number;
}

}  // namespace

OpenResult open(const std::string& path, bool writable, Handle* handle, uint64_t* sizeBytes, uint32_t* sectorSize,
                int* osError) {
    const std::wstring wpath = widen(path);
    if (wpath.empty()) {
        if (osError) *osError = ERROR_INVALID_NAME;
        return OpenResult::kFailed;
    }
    DWORD access = GENERIC_READ | (writable ? GENERIC_WRITE : 0);
    HANDLE h = ::CreateFileW(wpath.c_str(), access, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
                             FILE_FLAG_WRITE_THROUGH, nullptr);
    if (h == INVALID_HANDLE_VALUE) {
        const DWORD err = ::GetLastError();
        if (osError) *osError = static_cast<int>(err);
        switch (err) {
            case ERROR_ACCESS_DENIED:
            case ERROR_PRIVILEGE_NOT_HELD: return OpenResult::kPermission;
            case ERROR_SHARING_VIOLATION:
            case ERROR_LOCK_VIOLATION: return OpenResult::kBusy;
            case ERROR_FILE_NOT_FOUND:
            case ERROR_PATH_NOT_FOUND:
            case ERROR_DEVICE_NOT_CONNECTED:
            case ERROR_NOT_READY: return OpenResult::kNotFound;
            default: return OpenResult::kFailed;
        }
    }

    uint64_t size = 0;
    uint32_t sector = 512;
    const DWORD type = ::GetFileType(h);
    if (type == FILE_TYPE_DISK) {
        GET_LENGTH_INFORMATION len;
        DWORD got = 0;
        if (::DeviceIoControl(h, IOCTL_DISK_GET_LENGTH_INFO, nullptr, 0, &len, sizeof(len), &got, nullptr)) {
            size = static_cast<uint64_t>(len.Length.QuadPart);
        }
        uint64_t geoSize = 0;
        uint32_t geoSector = 512;
        if (diskGeometry(h, &geoSize, &geoSector)) {
            sector = geoSector;
            if (size == 0) size = geoSize;
        }
        if (size == 0) {  // a plain file (disk image) answers none of the disk IOCTLs
            LARGE_INTEGER fs;
            if (::GetFileSizeEx(h, &fs)) size = static_cast<uint64_t>(fs.QuadPart);
        }
    } else {
        ::CloseHandle(h);
        if (osError) *osError = ERROR_INVALID_FUNCTION;
        return OpenResult::kUnsupported;
    }
    *handle = reinterpret_cast<Handle>(h);
    *sizeBytes = size;
    *sectorSize = sector;
    return OpenResult::kOk;
}

bool pread(Handle h, void* buf, size_t len, uint64_t offset) {
    unsigned char* p = static_cast<unsigned char*>(buf);
    while (len > 0) {
        LARGE_INTEGER pos;
        pos.QuadPart = static_cast<LONGLONG>(offset);
        if (!::SetFilePointerEx(asHandle(h), pos, nullptr, FILE_BEGIN)) return false;
        const DWORD chunk = static_cast<DWORD>(std::min<size_t>(len, 1u << 20));
        DWORD got = 0;
        if (!::ReadFile(asHandle(h), p, chunk, &got, nullptr) || got == 0) return false;
        p += got;
        len -= got;
        offset += got;
    }
    return true;
}

bool pwrite(Handle h, const void* buf, size_t len, uint64_t offset) {
    const unsigned char* p = static_cast<const unsigned char*>(buf);
    while (len > 0) {
        LARGE_INTEGER pos;
        pos.QuadPart = static_cast<LONGLONG>(offset);
        if (!::SetFilePointerEx(asHandle(h), pos, nullptr, FILE_BEGIN)) return false;
        const DWORD chunk = static_cast<DWORD>(std::min<size_t>(len, 1u << 20));
        DWORD put = 0;
        if (!::WriteFile(asHandle(h), p, chunk, &put, nullptr) || put == 0) return false;
        p += put;
        len -= put;
        offset += put;
    }
    return true;
}

bool sync(Handle h) { return ::FlushFileBuffers(asHandle(h)) != 0; }

void close(Handle h) {
    if (h != kInvalid) ::CloseHandle(asHandle(h));
}

std::string canonical(const std::string& path) {
    std::string s = path;
    for (char& c : s) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    return s;
}

std::vector<DeviceInfo> enumerate() {
    std::vector<DeviceInfo> out;
    const int systemDisk = systemDiskNumber();
    for (int n = 0; n < 64; ++n) {
        const std::wstring wpath = L"\\\\.\\PhysicalDrive" + std::to_wstring(n);
        // Access 0: enough to ask for geometry and properties without being elevated.
        HANDLE q = ::CreateFileW(wpath.c_str(), 0, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
        if (q == INVALID_HANDLE_VALUE) continue;

        DeviceInfo d;
        d.path = "\\\\.\\PhysicalDrive" + std::to_string(n);
        uint64_t size = 0;
        uint32_t sector = 512;
        if (!diskGeometry(q, &size, &sector) || size == 0) {  // an empty card-reader slot
            ::CloseHandle(q);
            continue;
        }
        d.sizeBytes = size;
        d.sectorSize = sector;

        STORAGE_PROPERTY_QUERY query;
        std::memset(&query, 0, sizeof(query));
        query.PropertyId = StorageDeviceProperty;
        query.QueryType = PropertyStandardQuery;
        alignas(8) unsigned char buf[1024];
        DWORD got = 0;
        if (::DeviceIoControl(q, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query), buf, sizeof(buf), &got, nullptr)) {
            const STORAGE_DEVICE_DESCRIPTOR* desc = reinterpret_cast<const STORAGE_DEVICE_DESCRIPTOR*>(buf);
            const char* base = reinterpret_cast<const char*>(buf);
            std::string vendor = desc->VendorIdOffset && desc->VendorIdOffset < got ? base + desc->VendorIdOffset : "";
            std::string product = desc->ProductIdOffset && desc->ProductIdOffset < got ? base + desc->ProductIdOffset : "";
            vendor = trimAscii(vendor);
            product = trimAscii(product);
            if (vendor == "ATA") vendor.clear();
            d.name = trimAscii(vendor + (vendor.empty() || product.empty() ? "" : " ") + product);
            d.removable = desc->RemovableMedia != FALSE;
            switch (static_cast<int>(desc->BusType)) {
                case 7: d.bus = "usb"; break;
                case 0x11: d.bus = "nvme"; break;
                case 0x0B:
                case 3: d.bus = "sata"; break;
                case 0x0C:
                case 0x0D: d.bus = "mmc"; break;
                case 0x0E:
                case 0x0F: d.bus = "virtual"; break;
                default: d.bus = "scsi"; break;
            }
        }
        ::CloseHandle(q);

        d.system = (n == systemDisk);
        // Readable means this process is elevated enough to open it: ask for it, then let go.
        HANDLE r = ::CreateFileW(wpath.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
        if (r != INVALID_HANDLE_VALUE) {
            d.readable = true;
            d.writable = true;  // administrators may write; a mounted volume's sectors still refuse at write time
            ::CloseHandle(r);
        }
        out.push_back(std::move(d));
    }
    return out;
}

}  // namespace veraw::plat
