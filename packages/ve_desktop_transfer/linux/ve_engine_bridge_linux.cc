#include "ve_engine_bridge_linux.h"

#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <cstdlib>
#include <cstring>

namespace ve_transfer {

namespace {

constexpr int32_t kVeOk = 0;
constexpr int32_t kVeOpExport = 2;

uint32_t ReadU32LE(const uint8_t* p) {
  return static_cast<uint32_t>(p[0]) |
         (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}

struct ParsedDirRow {
  bool is_dir = false;
  int64_t modified_secs = 0;
  std::string name;
};

bool ParseWireEntry(const std::string& wire, ParsedDirRow* out) {
  if (wire.rfind("System:", 0) == 0 || wire.empty()) return false;
  const size_t a = wire.find('|');
  if (a == std::string::npos) return false;
  const size_t b = wire.find('|', a + 1);
  if (b == std::string::npos) return false;
  const size_t c = wire.find('|', b + 1);
  if (c == std::string::npos) return false;

  out->is_dir = (wire[0] == 'D');
  out->modified_secs = std::strtoll(wire.substr(b + 1, c - b - 1).c_str(), nullptr, 10);
  out->name = wire.substr(c + 1);
  return !out->name.empty();
}

std::string JoinPath(const std::string& parent, const std::string& child) {
  if (parent.empty()) return child;
  if (parent.back() == '/') return parent + child;
  return parent + "/" + child;
}

bool PathExists(const std::string& path) {
  struct stat st;
  return lstat(path.c_str(), &st) == 0;
}

std::string UniqueChildPath(const std::string& dir, const std::string& base_name) {
  std::string candidate = JoinPath(dir, base_name);
  if (!PathExists(candidate)) return candidate;
  const size_t dot = base_name.rfind('.');
  const bool has_ext = (dot != std::string::npos && dot > 0 && dot < base_name.size() - 1);
  const std::string stem = has_ext ? base_name.substr(0, dot) : base_name;
  const std::string ext = has_ext ? base_name.substr(dot) : std::string();
  for (int n = 1; n < 10000; ++n) {
    candidate = JoinPath(dir, stem + " (" + std::to_string(n) + ")" + ext);
    if (!PathExists(candidate)) return candidate;
  }
  return JoinPath(dir, base_name);
}

void ApplyModifiedTime(const std::string& path, int64_t epoch_secs) {
  if (epoch_secs <= 0) return;
  struct timespec times[2];
  times[0].tv_sec = 0;
  times[0].tv_nsec = UTIME_OMIT;
  times[1].tv_sec = static_cast<time_t>(epoch_secs);
  times[1].tv_nsec = 0;
  utimensat(AT_FDCWD, path.c_str(), times, AT_SYMLINK_NOFOLLOW);
}

bool IsDigitsOnly(const char* s) {
  if (!s || *s == '\0') return false;
  for (const char* p = s; *p != '\0'; ++p) {
    if (*p < '0' || *p > '9') return false;
  }
  return true;
}

}  // namespace

std::string SanitizePosixFileName(const std::string& name) {
  std::string out = name;
  for (size_t i = 0; i < out.size(); ++i) {
    if (out[i] == '/' || out[i] == '\0') out[i] = '_';
  }
  if (out.empty() || out == "." || out == "..") {
    return "item";
  }
  return out;
}

bool HardenStagingDirectoryLinux(const std::string& dir_path) {
  if (dir_path.empty()) return false;
  return chmod(dir_path.c_str(), 0700) == 0;
}

bool IsStagingBatchInUseLinux(const std::string& dir_path) {
  if (dir_path.empty()) return false;
  std::string prefix = dir_path;
  if (prefix.back() != '/') prefix.push_back('/');
  const std::string lock_path = prefix + "batch.lock";

  DIR* proc = opendir("/proc");
  if (!proc) return false;

  const uid_t my_uid = geteuid();
  bool in_use = false;
  struct dirent* proc_ent = nullptr;
  while ((proc_ent = readdir(proc)) != nullptr && !in_use) {
    if (!IsDigitsOnly(proc_ent->d_name)) continue;

    std::string pid_dir = std::string("/proc/") + proc_ent->d_name;
    struct stat pst;
    if (stat(pid_dir.c_str(), &pst) != 0 || pst.st_uid != my_uid) continue;

    std::string fd_dir = pid_dir + "/fd";
    DIR* fds = opendir(fd_dir.c_str());
    if (!fds) continue;

    struct dirent* fd_ent = nullptr;
    while ((fd_ent = readdir(fds)) != nullptr) {
      if (fd_ent->d_name[0] == '.') continue;
      std::string link_path = fd_dir + "/" + fd_ent->d_name;
      char target[4096];
      const ssize_t len = readlink(link_path.c_str(), target, sizeof(target) - 1);
      if (len <= 0) continue;
      target[len] = '\0';
      std::string target_str(target, static_cast<size_t>(len));
      if (target_str == lock_path) continue;
      if (target_str.compare(0, prefix.size(), prefix) == 0) {
        in_use = true;
        break;
      }
    }
    closedir(fds);
  }
  closedir(proc);
  return in_use;
}

EngineBridgeLinux::EngineBridgeLinux()
    : handle_(nullptr),
      fn_buffer_free_(nullptr),
      fn_list_dir_(nullptr),
      fn_export_file_(nullptr),
      fn_op_register_(nullptr),
      fn_op_cancel_(nullptr),
      fn_op_unregister_(nullptr) {}

bool EngineBridgeLinux::Initialize(const std::string& library_path) {
  std::lock_guard<std::mutex> lock(init_mu_);
  if (IsAvailable()) return true;

  void* h = nullptr;
  if (!library_path.empty()) {
    h = dlopen(library_path.c_str(), RTLD_LAZY | RTLD_NOLOAD);
    if (!h) h = dlopen(library_path.c_str(), RTLD_LAZY);
  }
  if (!h) {
    h = dlopen("libvaultexplorer_engine.so", RTLD_LAZY | RTLD_NOLOAD);
  }
  if (!h) {
    h = dlopen("libvaultexplorer_engine.so", RTLD_LAZY);
  }
  if (!h) return false;

  handle_ = h;
  fn_buffer_free_ = reinterpret_cast<FnBufferFree>(dlsym(h, "ve_buffer_free"));
  fn_list_dir_ = reinterpret_cast<FnListDir>(dlsym(h, "ve_list_directory"));
  fn_export_file_ = reinterpret_cast<FnExportFile>(dlsym(h, "ve_export_file"));
  fn_op_register_ = reinterpret_cast<FnOpRegister>(dlsym(h, "ve_op_register"));
  fn_op_cancel_ = reinterpret_cast<FnOpCancel>(dlsym(h, "ve_op_cancel"));
  fn_op_unregister_ = reinterpret_cast<FnOpUnregister>(dlsym(h, "ve_op_unregister"));
  return IsAvailable();
}

bool EngineBridgeLinux::IsAvailable() const {
  return handle_ != nullptr &&
         fn_buffer_free_ != nullptr &&
         fn_list_dir_ != nullptr &&
         fn_export_file_ != nullptr &&
         fn_op_register_ != nullptr &&
         fn_op_cancel_ != nullptr &&
         fn_op_unregister_ != nullptr;
}

int32_t EngineBridgeLinux::ExportFile(int32_t vol_id,
                                      const char* vault_path,
                                      const char* host_dest_path,
                                      int32_t op_id) const {
  if (!fn_export_file_) return -1;
  return fn_export_file_(vol_id, vault_path, host_dest_path, op_id);
}

void EngineBridgeLinux::OpRegister(int32_t op_id, int32_t flavor) const {
  if (fn_op_register_) fn_op_register_(op_id, flavor);
}

void EngineBridgeLinux::OpCancel(int32_t op_id) const {
  if (fn_op_cancel_) fn_op_cancel_(op_id);
}

void EngineBridgeLinux::OpUnregister(int32_t op_id) const {
  if (fn_op_unregister_) fn_op_unregister_(op_id);
}

int32_t EngineBridgeLinux::ListDirectory(
    int32_t vol_id, const char* vault_path, std::vector<std::string>* entries_out) const {
  if (!fn_list_dir_ || !fn_buffer_free_ || !entries_out) return -1;
  entries_out->clear();
  VeBuffer buf{nullptr, 0};
  const int32_t rc = fn_list_dir_(vol_id, vault_path, &buf);
  if (rc == kVeOk && buf.data != nullptr && buf.len >= 4) {
    const uint32_t count = ReadU32LE(buf.data);
    size_t pos = 4;
    for (uint32_t i = 0; i < count && pos + 4 <= buf.len; ++i) {
      const uint32_t slen = ReadU32LE(buf.data + pos);
      pos += 4;
      if (pos + slen > buf.len) break;
      entries_out->emplace_back(reinterpret_cast<const char*>(buf.data + pos), slen);
      pos += slen;
    }
  }
  fn_buffer_free_(&buf);
  return rc;
}

bool EngineBridgeLinux::ExportSingle(TransferBatch* batch,
                                     const std::string& vault_path,
                                     const std::string& dest_path,
                                     int32_t op_id) const {
  if (batch->cancelled.load()) return false;
  const int32_t rc = ExportFile(batch->vol_id, vault_path.c_str(), dest_path.c_str(), op_id);
  if (rc != kVeOk) {
    unlink(dest_path.c_str());
    return false;
  }
  chmod(dest_path.c_str(), 0600);
  return true;
}

bool EngineBridgeLinux::ExportTree(TransferBatch* batch,
                                   const std::string& vault_path,
                                   const std::string& dest_dir,
                                   int32_t op_id) const {
  if (batch->cancelled.load()) return false;
  if (mkdir(dest_dir.c_str(), 0700) != 0 && errno != EEXIST) {
    return false;
  }

  std::vector<std::string> raw_entries;
  if (ListDirectory(batch->vol_id, vault_path.c_str(), &raw_entries) != kVeOk) {
    return false;
  }
  for (const std::string& wire : raw_entries) {
    if (batch->cancelled.load()) return false;
    ParsedDirRow row;
    if (!ParseWireEntry(wire, &row)) continue;
    const std::string child_vault = JoinPath(vault_path, row.name);
    const std::string child_dest = UniqueChildPath(dest_dir, SanitizePosixFileName(row.name));
    if (row.is_dir) {
      if (!ExportTree(batch, child_vault, child_dest, op_id)) return false;
    } else {
      if (!ExportSingle(batch, child_vault, child_dest, op_id)) return false;
      ApplyModifiedTime(child_dest, row.modified_secs);
    }
  }
  return true;
}

bool EngineBridgeLinux::StageBatch(
    TransferBatch* batch, std::vector<std::string>* paths_out) const {
  if (!batch || !paths_out) return false;
  paths_out->clear();

  if (batch->vol_id < 0) {
    for (const auto& item : batch->items) {
      if (!item.local_path.empty()) paths_out->push_back(item.local_path);
    }
    return !paths_out->empty();
  }

  if (!IsAvailable() || batch->staging_dir.empty() || batch->cancelled.load()) {
    return false;
  }

  if (mkdir(batch->staging_dir.c_str(), 0700) != 0 && errno != EEXIST) {
    return false;
  }
  chmod(batch->staging_dir.c_str(), 0700);

  static std::atomic<int32_t> next_op_id(900000);
  const int32_t op_id = next_op_id.fetch_add(1);
  {
    std::lock_guard<std::mutex> lock(batch->mu);
    batch->op_id = op_id;
  }
  OpRegister(op_id, kVeOpExport);

  bool all_ok = true;
  std::vector<std::string> created_roots;
  for (const auto& item : batch->items) {
    if (batch->cancelled.load()) {
      all_ok = false;
      break;
    }
    const std::string safe_name = SanitizePosixFileName(item.name);
    const std::string dest_path = UniqueChildPath(batch->staging_dir, safe_name);
    if (item.is_dir) {
      if (!ExportTree(batch, item.vault_path, dest_path, op_id)) {
        all_ok = false;
        break;
      }
      created_roots.push_back(dest_path);
      paths_out->push_back(dest_path);
    } else {
      if (!ExportSingle(batch, item.vault_path, dest_path, op_id)) {
        all_ok = false;
        break;
      }
      ApplyModifiedTime(dest_path, item.modified_secs);
      created_roots.push_back(dest_path);
      paths_out->push_back(dest_path);
    }
  }

  OpUnregister(op_id);
  {
    std::lock_guard<std::mutex> lock(batch->mu);
    batch->op_id = 0;
    if (all_ok) {
      batch->realized = true;
      batch->staged_root_paths = created_roots;
    }
  }
  return all_ok && !paths_out->empty();
}

}  // namespace ve_transfer
