#pragma once
#include <cstdint>
#include <string>
#include <vector>
#include <unordered_map>
#include <list>
#include <mutex>
#include <unistd.h>
#include <fcntl.h>

struct CarrierTarget {
    int fd = -1;
    std::string path;
    bool readOnly = false;
    bool closeOnDestruct = false;
};

class CarrierFdCache {
public:
    explicit CarrierFdCache(size_t maxOpen = 32);
    ~CarrierFdCache();

    CarrierFdCache(const CarrierFdCache&) = delete;
    CarrierFdCache& operator=(const CarrierFdCache&) = delete;

    uint32_t addTarget(int fd, const std::string& path = "", bool readOnly = false, bool closeOnDestruct = false);

    // Returns a pinned file descriptor. Must be released with release().
    int acquire(uint32_t fileIndex);
    void release(uint32_t fileIndex);

    size_t targetCount() const;
    void closeAll();

private:
    struct CacheNode {
        uint32_t fileIndex;
        int fd;
        int pinCount;
    };

    size_t maxOpen_;
    std::vector<CarrierTarget> targets_;
    std::unordered_map<uint32_t, std::list<CacheNode>::iterator> lookup_;
    std::list<CacheNode> lruList_;
    mutable std::mutex mutex_;

    void evictOldestUnpinnedLocked();
    int openTargetLocked(uint32_t fileIndex);
};