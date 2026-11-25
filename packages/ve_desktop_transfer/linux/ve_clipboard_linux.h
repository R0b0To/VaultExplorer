#ifndef VE_DESKTOP_TRANSFER_CLIPBOARD_LINUX_H_
#define VE_DESKTOP_TRANSFER_CLIPBOARD_LINUX_H_

#include <gtk/gtk.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "ve_engine_bridge_linux.h"
#include "ve_transfer_callbacks_linux.h"

namespace ve_transfer {

struct ClipboardInspectLinux {
  bool has_files = false;
  bool is_own_files = false;
  std::string own_batch_id;
  std::vector<std::string> file_paths;
  bool has_image = false;
  bool is_move = false;
};

class ClipboardLinux {
 public:
  ClipboardLinux(const EngineBridgeLinux* bridge, TransferCallbacksLinux* callbacks);
  ~ClipboardLinux();

  bool SetFiles(std::shared_ptr<TransferBatch> batch);
  bool SetImage(const std::vector<uint8_t>& png_bytes, bool sensitive);
  bool SetSensitiveText(const std::string& text);
  bool ClearSensitiveText(const std::string* expected_text);
  bool ClearIfBatch(const std::string* batch_id,
                    const int32_t* vol_id,
                    bool clear_image = false);
  void ClearOwnedOnShutdown();

  ClipboardInspectLinux Inspect() const;
  std::vector<uint8_t> ReadImagePng() const;

 private:
  struct FilesOwner {
    ClipboardLinux* owner = nullptr;
    std::shared_ptr<TransferBatch> batch;
    bool realized_notified = false;
  };

  struct ImageOwner {
    ClipboardLinux* owner = nullptr;
    std::vector<uint8_t> png_bytes;
    bool sensitive = true;
  };

  struct TextOwner {
    ClipboardLinux* owner = nullptr;
    std::string text;
  };

  static void GetFilesCb(GtkClipboard* clipboard,
                         GtkSelectionData* sdata,
                         guint info,
                         gpointer user_data);
  static void ClearFilesCb(GtkClipboard* clipboard, gpointer user_data);

  static void GetImageCb(GtkClipboard* clipboard,
                         GtkSelectionData* sdata,
                         guint info,
                         gpointer user_data);
  static void ClearImageCb(GtkClipboard* clipboard, gpointer user_data);

  static void GetTextCb(GtkClipboard* clipboard,
                        GtkSelectionData* sdata,
                        guint info,
                        gpointer user_data);
  static void ClearTextCb(GtkClipboard* clipboard, gpointer user_data);

  static void OnOwnerChange(GtkClipboard* clipboard, GdkEvent* event, gpointer user_data);

  const EngineBridgeLinux* bridge_;
  TransferCallbacksLinux* callbacks_;
  GtkClipboard* clipboard_ = nullptr;
  gulong owner_change_sig_ = 0;

  FilesOwner* active_files_ = nullptr;
  ImageOwner* active_image_ = nullptr;
  TextOwner* active_text_ = nullptr;
  bool suppress_owner_change_ = false;
};

}  // namespace ve_transfer

#endif  // VE_DESKTOP_TRANSFER_CLIPBOARD_LINUX_H_
