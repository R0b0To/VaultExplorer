#include "include/ve_desktop_transfer/ve_desktop_transfer_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gdk/gdk.h>
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <gtk/gtk.h>

#include <algorithm>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "ve_clipboard_linux.h"
#include "ve_dnd_linux.h"
#include "ve_engine_bridge_linux.h"
#include "ve_transfer_callbacks_linux.h"

namespace {

std::string FlLookupString(FlValue* map, const char* key) {
  FlValue* v = fl_value_lookup_string(map, key);
  if (v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_STRING) {
    return fl_value_get_string(v);
  }
  return std::string();
}

bool FlLookupBool(FlValue* map, const char* key, bool fallback = false) {
  FlValue* v = fl_value_lookup_string(map, key);
  if (v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL) {
    return fl_value_get_bool(v);
  }
  return fallback;
}

int64_t FlLookupInt(FlValue* map, const char* key, int64_t fallback = 0) {
  FlValue* v = fl_value_lookup_string(map, key);
  if (v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_INT) {
    return fl_value_get_int(v);
  }
  return fallback;
}

std::shared_ptr<ve_transfer::TransferBatch> ParseManifest(FlValue* map) {
  auto batch = std::make_shared<ve_transfer::TransferBatch>();
  batch->batch_id = FlLookupString(map, "batchId");
  batch->vol_id = static_cast<int32_t>(FlLookupInt(map, "volId", -1));
  batch->staging_dir = FlLookupString(map, "stagingDir");
  batch->is_sensitive = FlLookupBool(map, "isSensitive", true);

  FlValue* items = fl_value_lookup_string(map, "items");
  if (items != nullptr && fl_value_get_type(items) == FL_VALUE_TYPE_LIST) {
    const size_t n = fl_value_get_length(items);
    for (size_t i = 0; i < n; ++i) {
      FlValue* row = fl_value_get_list_value(items, i);
      if (!row || fl_value_get_type(row) != FL_VALUE_TYPE_MAP) continue;
      ve_transfer::TransferItemSpec spec;
      spec.vault_path = FlLookupString(row, "vaultPath");
      spec.name = FlLookupString(row, "name");
      spec.is_dir = FlLookupBool(row, "isDir", false);
      spec.size_bytes = FlLookupInt(row, "sizeBytes", 0);
      spec.modified_secs = FlLookupInt(row, "modifiedSecs", 0);
      spec.local_path = FlLookupString(row, "localPath");
      batch->items.push_back(std::move(spec));
    }
  }
  return batch;
}

void FindFlViewsInWidget(GtkWidget* widget, std::vector<FlView*>* out) {
  if (!widget || !out) return;
  if (FL_IS_VIEW(widget)) {
    out->push_back(FL_VIEW(widget));
    return;
  }
  if (GTK_IS_CONTAINER(widget)) {
    GList* children = gtk_container_get_children(GTK_CONTAINER(widget));
    for (GList* l = children; l != nullptr; l = l->next) {
      FindFlViewsInWidget(GTK_WIDGET(l->data), out);
    }
    g_list_free(children);
  }
}

class LinuxCallbacks final : public ve_transfer::TransferCallbacksLinux {
 public:
  explicit LinuxCallbacks(FlMethodChannel* channel) : channel_(channel) {}

  void EmitDropEvent(int64_t view_id,
                     const char* method_name,
                     double x,
                     double y,
                     const std::vector<std::string>& paths) override {
    if (!channel_) return;
    g_autoptr(FlValue) path_list = fl_value_new_list();
    for (const std::string& p : paths) {
      fl_value_append_take(path_list, fl_value_new_string(p.c_str()));
    }
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "viewId", fl_value_new_int(view_id));
    fl_value_set_string_take(args, "x", fl_value_new_float(x));
    fl_value_set_string_take(args, "y", fl_value_new_float(y));
    fl_value_set_string(args, "paths", path_list);
    fl_method_channel_invoke_method(channel_, method_name, args, nullptr, nullptr, nullptr);
  }

  void EmitBatchRealized(const std::string& batch_id,
                         const std::vector<std::string>& paths) override {
    if (!channel_) return;
    g_autoptr(FlValue) path_list = fl_value_new_list();
    for (const std::string& p : paths) {
      fl_value_append_take(path_list, fl_value_new_string(p.c_str()));
    }
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "batchId", fl_value_new_string(batch_id.c_str()));
    fl_value_set_string(args, "paths", path_list);
    fl_method_channel_invoke_method(
        channel_, "onBatchRealized", args, nullptr, nullptr, nullptr);
  }

  void EmitBatchTransferFinished(const std::string& batch_id,
                                 bool success,
                                 bool immediate_if_unused) override {
    if (!channel_) return;
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "batchId", fl_value_new_string(batch_id.c_str()));
    fl_value_set_string_take(args, "success", fl_value_new_bool(success));
    fl_value_set_string_take(
        args, "immediateIfUnused", fl_value_new_bool(immediate_if_unused));
    fl_method_channel_invoke_method(
        channel_, "onBatchTransferFinished", args, nullptr, nullptr, nullptr);
  }

  void EmitClipboardOwnershipLost(const std::string& batch_id) override {
    if (!channel_) return;
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "batchId", fl_value_new_string(batch_id.c_str()));
    fl_method_channel_invoke_method(
        channel_, "onClipboardOwnershipLost", args, nullptr, nullptr, nullptr);
  }

 private:
  FlMethodChannel* channel_;  // owned by plugin GObject
};

}  // namespace

struct _VeDesktopTransferPlugin {
  GObject parent_instance;
  FlView* initial_view;
  gulong initial_view_destroy_sig;
  FlMethodChannel* channel;
  ve_transfer::EngineBridgeLinux* engine;
  LinuxCallbacks* callbacks;
  ve_transfer::DndLinux* dnd;
  ve_transfer::ClipboardLinux* clipboard;
  std::map<int64_t, FlView*>* view_map;
  std::mutex* batches_mu;
  std::map<std::string, std::weak_ptr<ve_transfer::TransferBatch>>* active_batches;
};

G_DEFINE_TYPE(VeDesktopTransferPlugin, ve_desktop_transfer_plugin, g_object_get_type())

static const char* DetectBackendName() {
  GdkDisplay* display = gdk_display_get_default();
#ifdef GDK_WINDOWING_WAYLAND
  if (display && GDK_IS_WAYLAND_DISPLAY(display)) return "gtk_wayland";
#endif
#ifdef GDK_WINDOWING_X11
  if (display && GDK_IS_X11_DISPLAY(display)) return "gtk_x11";
#endif
  return "gtk";
}

static void OnInitialViewDestroy(GtkWidget*, gpointer user_data) {
  auto* self = VE_DESKTOP_TRANSFER_PLUGIN(user_data);
  if (!self) return;
  self->initial_view = nullptr;
  self->initial_view_destroy_sig = 0;
}

static FlView* FindUnboundView(VeDesktopTransferPlugin* self) {
  std::vector<FlView*> live_views;
  if (self->initial_view && GTK_IS_WIDGET(self->initial_view)) {
    live_views.push_back(self->initial_view);
  }
  GList* toplevels = gtk_window_list_toplevels();
  for (GList* l = toplevels; l != nullptr; l = l->next) {
    FindFlViewsInWidget(GTK_WIDGET(l->data), &live_views);
  }
  g_list_free(toplevels);

  // Prune any destroyed views still lingering in view_map and return the newest unbound view.
  for (auto it = self->view_map->begin(); it != self->view_map->end();) {
    if (!it->second || !GTK_IS_WIDGET(it->second)) {
      it = self->view_map->erase(it);
    } else {
      ++it;
    }
  }
  for (auto it = live_views.rbegin(); it != live_views.rend(); ++it) {
    FlView* candidate = *it;
    bool bound = false;
    for (const auto& kv : *self->view_map) {
      if (kv.second == candidate) {
        bound = true;
        break;
      }
    }
    if (!bound) return candidate;
  }
  return nullptr;
}

static void ve_desktop_transfer_plugin_handle_method_call(
    VeDesktopTransferPlugin* self, FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* args_map =
      (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) ? args : nullptr;

  if (g_strcmp0(method, "initialize") == 0) {
    const std::string lib_path =
        args_map ? FlLookupString(args_map, "engineLibraryPath") : std::string();
    self->engine->Initialize(lib_path);
    g_autoptr(FlValue) reply = fl_value_new_map();
    fl_value_set_string_take(reply, "supported", fl_value_new_bool(TRUE));
    fl_value_set_string_take(reply, "backend", fl_value_new_string(DetectBackendName()));
    fl_method_call_respond_success(method_call, reply, nullptr);
    return;
  }

  if (g_strcmp0(method, "registerView") == 0) {
    const int64_t view_id = args_map ? FlLookupInt(args_map, "viewId", -1) : -1;
    bool ok = false;
    if (view_id >= 0) {
      if (self->view_map->find(view_id) != self->view_map->end()) {
        ok = true;
      } else {
        FlView* target = (view_id == 0 && self->initial_view != nullptr)
            ? self->initial_view
            : FindUnboundView(self);
        if (target != nullptr) {
          (*self->view_map)[view_id] = target;
          self->dnd->AttachView(view_id, target);
          ok = true;
        }
      }
    }
    g_autoptr(FlValue) reply = fl_value_new_bool(ok);
    fl_method_call_respond_success(method_call, reply, nullptr);
    return;
  }

  if (g_strcmp0(method, "unregisterView") == 0) {
    if (args_map) {
      const int64_t view_id = FlLookupInt(args_map, "viewId", -1);
      self->dnd->DetachView(view_id);
      self->view_map->erase(view_id);
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }

  if (g_strcmp0(method, "startDrag") == 0) {
    if (!args_map) {
      g_autoptr(FlValue) reply = fl_value_new_string("error");
      fl_method_call_respond_success(method_call, reply, nullptr);
      return;
    }
    const int64_t view_id = FlLookupInt(args_map, "viewId", 0);
    FlValue* manifest = fl_value_lookup_string(args_map, "manifest");
    if (!manifest || fl_value_get_type(manifest) != FL_VALUE_TYPE_MAP) {
      g_autoptr(FlValue) reply = fl_value_new_string("error");
      fl_method_call_respond_success(method_call, reply, nullptr);
      return;
    }
    self->engine->Initialize(std::string());
    const auto batch = ParseManifest(manifest);
    {
      std::lock_guard<std::mutex> lock(*self->batches_mu);
      (*self->active_batches)[batch->batch_id] = batch;
    }
    if (!self->dnd->BeginOutboundDrag(view_id, batch, method_call)) {
      g_autoptr(FlValue) reply = fl_value_new_string("cancelled");
      fl_method_call_respond_success(method_call, reply, nullptr);
    }
    // Otherwise responded asynchronously inside drag-end.
    return;
  }

  if (g_strcmp0(method, "setClipboardFiles") == 0) {
    FlValue* manifest = args_map ? fl_value_lookup_string(args_map, "manifest") : nullptr;
    bool ok = false;
    if (manifest && fl_value_get_type(manifest) == FL_VALUE_TYPE_MAP) {
      self->engine->Initialize(std::string());
      const auto batch = ParseManifest(manifest);
      {
        std::lock_guard<std::mutex> lock(*self->batches_mu);
        (*self->active_batches)[batch->batch_id] = batch;
      }
      ok = self->clipboard->SetFiles(batch);
    }
    g_autoptr(FlValue) reply = fl_value_new_bool(ok);
    fl_method_call_respond_success(method_call, reply, nullptr);
    return;
  }

  if (g_strcmp0(method, "setClipboardImage") == 0) {
    FlValue* png_val = args_map ? fl_value_lookup_string(args_map, "pngBytes") : nullptr;
    bool ok = false;
    if (png_val && fl_value_get_type(png_val) == FL_VALUE_TYPE_UINT8_LIST) {
      const uint8_t* ptr = fl_value_get_uint8_list(png_val);
      const size_t len = fl_value_get_length(png_val);
      std::vector<uint8_t> bytes(ptr, ptr + len);
      const bool sensitive = FlLookupBool(args_map, "sensitive", true);
      ok = self->clipboard->SetImage(bytes, sensitive);
    }
    g_autoptr(FlValue) reply = fl_value_new_bool(ok);
    fl_method_call_respond_success(method_call, reply, nullptr);
    return;
  }

  if (g_strcmp0(method, "setSensitiveClipboardText") == 0) {
    const std::string text = args_map ? FlLookupString(args_map, "text") : std::string();
    const bool ok = self->clipboard->SetSensitiveText(text);
    g_autoptr(FlValue) reply = fl_value_new_bool(ok);
    fl_method_call_respond_success(method_call, reply, nullptr);
    return;
  }

  if (g_strcmp0(method, "clearSensitiveClipboardText") == 0) {
    FlValue* exp_val = args_map ? fl_value_lookup_string(args_map, "expectedText") : nullptr;
    std::string exp_str;
    const std::string* exp_ptr = nullptr;
    if (exp_val && fl_value_get_type(exp_val) == FL_VALUE_TYPE_STRING) {
      exp_str = fl_value_get_string(exp_val);
      exp_ptr = &exp_str;
    }
    const bool ok = self->clipboard->ClearSensitiveText(exp_ptr);
    g_autoptr(FlValue) reply = fl_value_new_bool(ok);
    fl_method_call_respond_success(method_call, reply, nullptr);
    return;
  }

  if (g_strcmp0(method, "clearClipboardIfBatch") == 0) {
    FlValue* bid_val = args_map ? fl_value_lookup_string(args_map, "batchId") : nullptr;
    FlValue* vid_val = args_map ? fl_value_lookup_string(args_map, "volId") : nullptr;
    std::string bid;
    const std::string* bid_ptr = nullptr;
    if (bid_val && fl_value_get_type(bid_val) == FL_VALUE_TYPE_STRING) {
      bid = fl_value_get_string(bid_val);
      bid_ptr = &bid;
    }
    int32_t vid = 0;
    const int32_t* vid_ptr = nullptr;
    if (vid_val && fl_value_get_type(vid_val) == FL_VALUE_TYPE_INT) {
      vid = static_cast<int32_t>(fl_value_get_int(vid_val));
      vid_ptr = &vid;
    }
    FlValue* clear_img_val = args_map ? fl_value_lookup_string(args_map, "clearImage") : nullptr;
    const bool clear_image =
        clear_img_val && fl_value_get_type(clear_img_val) == FL_VALUE_TYPE_BOOL &&
        fl_value_get_bool(clear_img_val);
    const bool ok = self->clipboard->ClearIfBatch(bid_ptr, vid_ptr, clear_image);
    g_autoptr(FlValue) reply = fl_value_new_bool(ok);
    fl_method_call_respond_success(method_call, reply, nullptr);
    return;
  }

  if (g_strcmp0(method, "inspectClipboard") == 0) {
    const auto info = self->clipboard->Inspect();
    g_autoptr(FlValue) paths = fl_value_new_list();
    for (const std::string& p : info.file_paths) {
      fl_value_append_take(paths, fl_value_new_string(p.c_str()));
    }
    g_autoptr(FlValue) reply = fl_value_new_map();
    fl_value_set_string_take(reply, "hasFiles", fl_value_new_bool(info.has_files));
    fl_value_set_string_take(reply, "isOwnFiles", fl_value_new_bool(info.is_own_files));
    fl_value_set_string_take(
        reply,
        "ownBatchId",
        info.own_batch_id.empty()
            ? fl_value_new_null()
            : fl_value_new_string(info.own_batch_id.c_str()));
    fl_value_set_string(reply, "filePaths", paths);
    fl_value_set_string_take(reply, "hasImage", fl_value_new_bool(info.has_image));
    fl_value_set_string_take(reply, "isMove", fl_value_new_bool(info.is_move));
    fl_method_call_respond_success(method_call, reply, nullptr);
    return;
  }

  if (g_strcmp0(method, "readClipboardImageData") == 0) {
    const std::vector<uint8_t> bytes = self->clipboard->ReadImagePng();
    if (bytes.empty()) {
      fl_method_call_respond_success(method_call, nullptr, nullptr);
      return;
    }
    g_autoptr(FlValue) reply = fl_value_new_map();
    fl_value_set_string_take(reply, "format", fl_value_new_string("png"));
    fl_value_set_string_take(
        reply, "bytes", fl_value_new_uint8_list(bytes.data(), bytes.size()));
    fl_method_call_respond_success(method_call, reply, nullptr);
    return;
  }

  if (g_strcmp0(method, "hardenStagingDir") == 0) {
    const std::string path = args_map ? FlLookupString(args_map, "path") : std::string();
    const bool ok = ve_transfer::HardenStagingDirectoryLinux(path);
    g_autoptr(FlValue) reply = fl_value_new_bool(ok);
    fl_method_call_respond_success(method_call, reply, nullptr);
    return;
  }

  if (g_strcmp0(method, "isStagingBatchInUse") == 0) {
    const std::string path = args_map ? FlLookupString(args_map, "path") : std::string();
    const bool in_use = ve_transfer::IsStagingBatchInUseLinux(path);
    g_autoptr(FlValue) reply = fl_value_new_bool(in_use);
    fl_method_call_respond_success(method_call, reply, nullptr);
    return;
  }

  if (g_strcmp0(method, "cancelBatch") == 0) {
    if (args_map) {
      const std::string batch_id = FlLookupString(args_map, "batchId");
      std::shared_ptr<ve_transfer::TransferBatch> batch;
      {
        std::lock_guard<std::mutex> lock(*self->batches_mu);
        auto it = self->active_batches->find(batch_id);
        if (it != self->active_batches->end()) batch = it->second.lock();
      }
      if (batch) {
        batch->cancelled.store(true);
        int32_t op_id = 0;
        {
          std::lock_guard<std::mutex> lock(batch->mu);
          op_id = batch->op_id;
        }
        if (op_id > 0) self->engine->OpCancel(op_id);
      }
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }

  fl_method_call_respond_not_implemented(method_call, nullptr);
}

static void method_call_cb(FlMethodChannel*, FlMethodCall* method_call, gpointer user_data) {
  auto* plugin = VE_DESKTOP_TRANSFER_PLUGIN(user_data);
  ve_desktop_transfer_plugin_handle_method_call(plugin, method_call);
}

static void ve_desktop_transfer_plugin_dispose(GObject* object) {
  auto* self = VE_DESKTOP_TRANSFER_PLUGIN(object);
  if (self->initial_view && self->initial_view_destroy_sig != 0 &&
      g_signal_handler_is_connected(self->initial_view, self->initial_view_destroy_sig)) {
    g_signal_handler_disconnect(self->initial_view, self->initial_view_destroy_sig);
    self->initial_view_destroy_sig = 0;
  }
  delete self->dnd;
  self->dnd = nullptr;
  delete self->clipboard;
  self->clipboard = nullptr;
  delete self->callbacks;
  self->callbacks = nullptr;
  delete self->engine;
  self->engine = nullptr;
  delete self->view_map;
  self->view_map = nullptr;
  delete self->active_batches;
  self->active_batches = nullptr;
  delete self->batches_mu;
  self->batches_mu = nullptr;
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(ve_desktop_transfer_plugin_parent_class)->dispose(object);
}

static void ve_desktop_transfer_plugin_class_init(VeDesktopTransferPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = ve_desktop_transfer_plugin_dispose;
}

static void ve_desktop_transfer_plugin_init(VeDesktopTransferPlugin* self) {
  self->initial_view = nullptr;
  self->initial_view_destroy_sig = 0;
  self->channel = nullptr;
  self->engine = new ve_transfer::EngineBridgeLinux();
  self->view_map = new std::map<int64_t, FlView*>();
  self->batches_mu = new std::mutex();
  self->active_batches = new std::map<std::string, std::weak_ptr<ve_transfer::TransferBatch>>();
}

void ve_desktop_transfer_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  auto* plugin = VE_DESKTOP_TRANSFER_PLUGIN(
      g_object_new(ve_desktop_transfer_plugin_get_type(), nullptr));

  plugin->initial_view = fl_plugin_registrar_get_view(registrar);
  if (plugin->initial_view && GTK_IS_WIDGET(plugin->initial_view)) {
    plugin->initial_view_destroy_sig = g_signal_connect(
        plugin->initial_view, "destroy", G_CALLBACK(OnInitialViewDestroy), plugin);
  }

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "vaultexplorer/desktop_transfer",
      FL_METHOD_CODEC(codec));
  plugin->callbacks = new LinuxCallbacks(plugin->channel);
  plugin->dnd = new ve_transfer::DndLinux(plugin->engine, plugin->callbacks);
  plugin->clipboard = new ve_transfer::ClipboardLinux(plugin->engine, plugin->callbacks);

  fl_method_channel_set_method_call_handler(
      plugin->channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
