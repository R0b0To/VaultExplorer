#ifndef VE_DESKTOP_TRANSFER_ENGINE_BRIDGE_WIN_H_
#define VE_DESKTOP_TRANSFER_ENGINE_BRIDGE_WIN_H_

#include <windows.h>

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
  bool is_dir = false;
  int64_t size_bytes = 0;
  int64_t modified_secs = 0;
  std::string local_path;
};

struct VirtualFileDescriptorEntry {
  std::string vault_path;
  std::wstring rel_win_path;
  bool is_dir = false;
  int64_t size_bytes = 0;
  int64_t modified_secs = 0;
};

struct TransferBatch {
  std::string batch_id;
  int32_t vol_id = -1;
  std::string staging_dir;
  bool prefer_virtual_stream = false;
  bool is_sensitive = true;
  bool is_clipboard = false;
  std::vector<TransferItemSpec> items;

  std::mutex mu;
  std::atomic<bool> cancelled{false};
  int32_t op_id = 0;
  bool realized = false;
  bool staging_in_progress = false;
  std::vector<std::wstring> staged_root_paths;
};

// Dynamic C ABI bindings to vaultexplorer_engine.dll (resolved via GetModuleHandleW / LoadLibraryW).
class EngineBridgeWin {
 public:
  EngineBridgeWin() = default;
  ~EngineBridgeWin() = default;

  bool Initialize(const std::string& library_path_utf8);
  bool IsAvailable() const;

  int32_t ExportFile(int32_t vol_id, const char* vault_path, const char* host_dest_path, int32_t op_id) const;
  int64_t OpenStream(int32_t vol_id, const char* vault_path) const;
  int32_t ReadStream(int32_t vol_id, int64_t handle, int64_t offset, uint8_t* dest, int32_t length) const;
  void CloseStream(int32_t vol_id, int64_t handle) const;
  void OpRegister(int32_t op_id, int32_t flavor) const;
  void OpCancel(int32_t op_id) const;
  void OpUnregister(int32_t op_id) const;
  int32_t ListDirectory(int32_t vol_id, const char* vault_path, std::vector<std::string>* entries_out) const;
  int64_t GetFileSize(int32_t vol_id, const char* vault_path) const;

  // Materializes all items of |batch| into |batch->staging_dir|. Safe to call from a background thread.
  bool StageBatch(TransferBatch* batch, std::vector<std::string>* utf8_paths_out) const;

  // Expands |items| recursively into a flat descriptor list for CFSTR_FILEDESCRIPTORW.
  bool ExpandVirtualEntries(int32_t vol_id,
                            const std::vector<TransferItemSpec>& items,
                            std::vector<VirtualFileDescriptorEntry>* out) const;

 private:
  bool ExportSingle(TransferBatch* batch,
                    const std::string& vault_path,
                    const std::wstring& dest_win_path,
                    int32_t op_id) const;
  bool ExportTree(TransferBatch* batch,
                  const std::string& vault_path,
                  const std::wstring& dest_win_dir,
                  int32_t op_id) const;
  void CollectVirtualRecursive(int32_t vol_id,
                               const std::string& vault_path,
                               const std::wstring& rel_win_path,
                               std::vector<VirtualFileDescriptorEntry>* out) const;

  using FnBufferFree = void (*)(VeBuffer*);
  using FnListDir = int32_t (*)(int32_t, const char*, VeBuffer*);
  using FnGetFileSize = int64_t (*)(int32_t, const char*);
  using FnExportFile = int32_t (*)(int32_t, const char*, const char*, int32_t);
  using FnOpenStream = int64_t (*)(int32_t, const char*);
  using FnReadStream = int32_t (*)(int32_t, int64_t, int64_t, uint8_t*, int32_t);
  using FnCloseStream = void (*)(int32_t, int64_t);
  using FnOpRegister = void (*)(int32_t, int32_t);
  using FnOpCancel = void (*)(int32_t);
  using FnOpUnregister = void (*)(int32_t);

  mutable std::mutex init_mu_;
  HMODULE module_ = nullptr;
  FnBufferFree fn_buffer_free_ = nullptr;
  FnListDir fn_list_dir_ = nullptr;
  FnGetFileSize fn_get_file_size_ = nullptr;
  FnExportFile fn_export_file_ = nullptr;
  FnOpenStream fn_open_stream_ = nullptr;
  FnReadStream fn_read_stream_ = nullptr;
  FnCloseStream fn_close_stream_ = nullptr;
  FnOpRegister fn_op_register_ = nullptr;
  FnOpCancel fn_op_cancel_ = nullptr;
  FnOpUnregister fn_op_unregister_ = nullptr;
};

// UTF-8 / UTF-16 helpers.
std::wstring Utf8ToWide(const std::string& utf8);
std::string WideToUtf8(const std::wstring& wide);

// Sanitizes a single path segment for Windows NTFS/FAT filesystems.
std::wstring SanitizeWindowsFileName(const std::string& name_utf8);

// Applies owner-only DACL and FILE_ATTRIBUTE_NOT_CONTENT_INDEXED | FILE_ATTRIBUTE_TEMPORARY.
bool HardenStagingDirectoryWin(const std::wstring& dir_path);

// Checks if any external process holds an open handle to a file inside |dir_path|.
bool IsStagingBatchInUseWin(const std::wstring& dir_path);

// Converts Unix epoch seconds to Windows FILETIME (zero FILETIME when <= 0).
FILETIME UnixSecondsToFileTime(int64_t epoch_seconds);

}  // namespace ve_transfer

#endif  // VE_DESKTOP_TRANSFER_ENGINE_BRIDGE_WIN_H_
