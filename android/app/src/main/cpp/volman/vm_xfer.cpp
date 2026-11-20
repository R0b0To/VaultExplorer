#include "vm_xfer.h"

#include <algorithm>
#include <cstring>

namespace vm {

VolumeFileSource::VolumeFileSource(VolumeManager& m, int volId, std::string path, size_t chunkBytes)
    : m_(m), volId_(volId), path_(std::move(path)), chunk_(chunkBytes ? chunkBytes : VolumeManager::kCopyChunkBytes) {
    int64_t sz = -1;
    if (ok(m_.getFileSize(volId_, path_, sz))) size_ = sz;
}

VolumeFileSource::~VolumeFileSource() { wipe(); }

void VolumeFileSource::wipe() {
    if (!cur_.empty()) secureZero(cur_.data(), cur_.size());
    cur_.clear();
    curPos_ = 0;
}

int64_t VolumeFileSource::read(uint8_t* buf, size_t n) {
    if (size_ < 0) return -1;
    if (n == 0 || pos_ >= size_) return 0;
    if (curPos_ >= cur_.size()) {
        wipe();
        const size_t want = static_cast<size_t>(std::min<int64_t>(static_cast<int64_t>(chunk_), size_ - pos_));
        if (!ok(m_.readFileChunk(volId_, path_, pos_, want, cur_)) || cur_.empty()) {
            wipe();
            return -1;
        }
        if (cur_.size() > want) {   // a volume that returns more than asked cannot lengthen the file
            secureZero(cur_.data() + want, cur_.size() - want);
            cur_.resize(want);
        }
    }
    const size_t take = static_cast<size_t>(std::min<int64_t>(
        std::min<int64_t>(static_cast<int64_t>(n), static_cast<int64_t>(cur_.size() - curPos_)), size_ - pos_));
    std::memcpy(buf, cur_.data() + curPos_, take);
    curPos_ += take;
    pos_ += static_cast<int64_t>(take);
    return static_cast<int64_t>(take);
}

xfer::Result hashVolumeFile(VolumeManager& m, int volId, const std::string& path,
                            const std::vector<xfer::HashAlgo>& algos, xfer::Observer* obs,
                            std::vector<xfer::Digest>& out) {
    out.clear();
    VolumeFileSource src(m, volId, path);
    if (!src.valid()) return xfer::Result::Failed;
    return xfer::hashStream(src, algos, static_cast<uint64_t>(src.size()), obs, out);
}

}  // namespace vm
