#include "ve_engine_bridge_win.h"

#include <aclapi.h>
#include <sddl.h>

#include <algorithm>
#include <cctype>
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
  int64_t size_bytes = 0;
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
  out->size_bytes = std::strtoll(wire.substr(a + 1, b - a - 1).c_str(), nullptr, 10);
  out->modified_secs = std::strtoll(wire.substr(b + 1, c - b - 1).c_str(), nullptr, 10);
  out->name = wire.substr(c + 1);
  return !out->name.empty();
}

std::string JoinVaultPath(const std::string& parent, const std::string& child) {
  if (parent.empty()) return child;
  if (parent.back() == '/') return parent + child;
  return parent + "/" + child;
}

bool IsReservedDeviceName(const std::wstring& stem_upper) {
  static const wchar_t* const kReserved[] = {
      L"CON", L"PRN", L"AUX", L"NUL",
      L"COM1", L"COM2", L"COM3", L"COM4", L"COM5", L"COM6", L"COM7", L"COM8", L"COM9",
      L"LPT1", L"LPT2", L"LPT3", L"LPT4", L"LPT5", L"LPT6", L"LPT7", L"LPT8", L"LPT9",
  };
  for (const wchar_t* name : kReserved) {
    if (stem_upper == name) return true;
  }
  return false;
}

void ApplyNoIndexAttributes(const std::wstring& path) {
  const DWORD attrs = GetFileAttributesW(path.c_str());
  if (attrs != INVALID_FILE_ATTRIBUTES) {
    SetFileAttributesW(
        path.c_str(),
        attrs | FILE_ATTRIBUTE_NOT_CONTENT_INDEXED | FILE_ATTRIBUTE_TEMPORARY);
  }
}

void ApplyFileModifiedTime(const std::wstring& path, int64_t modified_secs) {
  if (modified_secs <= 0) return;
  const HANDLE h = CreateFileW(
      path.c_str(),
      FILE_WRITE_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      nullptr,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (h == INVALID_HANDLE_VALUE) return;
  const FILETIME ft = UnixSecondsToFileTime(modified_secs);
  SetFileTime(h, nullptr, nullptr, &ft);
  CloseHandle(h);
}

std::wstring UniqueChildPath(const std::wstring& dir, const std::wstring& base_name) {
  std::wstring candidate = dir + L"\\" + base_name;
  if (GetFileAttributesW(candidate.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return candidate;
  }
  const size_t dot = base_name.rfind(L'.');
  const bool has_ext = (dot != std::wstring::npos && dot > 0 && dot < base_name.size() - 1);
  const std::wstring stem = has_ext ? base_name.substr(0, dot) : base_name;
  const std::wstring ext = has_ext ? base_name.substr(dot) : std::wstring();
  for (int n = 1; n < 10000; ++n) {
    candidate = dir + L"\\" + stem + L" (" + std::to_wstring(n) + L")" + ext;
    if (GetFileAttributesW(candidate.c_str()) == INVALID_FILE_ATTRIBUTES) {
      return candidate;
    }
  }
  return dir + L"\\" + base_name;
}

bool CheckDirInUseRecursive(const std::wstring& dir_path) {
  const std::wstring pattern = dir_path + L"\\*";
  WIN32_FIND_DATAW ffd{};
  HANDLE find = FindFirstFileW(pattern.c_str(), &ffd);
  if (find == INVALID_HANDLE_VALUE) return false;

  bool in_use = false;
  do {
    const std::wstring name = ffd.cFileName;
    if (name == L"." || name == L".." || name == L"batch.lock") continue;
    const std::wstring full = dir_path + L"\\" + name;
    if ((ffd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
      if (CheckDirInUseRecursive(full)) {
        in_use = true;
        break;
      }
    } else {
      const HANDLE h = CreateFileW(
          full.c_str(),
          GENERIC_WRITE | DELETE,
          0,  // Exclusive check: fails if Explorer/Chrome/GIMP still holds a read handle.
          nullptr,
          OPEN_EXISTING,
          FILE_ATTRIBUTE_NORMAL,
          nullptr);
      if (h == INVALID_HANDLE_VALUE) {
        const DWORD err = GetLastError();
        if (err == ERROR_SHARING_VIOLATION || err == ERROR_ACCESS_DENIED) {
          in_use = true;
          break;
        }
      } else {
        CloseHandle(h);
      }
    }
  } while (FindNextFileW(find, &ffd));

  FindClose(find);
  return in_use;
}

}  // namespace

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int needed = MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (needed <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(needed), L'\0');
  MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), &out[0], needed);
  return out;
}

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  const int needed = WideCharToMultiByte(
      CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), nullptr, 0, nullptr, nullptr);
  if (needed <= 0) return std::string();
  std::string out(static_cast<size_t>(needed), '\0');
  WideCharToMultiByte(
      CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), &out[0], needed, nullptr, nullptr);
  return out;
}

std::wstring SanitizeWindowsFileName(const std::string& name_utf8) {
  std::wstring w = Utf8ToWide(name_utf8);
  for (wchar_t& ch : w) {
    if (ch < 32 || ch == L'<' || ch == L'>' || ch == L':' || ch == L'"' ||
        ch == L'/' || ch == L'\\' || ch == L'|' || ch == L'?' || ch == L'*') {
      ch = L'_';
    }
  }
  while (!w.empty() && (w.back() == L' ' || w.back() == L'.')) {
    w.pop_back();
  }
  if (w.empty() || w == L"." || w == L"..") {
    w = L"item";
  }
  const size_t dot = w.find(L'.');
  std::wstring stem = (dot == std::wstring::npos) ? w : w.substr(0, dot);
  std::transform(stem.begin(), stem.end(), stem.begin(), [](wchar_t c) {
    return static_cast<wchar_t>(towupper(c));
  });
  if (IsReservedDeviceName(stem)) {
    w = L"_" + w;
  }
  return w;
}

bool HardenStagingDirectoryWin(const std::wstring& dir_path) {
  if (dir_path.empty()) return false;
  ApplyNoIndexAttributes(dir_path);

  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }
  DWORD len = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &len);
  std::vector<uint8_t> buf(len);
  bool ok = false;
  if (len > 0 && GetTokenInformation(token, TokenUser, buf.data(), len, &len)) {
    auto* user = reinterpret_cast<TOKEN_USER*>(buf.data());
    LPWSTR sid_str = nullptr;
    if (ConvertSidToStringSidW(user->User.Sid, &sid_str)) {
      const std::wstring sddl = std::wstring(L"D:P(A;OICI;GA;;;") + sid_str + L")";
      LocalFree(sid_str);
      PSECURITY_DESCRIPTOR sd = nullptr;
      if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
              sddl.c_str(), SDDL_REVISION_1, &sd, nullptr)) {
        PACL dacl = nullptr;
        BOOL dacl_present = FALSE;
        BOOL dacl_defaulted = FALSE;
        if (GetSecurityDescriptorDacl(sd, &dacl_present, &dacl, &dacl_defaulted) &&
            dacl_present && dacl != nullptr) {
          const DWORD res = SetNamedSecurityInfoW(
              const_cast<LPWSTR>(dir_path.c_str()),
              SE_FILE_OBJECT,
              DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
              nullptr,
              nullptr,
              dacl,
              nullptr);
          ok = (res == ERROR_SUCCESS);
        }
        LocalFree(sd);
      }
    }
  }
  CloseHandle(token);
  return ok;
}

bool IsStagingBatchInUseWin(const std::wstring& dir_path) {
  if (dir_path.empty()) return false;
  return CheckDirInUseRecursive(dir_path);
}

FILETIME UnixSecondsToFileTime(int64_t epoch_seconds) {
  FILETIME ft{0, 0};
  if (epoch_seconds <= 0) return ft;
  const uint64_t win_ticks =
      (static_cast<uint64_t>(epoch_seconds) + 11644473600ULL) * 10000000ULL;
  ft.dwLowDateTime = static_cast<DWORD>(win_ticks & 0xFFFFFFFFULL);
  ft.dwHighDateTime = static_cast<DWORD>((win_ticks >> 32) & 0xFFFFFFFFULL);
  return ft;
}

bool EngineBridgeWin::Initialize(const std::string& library_path_utf8) {
  std::lock_guard<std::mutex> lock(init_mu_);
  if (IsAvailable()) return true;

  HMODULE mod = GetModuleHandleW(L"vaultexplorer_engine.dll");
  if (!mod && !library_path_utf8.empty()) {
    const std::wstring wide_path = Utf8ToWide(library_path_utf8);
    mod = LoadLibraryW(wide_path.c_str());
  }
  if (!mod) {
    mod = LoadLibraryW(L"vaultexplorer_engine.dll");
  }
  if (!mod) return false;

  module_ = mod;
  fn_buffer_free_ = reinterpret_cast<FnBufferFree>(GetProcAddress(mod, "ve_buffer_free"));
  fn_list_dir_ = reinterpret_cast<FnListDir>(GetProcAddress(mod, "ve_list_directory"));
  fn_get_file_size_ = reinterpret_cast<FnGetFileSize>(GetProcAddress(mod, "ve_get_file_size"));
  fn_export_file_ = reinterpret_cast<FnExportFile>(GetProcAddress(mod, "ve_export_file"));
  fn_open_stream_ = reinterpret_cast<FnOpenStream>(GetProcAddress(mod, "ve_open_stream"));
  fn_read_stream_ = reinterpret_cast<FnReadStream>(GetProcAddress(mod, "ve_read_stream"));
  fn_close_stream_ = reinterpret_cast<FnCloseStream>(GetProcAddress(mod, "ve_close_stream"));
  fn_op_register_ = reinterpret_cast<FnOpRegister>(GetProcAddress(mod, "ve_op_register"));
  fn_op_cancel_ = reinterpret_cast<FnOpCancel>(GetProcAddress(mod, "ve_op_cancel"));
  fn_op_unregister_ = reinterpret_cast<FnOpUnregister>(GetProcAddress(mod, "ve_op_unregister"));
  return IsAvailable();
}

bool EngineBridgeWin::IsAvailable() const {
  return module_ != nullptr &&
         fn_buffer_free_ != nullptr &&
         fn_list_dir_ != nullptr &&
         fn_get_file_size_ != nullptr &&
         fn_export_file_ != nullptr &&
         fn_open_stream_ != nullptr &&
         fn_read_stream_ != nullptr &&
         fn_close_stream_ != nullptr &&
         fn_op_register_ != nullptr &&
         fn_op_cancel_ != nullptr &&
         fn_op_unregister_ != nullptr;
}

int32_t EngineBridgeWin::ExportFile(
    int32_t vol_id, const char* vault_path, const char* host_dest_path, int32_t op_id) const {
  if (!fn_export_file_) return -1;
  return fn_export_file_(vol_id, vault_path, host_dest_path, op_id);
}

int64_t EngineBridgeWin::OpenStream(int32_t vol_id, const char* vault_path) const {
  if (!fn_open_stream_) return 0;
  return fn_open_stream_(vol_id, vault_path);
}

int32_t EngineBridgeWin::ReadStream(
    int32_t vol_id, int64_t handle, int64_t offset, uint8_t* dest, int32_t length) const {
  if (!fn_read_stream_) return -1;
  return fn_read_stream_(vol_id, handle, offset, dest, length);
}

void EngineBridgeWin::CloseStream(int32_t vol_id, int64_t handle) const {
  if (fn_close_stream_) fn_close_stream_(vol_id, handle);
}

void EngineBridgeWin::OpRegister(int32_t op_id, int32_t flavor) const {
  if (fn_op_register_) fn_op_register_(op_id, flavor);
}

void EngineBridgeWin::OpCancel(int32_t op_id) const {
  if (fn_op_cancel_) fn_op_cancel_(op_id);
}

void EngineBridgeWin::OpUnregister(int32_t op_id) const {
  if (fn_op_unregister_) fn_op_unregister_(op_id);
}

int32_t EngineBridgeWin::ListDirectory(
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

int64_t EngineBridgeWin::GetFileSize(int32_t vol_id, const char* vault_path) const {
  if (!fn_get_file_size_) return -1;
  return fn_get_file_size_(vol_id, vault_path);
}

bool EngineBridgeWin::ExportSingle(TransferBatch* batch,
                                   const std::string& vault_path,
                                   const std::wstring& dest_win_path,
                                   int32_t op_id) const {
  if (batch->cancelled.load()) return false;
  const std::string dest_utf8 = WideToUtf8(dest_win_path);
  const int32_t rc = ExportFile(batch->vol_id, vault_path.c_str(), dest_utf8.c_str(), op_id);
  if (rc != kVeOk) {
    DeleteFileW(dest_win_path.c_str());
    return false;
  }
  ApplyNoIndexAttributes(dest_win_path);
  return true;
}

bool EngineBridgeWin::ExportTree(TransferBatch* batch,
                                 const std::string& vault_path,
                                 const std::wstring& dest_win_dir,
                                 int32_t op_id) const {
  if (batch->cancelled.load()) return false;
  CreateDirectoryW(dest_win_dir.c_str(), nullptr);
  ApplyNoIndexAttributes(dest_win_dir);

  std::vector<std::string> raw_entries;
  if (ListDirectory(batch->vol_id, vault_path.c_str(), &raw_entries) != kVeOk) {
    return false;
  }

  for (const std::string& wire : raw_entries) {
    if (batch->cancelled.load()) return false;
    ParsedDirRow row;
    if (!ParseWireEntry(wire, &row)) continue;
    const std::string child_vault = JoinVaultPath(vault_path, row.name);
    const std::wstring safe_name = SanitizeWindowsFileName(row.name);
    const std::wstring child_dest = UniqueChildPath(dest_win_dir, safe_name);
    if (row.is_dir) {
      if (!ExportTree(batch, child_vault, child_dest, op_id)) return false;
    } else {
      if (!ExportSingle(batch, child_vault, child_dest, op_id)) return false;
      ApplyFileModifiedTime(child_dest, row.modified_secs);
    }
  }
  return true;
}

bool EngineBridgeWin::StageBatch(
    TransferBatch* batch, std::vector<std::string>* utf8_paths_out) const {
  if (!batch || !utf8_paths_out) return false;
  utf8_paths_out->clear();

  if (batch->vol_id < 0) {
    for (const auto& item : batch->items) {
      if (!item.local_path.empty()) utf8_paths_out->push_back(item.local_path);
    }
    return !utf8_paths_out->empty();
  }

  if (!IsAvailable() || batch->staging_dir.empty() || batch->cancelled.load()) {
    return false;
  }

  const std::wstring staging_root = Utf8ToWide(batch->staging_dir);
  CreateDirectoryW(staging_root.c_str(), nullptr);
  HardenStagingDirectoryWin(staging_root);

  static std::atomic<int32_t> next_op_id{900000};
  const int32_t op_id = next_op_id.fetch_add(1);
  {
    std::lock_guard<std::mutex> lock(batch->mu);
    batch->op_id = op_id;
  }
  OpRegister(op_id, kVeOpExport);

  bool all_ok = true;
  std::vector<std::wstring> created_roots;
  for (const auto& item : batch->items) {
    if (batch->cancelled.load()) {
      all_ok = false;
      break;
    }
    const std::wstring safe_name = SanitizeWindowsFileName(item.name);
    const std::wstring dest_path = UniqueChildPath(staging_root, safe_name);
    if (item.is_dir) {
      if (!ExportTree(batch, item.vault_path, dest_path, op_id)) {
        all_ok = false;
        break;
      }
      created_roots.push_back(dest_path);
      utf8_paths_out->push_back(WideToUtf8(dest_path));
    } else {
      if (!ExportSingle(batch, item.vault_path, dest_path, op_id)) {
        all_ok = false;
        break;
      }
      ApplyFileModifiedTime(dest_path, item.modified_secs);
      created_roots.push_back(dest_path);
      utf8_paths_out->push_back(WideToUtf8(dest_path));
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
  return all_ok && !utf8_paths_out->empty();
}

void EngineBridgeWin::CollectVirtualRecursive(
    int32_t vol_id,
    const std::string& vault_path,
    const std::wstring& rel_win_path,
    std::vector<VirtualFileDescriptorEntry>* out) const {
  std::vector<std::string> raw_entries;
  if (ListDirectory(vol_id, vault_path.c_str(), &raw_entries) != kVeOk) return;
  for (const std::string& wire : raw_entries) {
    ParsedDirRow row;
    if (!ParseWireEntry(wire, &row)) continue;
    const std::string child_vault = JoinVaultPath(vault_path, row.name);
    const std::wstring child_rel = rel_win_path + L"\\" + SanitizeWindowsFileName(row.name);
    VirtualFileDescriptorEntry entry;
    entry.vault_path = child_vault;
    entry.rel_win_path = child_rel;
    entry.is_dir = row.is_dir;
    entry.size_bytes = row.is_dir ? 0 : row.size_bytes;
    entry.modified_secs = row.modified_secs;
    out->push_back(entry);
    if (row.is_dir) {
      CollectVirtualRecursive(vol_id, child_vault, child_rel, out);
    }
  }
}

bool EngineBridgeWin::ExpandVirtualEntries(
    int32_t vol_id,
    const std::vector<TransferItemSpec>& items,
    std::vector<VirtualFileDescriptorEntry>* out) const {
  if (!out || vol_id < 0 || !IsAvailable()) return false;
  out->clear();
  for (const auto& item : items) {
    const std::wstring rel = SanitizeWindowsFileName(item.name);
    VirtualFileDescriptorEntry entry;
    entry.vault_path = item.vault_path;
    entry.rel_win_path = rel;
    entry.is_dir = item.is_dir;
    entry.size_bytes = item.is_dir ? 0 : item.size_bytes;
    entry.modified_secs = item.modified_secs;
    out->push_back(entry);
    if (item.is_dir) {
      CollectVirtualRecursive(vol_id, item.vault_path, rel, out);
    }
  }
  return !out->empty();
}

}  // namespace ve_transfer
