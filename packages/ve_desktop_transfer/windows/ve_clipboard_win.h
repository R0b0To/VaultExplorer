#ifndef VE_DESKTOP_TRANSFER_CLIPBOARD_WIN_H_
#define VE_DESKTOP_TRANSFER_CLIPBOARD_WIN_H_

#include <objidl.h>
#include <windows.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "ve_data_object.h"
#include "ve_engine_bridge_win.h"
#include "ve_transfer_callbacks_win.h"

namespace ve_transfer {

struct ClipboardInspectWin {
  bool has_files = false;
  bool is_own_files = false;
  std::string own_batch_id;
  std::vector<std::string> file_paths;
  bool has_image = false;
};

struct ClipboardImageReadWin {
  bool ok = false;
  std::string format;  // "png" or "bmp"
  std::vector<uint8_t> bytes;
};

class ClipboardWin {
 public:
  ClipboardWin(const EngineBridgeWin* bridge,
               TransferCallbacksWin* callbacks,
               DWORD ui_thread_id);
  ~ClipboardWin();

  bool SetFiles(std::shared_ptr<TransferBatch> batch);
  bool SetImage(const std::vector<uint8_t>& png_bytes,
                const std::vector<uint8_t>& rgba_bytes,
                int32_t width,
                int32_t height,
                bool sensitive);
  bool SetSensitiveText(const std::string& utf8_text);
  bool ClearSensitiveText(const std::string* expected_utf8);
  bool ClearIfBatch(const std::string* batch_id,
                    const int32_t* vol_id,
                    bool clear_image = false);
  void ClearOwnedOnShutdown();

  // Called from WM_CLIPBOARDUPDATE on the platform thread.
  void OnClipboardUpdated();

  ClipboardInspectWin Inspect(HWND owner_hwnd) const;
  ClipboardImageReadWin ReadImage(HWND owner_hwnd) const;

 private:
  const EngineBridgeWin* bridge_;
  TransferCallbacksWin* callbacks_;
  DWORD ui_thread_id_;

  VeDataObject* active_files_obj_ = nullptr;
  IDataObject* active_image_obj_ = nullptr;
  IDataObject* active_text_obj_ = nullptr;
  std::wstring active_sensitive_text_;
  DWORD active_sensitive_seq_ = 0;

  void ReleaseActiveFiles();
  void ReleaseActiveImage();
  void ReleaseActiveText();
};

}  // namespace ve_transfer

#endif  // VE_DESKTOP_TRANSFER_CLIPBOARD_WIN_H_
