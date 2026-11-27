#include "include/ve_desktop_transfer/ve_desktop_transfer_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <ole2.h>
#include <windows.h>

#include <cstdint>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "ve_clipboard_win.h"
#include "ve_data_object.h"
#include "ve_drop_target.h"
#include "ve_engine_bridge_win.h"
#include "ve_transfer_callbacks_win.h"

namespace {

constexpr UINT kWmPluginNotify = WM_APP + 0x317;
constexpr const wchar_t* kMsgWindowClass = L"VaultExplorerTransferMsgWin";

const flutter::EncodableValue* MapLookup(
    const flutter::EncodableMap& map, const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::string MapGetString(const flutter::EncodableMap& map, const char* key) {
  const auto* val = MapLookup(map, key);
  if (val == nullptr) return std::string();
  if (const auto* s = std::get_if<std::string>(val)) return *s;
  return std::string();
}

bool MapGetBool(const flutter::EncodableMap& map, const char* key, bool fallback = false) {
  const auto* val = MapLookup(map, key);
  if (val == nullptr) return fallback;
  if (const auto* b = std::get_if<bool>(val)) return *b;
  return fallback;
}

int64_t MapGetInt64(const flutter::EncodableMap& map, const char* key, int64_t fallback = 0) {
  const auto* val = MapLookup(map, key);
  if (val == nullptr) return fallback;
  if (const auto* i32 = std::get_if<int32_t>(val)) return *i32;
  if (const auto* i64 = std::get_if<int64_t>(val)) return *i64;
  return fallback;
}

std::shared_ptr<ve_transfer::TransferBatch> ParseManifest(
    const flutter::EncodableMap& m) {
  auto batch = std::make_shared<ve_transfer::TransferBatch>();
  batch->batch_id = MapGetString(m, "batchId");
  batch->vol_id = static_cast<int32_t>(MapGetInt64(m, "volId", -1));
  batch->staging_dir = MapGetString(m, "stagingDir");
  batch->prefer_virtual_stream = MapGetBool(m, "preferVirtualStream", false);
  batch->is_sensitive = MapGetBool(m, "isSensitive", true);

  const auto* items_val = MapLookup(m, "items");
  if (items_val != nullptr) {
    if (const auto* list = std::get_if<flutter::EncodableList>(items_val)) {
      for (const auto& raw_item : *list) {
        const auto* item_map = std::get_if<flutter::EncodableMap>(&raw_item);
        if (!item_map) continue;
        ve_transfer::TransferItemSpec spec;
        spec.vault_path = MapGetString(*item_map, "vaultPath");
        spec.name = MapGetString(*item_map, "name");
        spec.is_dir = MapGetBool(*item_map, "isDir", false);
        spec.size_bytes = MapGetInt64(*item_map, "sizeBytes", 0);
        spec.modified_secs = MapGetInt64(*item_map, "modifiedSecs", 0);
        spec.local_path = MapGetString(*item_map, "localPath");
        batch->items.push_back(std::move(spec));
      }
    }
  }
  return batch;
}

class VeDesktopTransferPlugin final : public flutter::Plugin,
                                      public ve_transfer::TransferCallbacksWin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit VeDesktopTransferPlugin(flutter::PluginRegistrarWindows* registrar);
  ~VeDesktopTransferPlugin() override;

  // TransferCallbacksWin (thread-safe; marshals back to platform thread)
  void PostDropEvent(int64_t view_id,
                     const char* method_name,
                     double x,
                     double y,
                     std::vector<std::string> paths) override;
  void PostBatchRealized(std::string batch_id, std::vector<std::string> paths) override;
  void PostBatchTransferFinished(std::string batch_id,
                                 bool success,
                                 bool immediate_if_unused) override;
  void PostClipboardOwnershipLost(std::string batch_id) override;

 private:
  void CreateMessageWindow();
  void DestroyMessageWindow();
  static LRESULT CALLBACK MsgWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
  void EnqueueUiTask(std::function<void()> task);
  void DrainUiTasks();

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  HWND ResolveViewHwnd(int64_t view_id) const;
  bool RegisterView(int64_t view_id);
  void UnregisterView(int64_t view_id);
  std::string RunDrag(int64_t view_id, const std::shared_ptr<ve_transfer::TransferBatch>& batch);
  void CancelBatch(const std::string& batch_id);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  DWORD ui_thread_id_ = 0;
  bool ole_initialized_ = false;
  HWND msg_hwnd_ = nullptr;

  ve_transfer::EngineBridgeWin engine_;
  std::unique_ptr<ve_transfer::ClipboardWin> clipboard_;

  struct ViewEntry {
    HWND hwnd = nullptr;
    ve_transfer::VeDropTarget* drop_target = nullptr;
  };
  std::map<int64_t, ViewEntry> views_;

  std::mutex active_batches_mu_;
  std::map<std::string, std::weak_ptr<ve_transfer::TransferBatch>> active_batches_;

  std::mutex ui_tasks_mu_;
  std::deque<std::function<void()>> ui_tasks_;
};

// static
void VeDesktopTransferPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<VeDesktopTransferPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

VeDesktopTransferPlugin::VeDesktopTransferPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar), ui_thread_id_(GetCurrentThreadId()) {
  const HRESULT hr = OleInitialize(nullptr);
  ole_initialized_ = (hr == S_OK || hr == S_FALSE);

  clipboard_ = std::make_unique<ve_transfer::ClipboardWin>(&engine_, this, ui_thread_id_);
  CreateMessageWindow();

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar_->messenger(),
      "vaultexplorer/desktop_transfer",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

VeDesktopTransferPlugin::~VeDesktopTransferPlugin() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
  }
  for (auto& kv : views_) {
    if (kv.second.drop_target) {
      kv.second.drop_target->Revoke();
      kv.second.drop_target->Release();
    }
  }
  views_.clear();

  if (clipboard_) {
    clipboard_->ClearOwnedOnShutdown();
    clipboard_.reset();
  }
  DestroyMessageWindow();
  if (ole_initialized_) {
    OleUninitialize();
    ole_initialized_ = false;
  }
}

void VeDesktopTransferPlugin::CreateMessageWindow() {
  const HINSTANCE hinst = GetModuleHandleW(nullptr);
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = MsgWndProc;
  wc.hInstance = hinst;
  wc.lpszClassName = kMsgWindowClass;
  RegisterClassExW(&wc);

  msg_hwnd_ = CreateWindowExW(
      0, kMsgWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, hinst, this);
  if (msg_hwnd_) {
    AddClipboardFormatListener(msg_hwnd_);
  }
}

void VeDesktopTransferPlugin::DestroyMessageWindow() {
  if (msg_hwnd_) {
    RemoveClipboardFormatListener(msg_hwnd_);
    DestroyWindow(msg_hwnd_);
    msg_hwnd_ = nullptr;
  }
}

// static
LRESULT CALLBACK VeDesktopTransferPlugin::MsgWndProc(
    HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lp);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    return TRUE;
  }
  auto* self = reinterpret_cast<VeDesktopTransferPlugin*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self) {
    if (msg == kWmPluginNotify) {
      self->DrainUiTasks();
      return 0;
    }
    if (msg == WM_CLIPBOARDUPDATE && self->clipboard_) {
      self->clipboard_->OnClipboardUpdated();
      return 0;
    }
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}

void VeDesktopTransferPlugin::EnqueueUiTask(std::function<void()> task) {
  {
    std::lock_guard<std::mutex> lock(ui_tasks_mu_);
    ui_tasks_.push_back(std::move(task));
  }
  if (msg_hwnd_) {
    PostMessageW(msg_hwnd_, kWmPluginNotify, 0, 0);
  }
}

void VeDesktopTransferPlugin::DrainUiTasks() {
  std::deque<std::function<void()>> batch;
  {
    std::lock_guard<std::mutex> lock(ui_tasks_mu_);
    batch.swap(ui_tasks_);
  }
  for (auto& fn : batch) {
    if (fn) fn();
  }
}

void VeDesktopTransferPlugin::PostDropEvent(int64_t view_id,
                                            const char* method_name,
                                            double x,
                                            double y,
                                            std::vector<std::string> paths) {
  std::string method(method_name ? method_name : "");
  auto emit = [this, view_id, method = std::move(method), x, y, paths = std::move(paths)]() {
    if (!channel_) return;
    flutter::EncodableList list;
    list.reserve(paths.size());
    for (const auto& p : paths) {
      list.push_back(flutter::EncodableValue(p));
    }
    flutter::EncodableMap args{
        {flutter::EncodableValue("viewId"), flutter::EncodableValue(view_id)},
        {flutter::EncodableValue("x"), flutter::EncodableValue(x)},
        {flutter::EncodableValue("y"), flutter::EncodableValue(y)},
        {flutter::EncodableValue("paths"), flutter::EncodableValue(std::move(list))},
    };
    channel_->InvokeMethod(method, std::make_unique<flutter::EncodableValue>(std::move(args)));
  };
  if (GetCurrentThreadId() == ui_thread_id_) {
    emit();
  } else {
    EnqueueUiTask(std::move(emit));
  }
}

void VeDesktopTransferPlugin::PostBatchRealized(
    std::string batch_id, std::vector<std::string> paths) {
  EnqueueUiTask([this, batch_id = std::move(batch_id), paths = std::move(paths)]() {
    if (!channel_) return;
    flutter::EncodableList list;
    list.reserve(paths.size());
    for (const auto& p : paths) {
      list.push_back(flutter::EncodableValue(p));
    }
    flutter::EncodableMap args{
        {flutter::EncodableValue("batchId"), flutter::EncodableValue(batch_id)},
        {flutter::EncodableValue("paths"), flutter::EncodableValue(std::move(list))},
    };
    channel_->InvokeMethod(
        "onBatchRealized", std::make_unique<flutter::EncodableValue>(std::move(args)));
  });
}

void VeDesktopTransferPlugin::PostBatchTransferFinished(
    std::string batch_id, bool success, bool immediate_if_unused) {
  EnqueueUiTask([this, batch_id = std::move(batch_id), success, immediate_if_unused]() {
    if (!channel_) return;
    flutter::EncodableMap args{
        {flutter::EncodableValue("batchId"), flutter::EncodableValue(batch_id)},
        {flutter::EncodableValue("success"), flutter::EncodableValue(success)},
        {flutter::EncodableValue("immediateIfUnused"), flutter::EncodableValue(immediate_if_unused)},
    };
    channel_->InvokeMethod(
        "onBatchTransferFinished",
        std::make_unique<flutter::EncodableValue>(std::move(args)));
  });
}

void VeDesktopTransferPlugin::PostClipboardOwnershipLost(std::string batch_id) {
  auto emit = [this, batch_id = std::move(batch_id)]() {
    if (!channel_) return;
    flutter::EncodableMap args{
        {flutter::EncodableValue("batchId"), flutter::EncodableValue(batch_id)},
    };
    channel_->InvokeMethod(
        "onClipboardOwnershipLost",
        std::make_unique<flutter::EncodableValue>(std::move(args)));
  };
  if (GetCurrentThreadId() == ui_thread_id_) {
    emit();
  } else {
    EnqueueUiTask(std::move(emit));
  }
}

HWND VeDesktopTransferPlugin::ResolveViewHwnd(int64_t view_id) const {
  if (!registrar_) return nullptr;
  const std::shared_ptr<flutter::FlutterView> view = registrar_->GetViewById(view_id);
  if (!view) return nullptr;
  return view->GetNativeWindow();
}

bool VeDesktopTransferPlugin::RegisterView(int64_t view_id) {
  if (views_.find(view_id) != views_.end()) return true;
  const HWND hwnd = ResolveViewHwnd(view_id);
  if (!hwnd || !IsWindow(hwnd)) return false;

  auto* target = new (std::nothrow) ve_transfer::VeDropTarget(hwnd, view_id, this);
  if (!target) return false;
  if (!target->Register()) {
    target->Release();
    return false;
  }
  views_[view_id] = ViewEntry{hwnd, target};
  return true;
}

void VeDesktopTransferPlugin::UnregisterView(int64_t view_id) {
  const auto it = views_.find(view_id);
  if (it == views_.end()) return;
  if (it->second.drop_target) {
    it->second.drop_target->Revoke();
    it->second.drop_target->Release();
  }
  views_.erase(it);
}

std::string VeDesktopTransferPlugin::RunDrag(
    int64_t, const std::shared_ptr<ve_transfer::TransferBatch>& batch) {
  if (!batch || batch->items.empty()) return "error";

  {
    std::lock_guard<std::mutex> lock(active_batches_mu_);
    active_batches_[batch->batch_id] = batch;
  }

  auto* data_obj = new (std::nothrow)
      ve_transfer::VeDataObject(batch, &engine_, this, ui_thread_id_);
  auto* drop_src = new (std::nothrow) ve_transfer::VeDropSource();
  if (!data_obj || !drop_src) {
    if (data_obj) data_obj->Release();
    if (drop_src) drop_src->Release();
    return "error";
  }

  // Release Flutter's mouse capture before entering the OLE modal drag loop.
  // The FLUTTERVIEW sets SetCapture on WM_LBUTTONDOWN; leaving it active while
  // DoDragDrop runs its own message loop causes the cursor to stay captured,
  // prevents subsequent WM_LBUTTONDOWN from reaching the view, and breaks
  // drop-target registration for following drags.
  ReleaseCapture();

  DWORD effect = DROPEFFECT_NONE;
  // Our own windows are drop targets for this drag too; they must know it is
  // ours (see VeDropTarget::SetOwnOutboundDataObject).
  ve_transfer::VeDropTarget::SetOwnOutboundDataObject(data_obj);
  const HRESULT hr = DoDragDrop(data_obj, drop_src, DROPEFFECT_COPY, &effect);
  ve_transfer::VeDropTarget::SetOwnOutboundDataObject(nullptr);
  const bool async_started = data_obj->did_async_operation();
  data_obj->Release();
  drop_src->Release();

  if (hr == DRAGDROP_S_DROP && effect != DROPEFFECT_NONE) {
    if (!async_started) {
      PostBatchTransferFinished(batch->batch_id, true, false);
    }
    return "copied";
  }
  if (!async_started) {
    PostBatchTransferFinished(batch->batch_id, false, true);
  }
  return "cancelled";
}

void VeDesktopTransferPlugin::CancelBatch(const std::string& batch_id) {
  std::shared_ptr<ve_transfer::TransferBatch> batch;
  {
    std::lock_guard<std::mutex> lock(active_batches_mu_);
    const auto it = active_batches_.find(batch_id);
    if (it != active_batches_.end()) {
      batch = it->second.lock();
    }
  }
  if (!batch) return;
  batch->cancelled.store(true);
  int32_t op_id = 0;
  {
    std::lock_guard<std::mutex> lock(batch->mu);
    op_id = batch->op_id;
  }
  if (op_id > 0) {
    engine_.OpCancel(op_id);
  }
}

void VeDesktopTransferPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  const auto& method = call.method_name();

  if (method == "initialize") {
    const std::string lib_path = args ? MapGetString(*args, "engineLibraryPath") : std::string();
    engine_.Initialize(lib_path);
    flutter::EncodableMap reply{
        {flutter::EncodableValue("supported"), flutter::EncodableValue(true)},
        {flutter::EncodableValue("backend"), flutter::EncodableValue("win32")},
    };
    result->Success(flutter::EncodableValue(std::move(reply)));
    return;
  }

  if (method == "registerView") {
    const int64_t view_id = args ? MapGetInt64(*args, "viewId", -1) : -1;
    result->Success(flutter::EncodableValue(view_id >= 0 && RegisterView(view_id)));
    return;
  }

  if (method == "unregisterView") {
    if (args) UnregisterView(MapGetInt64(*args, "viewId", -1));
    result->Success();
    return;
  }

  if (method == "startDrag") {
    if (!args) {
      result->Success(flutter::EncodableValue("error"));
      return;
    }
    const int64_t view_id = MapGetInt64(*args, "viewId", 0);
    const auto* manifest_val = MapLookup(*args, "manifest");
    const auto* manifest_map = manifest_val
        ? std::get_if<flutter::EncodableMap>(manifest_val)
        : nullptr;
    if (!manifest_map) {
      result->Success(flutter::EncodableValue("error"));
      return;
    }
    engine_.Initialize(std::string());
    const auto batch = ParseManifest(*manifest_map);
    result->Success(flutter::EncodableValue(RunDrag(view_id, batch)));
    return;
  }

  if (method == "setClipboardFiles") {
    const auto* manifest_val = args ? MapLookup(*args, "manifest") : nullptr;
    const auto* manifest_map = manifest_val
        ? std::get_if<flutter::EncodableMap>(manifest_val)
        : nullptr;
    if (!manifest_map || !clipboard_) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    engine_.Initialize(std::string());
    const auto batch = ParseManifest(*manifest_map);
    {
      std::lock_guard<std::mutex> lock(active_batches_mu_);
      active_batches_[batch->batch_id] = batch;
    }
    result->Success(flutter::EncodableValue(clipboard_->SetFiles(batch)));
    return;
  }

  if (method == "setClipboardImage") {
    if (!args || !clipboard_) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    const auto* png_val = MapLookup(*args, "pngBytes");
    const auto* rgba_val = MapLookup(*args, "rgbaBytes");
    const auto* png = png_val ? std::get_if<std::vector<uint8_t>>(png_val) : nullptr;
    const auto* rgba = rgba_val ? std::get_if<std::vector<uint8_t>>(rgba_val) : nullptr;
    const int32_t width = static_cast<int32_t>(MapGetInt64(*args, "width", 0));
    const int32_t height = static_cast<int32_t>(MapGetInt64(*args, "height", 0));
    const bool sensitive = MapGetBool(*args, "sensitive", true);
    if (!png || png->empty()) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    static const std::vector<uint8_t> kEmptyRgba;
    result->Success(flutter::EncodableValue(
        clipboard_->SetImage(*png, rgba ? *rgba : kEmptyRgba, width, height, sensitive)));
    return;
  }

  if (method == "setSensitiveClipboardText") {
    if (!args || !clipboard_) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    const std::string text = MapGetString(*args, "text");
    result->Success(flutter::EncodableValue(clipboard_->SetSensitiveText(text)));
    return;
  }

  if (method == "clearSensitiveClipboardText") {
    if (!clipboard_) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    const auto* exp_val = args ? MapLookup(*args, "expectedText") : nullptr;
    const auto* exp_str = exp_val ? std::get_if<std::string>(exp_val) : nullptr;
    result->Success(flutter::EncodableValue(clipboard_->ClearSensitiveText(exp_str)));
    return;
  }

  if (method == "clearClipboardIfBatch") {
    if (!clipboard_) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    const auto* bid_val = args ? MapLookup(*args, "batchId") : nullptr;
    const auto* bid = bid_val ? std::get_if<std::string>(bid_val) : nullptr;
    const auto* vid_val = args ? MapLookup(*args, "volId") : nullptr;
    int32_t vol_id = 0;
    const int32_t* vol_ptr = nullptr;
    if (vid_val) {
      if (const auto* i32 = std::get_if<int32_t>(vid_val)) {
        vol_id = *i32;
        vol_ptr = &vol_id;
      } else if (const auto* i64 = std::get_if<int64_t>(vid_val)) {
        vol_id = static_cast<int32_t>(*i64);
        vol_ptr = &vol_id;
      }
    }
    const auto* clear_img_val = args ? MapLookup(*args, "clearImage") : nullptr;
    const bool clear_image =
        clear_img_val && std::get_if<bool>(clear_img_val) && *std::get_if<bool>(clear_img_val);
    result->Success(flutter::EncodableValue(
        clipboard_->ClearIfBatch(bid, vol_ptr, clear_image)));
    return;
  }

  if (method == "inspectClipboard") {
    if (!clipboard_) {
      result->Success(flutter::EncodableValue());
      return;
    }
    const auto info = clipboard_->Inspect(msg_hwnd_);
    flutter::EncodableList paths;
    paths.reserve(info.file_paths.size());
    for (const auto& p : info.file_paths) {
      paths.push_back(flutter::EncodableValue(p));
    }
    flutter::EncodableMap reply{
        {flutter::EncodableValue("hasFiles"), flutter::EncodableValue(info.has_files)},
        {flutter::EncodableValue("isOwnFiles"), flutter::EncodableValue(info.is_own_files)},
        {flutter::EncodableValue("ownBatchId"),
         info.own_batch_id.empty()
             ? flutter::EncodableValue()
             : flutter::EncodableValue(info.own_batch_id)},
        {flutter::EncodableValue("filePaths"), flutter::EncodableValue(std::move(paths))},
        {flutter::EncodableValue("hasImage"), flutter::EncodableValue(info.has_image)},
        {flutter::EncodableValue("isMove"), flutter::EncodableValue(false)},
    };
    result->Success(flutter::EncodableValue(std::move(reply)));
    return;
  }

  if (method == "readClipboardImageData") {
    if (!clipboard_) {
      result->Success(flutter::EncodableValue());
      return;
    }
    const auto img = clipboard_->ReadImage(msg_hwnd_);
    if (!img.ok || img.bytes.empty()) {
      result->Success(flutter::EncodableValue());
      return;
    }
    flutter::EncodableMap reply{
        {flutter::EncodableValue("format"), flutter::EncodableValue(img.format)},
        {flutter::EncodableValue("bytes"), flutter::EncodableValue(img.bytes)},
    };
    result->Success(flutter::EncodableValue(std::move(reply)));
    return;
  }

  if (method == "hardenStagingDir") {
    const std::string path = args ? MapGetString(*args, "path") : std::string();
    result->Success(flutter::EncodableValue(
        ve_transfer::HardenStagingDirectoryWin(ve_transfer::Utf8ToWide(path))));
    return;
  }

  if (method == "isStagingBatchInUse") {
    const std::string path = args ? MapGetString(*args, "path") : std::string();
    result->Success(flutter::EncodableValue(
        ve_transfer::IsStagingBatchInUseWin(ve_transfer::Utf8ToWide(path))));
    return;
  }

  if (method == "cancelBatch") {
    if (args) CancelBatch(MapGetString(*args, "batchId"));
    result->Success();
    return;
  }

  result->NotImplemented();
}

}  // namespace

void VeDesktopTransferPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  VeDesktopTransferPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
