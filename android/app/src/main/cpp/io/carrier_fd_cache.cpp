#include "carrier_fd_cache.h"
#include <algorithm>

#undef min
#undef max

CarrierFdCache::CarrierFdCache(size_t maxOpen)
    : maxOpen_(maxOpen > 0 ? maxOpen : 32) {}

CarrierFdCache::~CarrierFdCache() {
    closeAll();
}

void CarrierFdCache::closeAll() {
    std::lock_guard<std::mutex> lock(mutex_);
    
    // 1. Close dynamically opened path descriptors only
    for (auto& node : lruList_) {
        if (node.fileIndex < targets_.size()) {
            if (targets_[node.fileIndex].fd < 0 && node.fd >= 0) {
                ::close(node.fd);
                node.fd = -1;
            }
        }
    }
    lruList_.clear();
    lookup_.clear();

    // 2. Close native-owned descriptors exactly once
    for (auto& target : targets_) {
        if (target.closeOnDestruct && target.fd >= 0) {
            ::close(target.fd);
            target.fd = -1;
        }
    }
}

uint32_t CarrierFdCache::addTarget(int fd, const std::string& path, bool readOnly, bool closeOnDestruct) {
    std::lock_guard<std::mutex> lock(mutex_);
    uint32_t index = static_cast<uint32_t>(targets_.size());
    targets_.push_back({fd, path, readOnly, closeOnDestruct});
    return index;
}

size_t CarrierFdCache::targetCount() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return targets_.size();
}

int CarrierFdCache::openTargetLocked(uint32_t fileIndex) {
    if (fileIndex >= targets_.size()) return -1;
    const auto& target = targets_[fileIndex];

    if (target.fd >= 0) {
        return target.fd;
    }

    if (!target.path.empty()) {
        int flags = target.readOnly ? O_RDONLY : O_RDWR;
#ifdef O_LARGEFILE
        flags |= O_LARGEFILE;
#endif
        int fd = ::open(target.path.c_str(), flags);
        if (fd < 0 && !target.readOnly) {
            fd = ::open(target.path.c_str(), O_RDONLY);
        }
        return fd;
    }

    return target.fd;
}

void CarrierFdCache::evictOldestUnpinnedLocked() {
    for (auto it = lruList_.rbegin(); it != lruList_.rend(); ++it) {
        if (it->pinCount == 0) {
            uint32_t idx = it->fileIndex;
            // Only evict descriptors that can be safely re-opened from disk path
            if (idx < targets_.size() && targets_[idx].fd < 0 && !targets_[idx].path.empty()) {
                if (it->fd >= 0) {
                    ::close(it->fd);
                    it->fd = -1;
                }
                auto forwardIt = std::next(it).base();
                lookup_.erase(idx);
                lruList_.erase(forwardIt);
                return;
            }
        }
    }
}

int CarrierFdCache::acquire(uint32_t fileIndex) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (fileIndex >= targets_.size()) return -1;

    // Fast path: descriptor already supplied directly by caller
    if (targets_[fileIndex].fd >= 0) {
        auto it = lookup_.find(fileIndex);
        if (it != lookup_.end()) {
            it->second->pinCount++;
        } else {
            lruList_.push_front({fileIndex, targets_[fileIndex].fd, 1});
            lookup_[fileIndex] = lruList_.begin();
        }
        return targets_[fileIndex].fd;
    }

    // Path-backed descriptor: resolve with LRU eviction
    auto it = lookup_.find(fileIndex);
    if (it != lookup_.end()) {
        it->second->pinCount++;
        lruList_.splice(lruList_.begin(), lruList_, it->second);
        return it->second->fd;
    }

    if (lruList_.size() >= maxOpen_) {
        evictOldestUnpinnedLocked();
    }

    int fd = openTargetLocked(fileIndex);
    if (fd < 0) return -1;

    lruList_.push_front({fileIndex, fd, 1});
    lookup_[fileIndex] = lruList_.begin();
    return fd;
}

void CarrierFdCache::syncAll() {
    std::lock_guard<std::mutex> lock(mutex_);

    // Fds currently sitting in the LRU list: path-backed carriers that have
    // been opened, plus any caller-supplied fd that has been acquire()'d at
    // least once (the "fast path" in acquire() adds it here too).
    for (auto& node : lruList_) {
        if (node.fd >= 0) ::fsync(node.fd);
    }

    // Caller-supplied fds that were registered directly but never went
    // through acquire()/the LRU list (e.g. formatted but not yet read back).
    for (uint32_t idx = 0; idx < targets_.size(); ++idx) {
        if (targets_[idx].fd >= 0 && lookup_.find(idx) == lookup_.end()) {
            ::fsync(targets_[idx].fd);
        }
    }
}

void CarrierFdCache::release(uint32_t fileIndex) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = lookup_.find(fileIndex);
    if (it != lookup_.end()) {
        if (it->second->pinCount > 0) {
            it->second->pinCount--;
        }
    }
}