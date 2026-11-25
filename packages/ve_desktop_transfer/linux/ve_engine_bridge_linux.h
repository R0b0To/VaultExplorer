#ifndef VE_DESKTOP_TRANSFER_ENGINE_BRIDGE_LINUX_H_
#define VE_DESKTOP_TRANSFER_ENGINE_BRIDGE_LINUX_H_

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace ve_transfer {

struct VeBuffer {
  uint8_t* data;
  size_t len;
};

struct TransferItemSpec {
  std::string vault_path;
  std::string name;
  bool is_dir;
  int64_t size_bytes;
  int64_t modified_secs;
  std::string local_path;

  TransferItemSpec()
      : is_dir(false), size_bytes(0), modified_secs(0) {}
};

struct TransferBatch {
  std::string batch_id;
  int32_t vol_id;
  std::string staging_dir;
  bool is_sensitive;
  bool is_clipboard;
  std::vector<TransferItemSpec> items;

  std::mutex mu;
  std::atomic<bool> cancelled;
  int32_t op_id;
  bool realized;
  std::vector<std::string> staged_root_paths;

  TransferBatch()
      : vol_id(-1),
        is_sensitive(true),
        is_clipboard(false),
        cancelled(false),
        op_id(0),
        realized(false) {}
};

class EngineBridgeLinux {
 public:
  EngineBridgeLinux();
  ~EngineBridgeLinux() = default;

  bool Initialize(const std::string& library_path);
  bool IsAvailable() const;

  int32_t ExportFile(int32_t vol_id,
                     const char* vault_path,
                     const char* host_dest_path,
                     int32_t op_id) const;
  void OpRegister(int32_t op_id, int32_t flavor) const;
  void OpCancel(int32_t op_id) const;
  void OpUnregister(int32_t op_id) const;
  int32_t ListDirectory(int32_t vol_id,
                        const char* vault_path,
                        std::vector<std::string>* entries_out) const;

  bool StageBatch(TransferBatch* batch, std::vector<std::string>* paths_out) const;

 private:
  bool ExportSingle(TransferBatch* batch,
                    const std::string& vault_path,
                    const std::string& dest_path,
                    int32_t op_id) const;
  bool ExportTree(TransferBatch* batch,
                  const std::string& vault_path,
                  const std::string& dest_dir,
                  int32_t op_id) const;

  using FnBufferFree = void (*)(VeBuffer*);
  using FnListDir = int32_t (*)(int32_t, const char*, VeBuffer*);
  using FnExportFile = int32_t (*)(int32_t, const char*, const char*, int32_t);
  using FnOpRegister = void (*)(int32_t, int32_t);
  using FnOpCancel = void (*)(int32_t);
  using FnOpUnregister = void (*)(int32_t);

  mutable std::mutex init_mu_;
  void* handle_;
  FnBufferFree fn_buffer_free_;
  FnListDir fn_list_dir_;
  FnExportFile fn_export_file_;
  FnOpRegister fn_op_register_;
  FnOpCancel fn_op_cancel_;
  FnOpUnregister fn_op_unregister_;
};

std::string SanitizePosixFileName(const std::string& name);
bool HardenStagingDirectoryLinux(const std::string& dir_path);
bool IsStagingBatchInUseLinux(const std::string& dir_path);

}  // namespace ve_transfer

#endif  // VE_DESKTOP_TRANSFER_ENGINE_BRIDGE_LINUX_H_
