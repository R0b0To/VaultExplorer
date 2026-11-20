// Bridges the transfer helpers (../xfer) to vm::VolumeManager: a vault file as a byte source,
// and hashing a vault file in one native pass (the loop ImportExportHandlers.sha256VaultFile
// and HashVerifierHandlers run chunk by chunk across JNI).
#pragma once

#include <string>
#include <vector>

#include "vm_manager.h"
#include "xfer/xfer_hash.h"
#include "xfer/xfer_io.h"

namespace vm {

// Reads one file of a volume front to back in `chunkBytes` pieces. Like the copy path, a read
// that fails, or comes back empty before the file's size was reached, is an error (-1), never an
// end of file: a digest of a truncated read would be wrong without anyone noticing. Cached
// plaintext is wiped as it is replaced and on destruction.
class VolumeFileSource final : public xfer::ByteSource {
public:
    VolumeFileSource(VolumeManager& m, int volId, std::string path, size_t chunkBytes = VolumeManager::kCopyChunkBytes);
    ~VolumeFileSource() override;

    // False when the file does not exist, is a folder, or the volume is not unlocked.
    bool valid() const { return size_ >= 0; }
    int64_t size() const { return size_; }

    int64_t read(uint8_t* buf, size_t n) override;

private:
    void wipe();

    VolumeManager& m_;
    const int volId_;
    const std::string path_;
    const size_t chunk_;
    int64_t size_ = -1;
    int64_t pos_ = 0;
    Bytes cur_;
    size_t curPos_ = 0;
};

// Digests of the file at `path` on volume `volId` for every algorithm in `algos`. Failed when the
// file cannot be read in full (including a locked volume); Cancelled when `obs` says so.
xfer::Result hashVolumeFile(VolumeManager& m, int volId, const std::string& path,
                            const std::vector<xfer::HashAlgo>& algos, xfer::Observer* obs,
                            std::vector<xfer::Digest>& out);

}  // namespace vm
