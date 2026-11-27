// POSIX half of the raw-device layer (see ve_raw_device.h). Linux is the target; other POSIX hosts
// get file/image support (no enumeration). No engine headers.
#include "ve_raw_device.h"

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>

#if defined(__linux__)
#include <linux/fs.h>
#include <sys/ioctl.h>
#endif

namespace veraw::plat {

namespace {

int fdOf(Handle h) { return static_cast<int>(h); }

#if defined(__linux__)

std::string trim(std::string s) {
    const char* ws = " \t\r\n";
    const size_t b = s.find_first_not_of(ws);
    if (b == std::string::npos) return std::string();
    const size_t e = s.find_last_not_of(ws);
    s = s.substr(b, e - b + 1);
    std::string out;  // collapse runs of spaces ("ATA      Samsung SSD" -> "ATA Samsung SSD")
    for (char c : s) {
        if (c == ' ' && !out.empty() && out.back() == ' ') continue;
        out.push_back(c);
    }
    return out;
}

std::string readSmallFile(const std::string& path) {
    std::ifstream f(path);
    if (!f) return std::string();
    std::string line;
    std::getline(f, line);
    return trim(line);
}

uint64_t readU64(const std::string& path, uint64_t fallback = 0) {
    const std::string s = readSmallFile(path);
    if (s.empty()) return fallback;
    char* end = nullptr;
    const unsigned long long v = std::strtoull(s.c_str(), &end, 10);
    return (end && end != s.c_str()) ? static_cast<uint64_t>(v) : fallback;
}

std::string realPath(const std::string& p) {
    char buf[PATH_MAX];
    return ::realpath(p.c_str(), buf) ? std::string(buf) : std::string();
}

std::vector<std::string> listDir(const std::string& path) {
    std::vector<std::string> names;
    DIR* d = ::opendir(path.c_str());
    if (!d) return names;
    while (const dirent* e = ::readdir(d)) {
        if (std::strcmp(e->d_name, ".") == 0 || std::strcmp(e->d_name, "..") == 0) continue;
        names.emplace_back(e->d_name);
    }
    ::closedir(d);
    std::sort(names.begin(), names.end());
    return names;
}

bool startsWith(const std::string& s, const char* prefix) { return s.rfind(prefix, 0) == 0; }

bool wantedDisk(const std::string& n) {
    if (startsWith(n, "sd") || startsWith(n, "vd") || startsWith(n, "xvd") || startsWith(n, "hd")) return true;
    if (startsWith(n, "nvme")) return n.find('n', 4) != std::string::npos;
    if (startsWith(n, "mmcblk")) return n.find("boot") == std::string::npos && n.find("rpmb") == std::string::npos;
    return false;
}

// /dev/disk/by-id link that points at /dev/<name> (the whole disk): survives sdb -> sdc after a replug.
std::string stableIdPath(const std::string& name) {
    const std::string target = "/dev/" + name;
    std::vector<std::string> preferred;
    for (const std::string& link : listDir("/dev/disk/by-id")) {
        if (link.find("-part") != std::string::npos) continue;
        if (!(startsWith(link, "usb-") || startsWith(link, "ata-") || startsWith(link, "nvme-") ||
              startsWith(link, "mmc-") || startsWith(link, "scsi-") || startsWith(link, "virtio-"))) {
            continue;
        }
        if (startsWith(link, "nvme-eui.")) continue;
        if (realPath("/dev/disk/by-id/" + link) == target) preferred.push_back(link);
    }
    return preferred.empty() ? target : "/dev/disk/by-id/" + preferred.front();
}

// major:minor -> mount points, from /proc/self/mountinfo.
std::map<std::string, std::vector<std::string>> mountsByDevno() {
    std::map<std::string, std::vector<std::string>> out;
    std::ifstream f("/proc/self/mountinfo");
    std::string line;
    while (std::getline(f, line)) {
        std::istringstream in(line);
        std::string id, parent, devno, root, mountPoint;
        if (in >> id >> parent >> devno >> root >> mountPoint) out[devno].push_back(mountPoint);
    }
    return out;
}

#endif  // __linux__

}  // namespace

OpenResult open(const std::string& path, bool writable, Handle* handle, uint64_t* sizeBytes, uint32_t* sectorSize,
                int* osError) {
    struct stat st;
    if (::stat(path.c_str(), &st) != 0) {
        if (osError) *osError = errno;
        return (errno == ENOENT || errno == ENOTDIR) ? OpenResult::kNotFound
               : errno == EACCES                    ? OpenResult::kPermission
                                                    : OpenResult::kFailed;
    }
    const bool isBlock = S_ISBLK(st.st_mode);
    if (!isBlock && !S_ISREG(st.st_mode)) {
        if (osError) *osError = EINVAL;
        return OpenResult::kUnsupported;
    }

    int flags = (writable ? O_RDWR : O_RDONLY) | O_CLOEXEC;
#if defined(__linux__)
    // Exclusive open of a block device: the kernel refuses (EBUSY) while it, or any partition of it, is
    // mounted or claimed, so we never write under a file system the OS is using.
    if (writable && isBlock) flags |= O_EXCL;
#endif
    const int fd = ::open(path.c_str(), flags);
    if (fd < 0) {
        const int err = errno;
        if (osError) *osError = err;
        switch (err) {
            case EACCES:
            case EPERM:
            case EROFS: return OpenResult::kPermission;
            case EBUSY: return OpenResult::kBusy;
            case ENOENT:
            case ENXIO:
            case ENODEV: return OpenResult::kNotFound;
            default: return OpenResult::kFailed;
        }
    }

    uint64_t size = 0;
    uint32_t sector = 512;
    if (isBlock) {
#if defined(__linux__)
        unsigned long long bytes = 0;
        if (::ioctl(fd, BLKGETSIZE64, &bytes) == 0) size = bytes;
        int logical = 0;
        if (::ioctl(fd, BLKSSZGET, &logical) == 0 && logical > 0) sector = static_cast<uint32_t>(logical);
#endif
        if (size == 0) {
            const off_t end = ::lseek(fd, 0, SEEK_END);
            if (end > 0) size = static_cast<uint64_t>(end);
        }
    } else {
        size = static_cast<uint64_t>(st.st_size);
    }
    *handle = fd;
    *sizeBytes = size;
    *sectorSize = sector;
    return OpenResult::kOk;
}

bool pread(Handle h, void* buf, size_t len, uint64_t offset) {
    unsigned char* p = static_cast<unsigned char*>(buf);
    while (len > 0) {
        const ssize_t n = ::pread(fdOf(h), p, len, static_cast<off_t>(offset));
        if (n < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        if (n == 0) return false;  // past the end
        p += n;
        len -= static_cast<size_t>(n);
        offset += static_cast<uint64_t>(n);
    }
    return true;
}

bool pwrite(Handle h, const void* buf, size_t len, uint64_t offset) {
    const unsigned char* p = static_cast<const unsigned char*>(buf);
    while (len > 0) {
        const ssize_t n = ::pwrite(fdOf(h), p, len, static_cast<off_t>(offset));
        if (n < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        if (n == 0) return false;
        p += n;
        len -= static_cast<size_t>(n);
        offset += static_cast<uint64_t>(n);
    }
    return true;
}

bool sync(Handle h) { return ::fsync(fdOf(h)) == 0; }

void close(Handle h) {
    if (h != kInvalid) ::close(fdOf(h));
}

std::string canonical(const std::string& path) {
    char buf[PATH_MAX];
    return ::realpath(path.c_str(), buf) ? std::string(buf) : path;
}

std::vector<DeviceInfo> enumerate() {
    std::vector<DeviceInfo> out;
#if defined(__linux__)
    const auto mounts = mountsByDevno();
    for (const std::string& name : listDir("/sys/block")) {
        if (!wantedDisk(name)) continue;
        const std::string sys = "/sys/block/" + name;
        const uint64_t sectors512 = readU64(sys + "/size");
        if (sectors512 == 0) continue;  // empty card-reader slot

        DeviceInfo d;
        d.sizeBytes = sectors512 * 512;
        d.sectorSize = static_cast<uint32_t>(readU64(sys + "/queue/logical_block_size", 512));
        if (d.sectorSize == 0) d.sectorSize = 512;
        d.removable = readU64(sys + "/removable") == 1;

        std::string vendor = readSmallFile(sys + "/device/vendor");
        const std::string model = readSmallFile(sys + "/device/model");
        if (vendor == "ATA") vendor.clear();
        d.name = trim(vendor + (vendor.empty() || model.empty() ? "" : " ") + model);

        const std::string devPath = realPath(sys + "/device");
        if (devPath.find("/usb") != std::string::npos) d.bus = "usb";
        else if (startsWith(name, "nvme")) d.bus = "nvme";
        else if (startsWith(name, "mmcblk")) d.bus = "mmc";
        else if (startsWith(name, "vd") || startsWith(name, "xvd")) d.bus = "virtual";
        else if (devPath.find("/ata") != std::string::npos) d.bus = "sata";
        else d.bus = "scsi";

        // Is anything on it mounted (the disk node, or a partition of it), or held by device-mapper/LVM?
        std::vector<std::string> devnos;
        devnos.push_back(readSmallFile(sys + "/dev"));
        bool held = !listDir(sys + "/holders").empty();
        for (const std::string& child : listDir(sys)) {
            if (!startsWith(child, name.c_str())) continue;
            if (::access((sys + "/" + child + "/partition").c_str(), F_OK) != 0) continue;
            devnos.push_back(readSmallFile(sys + "/" + child + "/dev"));
            if (!listDir(sys + "/" + child + "/holders").empty()) held = true;
        }
        d.inUse = held;
        for (const std::string& devno : devnos) {
            const auto it = mounts.find(devno);
            if (it == mounts.end()) continue;
            d.inUse = true;
            for (const std::string& mp : it->second) {
                if (mp == "/" || mp == "/boot" || mp == "/boot/efi") d.system = true;
            }
        }

        d.path = stableIdPath(name);
        d.readable = ::access(("/dev/" + name).c_str(), R_OK) == 0;
        d.writable = ::access(("/dev/" + name).c_str(), W_OK) == 0;
        out.push_back(std::move(d));
    }
#endif
    return out;
}

}  // namespace veraw::plat
