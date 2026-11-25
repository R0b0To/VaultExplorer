#include "ve_dnd_linux.h"

#include <gio/gio.h>

#include <atomic>
#include <cstring>
#include <sstream>
#include <thread>
#include <vector>

namespace ve_transfer {

namespace {

bool IsKdeDesktop() {
  const char* de = g_getenv("XDG_CURRENT_DESKTOP");
  if (!de) return false;
  g_autofree gchar* lower = g_ascii_strdown(de, -1);
  return g_strstr_len(lower, -1, "kde") != nullptr ||
         g_strstr_len(lower, -1, "plasma") != nullptr;
}

std::vector<std::string> ParseUriList(const char* raw, gint len) {
  std::vector<std::string> out;
  if (!raw || len <= 0) return out;
  std::string payload(raw, static_cast<size_t>(len));
  std::istringstream iss(payload);
  std::string line;
  while (std::getline(iss, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (line.empty() || line[0] == '#') continue;
    g_autofree gchar* filename = g_filename_from_uri(line.c_str(), nullptr, nullptr);
    if (filename != nullptr && filename[0] != '\0') {
      out.emplace_back(filename);
    }
  }
  return out;
}

struct PortalResolveReq {
  DndLinux* self;
  TransferCallbacksLinux* callbacks;
  int64_t view_id;
  double x;
  double y;
};

void OnPortalReply(GObject* source, GAsyncResult* res, gpointer user_data) {
  std::unique_ptr<PortalResolveReq> req(static_cast<PortalResolveReq*>(user_data));
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source), res, &error);
  std::vector<std::string> paths;
  if (reply != nullptr && g_variant_n_children(reply) > 0) {
    g_autoptr(GVariant) arr = g_variant_get_child_value(reply, 0);
    GVariantIter iter;
    const gchar* path = nullptr;
    g_variant_iter_init(&iter, arr);
    while (g_variant_iter_next(&iter, "&s", &path)) {
      if (path && path[0] != '\0') paths.emplace_back(path);
    }
  }
  if (req->callbacks && !paths.empty()) {
    req->callbacks->EmitDropEvent(req->view_id, "onDropReceived", req->x, req->y, paths);
  }
}

}  // namespace

DndLinux::DndLinux(const EngineBridgeLinux* bridge, TransferCallbacksLinux* callbacks)
    : bridge_(bridge), callbacks_(callbacks) {}

DndLinux::~DndLinux() {
  DetachAll();
  if (cached_pointer_event_) {
    gdk_event_free(cached_pointer_event_);
    cached_pointer_event_ = nullptr;
  }
}

void DndLinux::AttachView(int64_t view_id, FlView* view) {
  if (!view || views_.find(view_id) != views_.end()) return;
  GtkWidget* widget = GTK_WIDGET(view);

  static GtkTargetEntry dest_entries[] = {
      {const_cast<gchar*>("application/vnd.portal.filetransfer"), GTK_TARGET_OTHER_APP, 0},
      {const_cast<gchar*>("text/uri-list"), GTK_TARGET_OTHER_APP, 1},
      {const_cast<gchar*>("STRING"), GTK_TARGET_OTHER_APP, 2},
  };
  gtk_drag_dest_set(widget, GTK_DEST_DEFAULT_ALL, dest_entries, 3, GDK_ACTION_COPY);
  gtk_drag_dest_add_uri_targets(widget);

  gtk_widget_add_events(
      widget, GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK | GDK_POINTER_MOTION_MASK);

  auto state = std::unique_ptr<ViewState>(new ViewState());
  state->view_id = view_id;
  state->view = view;
  state->owner = this;

  ViewState* raw = state.get();
  state->motion_sig = g_signal_connect(widget, "drag-motion", G_CALLBACK(OnDragMotion), raw);
  state->leave_sig = g_signal_connect(widget, "drag-leave", G_CALLBACK(OnDragLeave), raw);
  state->data_recv_sig =
      g_signal_connect(widget, "drag-data-received", G_CALLBACK(OnDragDataReceived), raw);
  state->press_sig =
      g_signal_connect(widget, "button-press-event", G_CALLBACK(OnButtonPress), raw);
  state->ptr_motion_sig =
      g_signal_connect(widget, "motion-notify-event", G_CALLBACK(OnPointerMotion), raw);
  state->release_sig =
      g_signal_connect(widget, "button-release-event", G_CALLBACK(OnButtonRelease), raw);
  state->drag_data_get_sig =
      g_signal_connect(widget, "drag-data-get", G_CALLBACK(OnDragDataGet), raw);
  state->drag_end_sig = g_signal_connect(widget, "drag-end", G_CALLBACK(OnDragEnd), raw);
  state->drag_failed_sig =
      g_signal_connect(widget, "drag-failed", G_CALLBACK(OnDragFailed), raw);
  state->destroy_sig = g_signal_connect(widget, "destroy", G_CALLBACK(OnWidgetDestroy), raw);

  views_[view_id] = std::move(state);
}

void DndLinux::DetachView(int64_t view_id) {
  auto it = views_.find(view_id);
  if (it == views_.end()) return;
  ViewState* raw = it->second.get();
  GtkWidget* widget = GTK_WIDGET(raw->view);
  if (widget && GTK_IS_WIDGET(widget)) {
    const gulong sigs[] = {
        raw->motion_sig,
        raw->leave_sig,
        raw->data_recv_sig,
        raw->press_sig,
        raw->ptr_motion_sig,
        raw->release_sig,
        raw->drag_data_get_sig,
        raw->drag_end_sig,
        raw->drag_failed_sig,
        raw->destroy_sig,
    };
    for (gulong id : sigs) {
      if (id != 0 && g_signal_handler_is_connected(widget, id)) {
        g_signal_handler_disconnect(widget, id);
      }
    }
  }
  views_.erase(it);
}

void DndLinux::DetachAll() {
  std::vector<int64_t> ids;
  ids.reserve(views_.size());
  for (const auto& kv : views_) ids.push_back(kv.first);
  for (int64_t id : ids) DetachView(id);
}

bool DndLinux::HasActiveView(int64_t view_id) const {
  return views_.find(view_id) != views_.end();
}

void DndLinux::CachePointerEvent(const GdkEvent* event, int64_t view_id, double x, double y) {
  if (!event) return;
  if (cached_pointer_event_) {
    gdk_event_free(cached_pointer_event_);
  }
  cached_pointer_event_ = gdk_event_copy(event);
  cached_event_view_id_ = view_id;
  cached_x_ = x;
  cached_y_ = y;
}

gboolean DndLinux::OnButtonPress(GtkWidget*, GdkEventButton* event, gpointer user_data) {
  auto* st = static_cast<ViewState*>(user_data);
  if (event && event->button == 1 && st && st->owner) {
    st->owner->primary_button_down_ = true;
    st->owner->CachePointerEvent(
        reinterpret_cast<const GdkEvent*>(event), st->view_id, event->x, event->y);
  }
  return FALSE;  // Never swallow pointer events from Flutter.
}

gboolean DndLinux::OnPointerMotion(GtkWidget*, GdkEventMotion* event, gpointer user_data) {
  auto* st = static_cast<ViewState*>(user_data);
  if (event && (event->state & GDK_BUTTON1_MASK) != 0 && st && st->owner) {
    st->owner->primary_button_down_ = true;
    st->owner->CachePointerEvent(
        reinterpret_cast<const GdkEvent*>(event), st->view_id, event->x, event->y);
  }
  return FALSE;
}

gboolean DndLinux::OnButtonRelease(GtkWidget*, GdkEventButton* event, gpointer user_data) {
  auto* st = static_cast<ViewState*>(user_data);
  if (event && event->button == 1 && st && st->owner) {
    st->owner->primary_button_down_ = false;
  }
  return FALSE;
}

gboolean DndLinux::OnDragMotion(
    GtkWidget*, GdkDragContext*, gint x, gint y, guint, gpointer user_data) {
  auto* st = static_cast<ViewState*>(user_data);
  if (st && st->owner && st->owner->callbacks_) {
    st->owner->callbacks_->EmitDropEvent(
        st->view_id, "onDropUpdated", static_cast<double>(x), static_cast<double>(y), {});
  }
  return FALSE;
}

void DndLinux::OnDragLeave(GtkWidget*, GdkDragContext*, guint, gpointer user_data) {
  auto* st = static_cast<ViewState*>(user_data);
  if (st && st->owner && st->owner->callbacks_) {
    st->owner->callbacks_->EmitDropEvent(st->view_id, "onDropExited", 0.0, 0.0, {});
  }
}

void DndLinux::ResolvePortalKeyAsync(
    int64_t view_id, double x, double y, const std::string& key) {
  g_autoptr(GError) err = nullptr;
  GDBusConnection* bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &err);
  if (!bus) return;

  GVariantBuilder dict;
  g_variant_builder_init(&dict, G_VARIANT_TYPE("a{sv}"));
  GVariant* params = g_variant_new("(sa{sv})", key.c_str(), &dict);

  auto* req = new PortalResolveReq{this, callbacks_, view_id, x, y};
  g_dbus_connection_call(
      bus,
      "org.freedesktop.portal.Documents",
      "/org/freedesktop/portal/documents",
      "org.freedesktop.portal.FileTransfer",
      "RetrieveFiles",
      params,
      G_VARIANT_TYPE("(as)"),
      G_DBUS_CALL_FLAGS_NONE,
      5000,
      nullptr,
      OnPortalReply,
      req);
  g_object_unref(bus);
}

void DndLinux::OnDragDataReceived(GtkWidget*,
                                  GdkDragContext*,
                                  gint x,
                                  gint y,
                                  GtkSelectionData* sdata,
                                  guint,
                                  guint,
                                  gpointer user_data) {
  auto* st = static_cast<ViewState*>(user_data);
  if (!st || !st->owner || !sdata) return;

  const gint len = gtk_selection_data_get_length(sdata);
  if (len <= 0) return;

  const char* raw = reinterpret_cast<const char*>(gtk_selection_data_get_data(sdata));
  g_autofree gchar* target_name = gdk_atom_name(gtk_selection_data_get_target(sdata));
  if (target_name != nullptr &&
      std::strcmp(target_name, "application/vnd.portal.filetransfer") == 0) {
    std::string key(raw, static_cast<size_t>(len));
    while (!key.empty() && (key.back() == '\n' || key.back() == '\r' || key.back() == '\0')) {
      key.pop_back();
    }
    if (!key.empty()) {
      st->owner->ResolvePortalKeyAsync(
          st->view_id, static_cast<double>(x), static_cast<double>(y), key);
    }
    return;
  }

  const std::vector<std::string> paths = ParseUriList(raw, len);
  if (!paths.empty() && st->owner->callbacks_) {
    st->owner->callbacks_->EmitDropEvent(
        st->view_id,
        "onDropReceived",
        static_cast<double>(x),
        static_cast<double>(y),
        paths);
  }
}

bool DndLinux::BeginOutboundDrag(int64_t view_id,
                                 std::shared_ptr<TransferBatch> batch,
                                 FlMethodCall* pending_call) {
  if (!batch || batch->items.empty() || active_drag_) {
    return false;
  }

  auto it = views_.find(view_id);
  if (it == views_.end() && cached_event_view_id_ >= 0) {
    it = views_.find(cached_event_view_id_);
  }
  if (it == views_.end() && !views_.empty()) {
    it = views_.begin();
  }
  if (it == views_.end()) return false;

  GdkEvent* event = cached_pointer_event_;
  if (!event || !primary_button_down_) {
    return false;
  }

  GtkWidget* widget = GTK_WIDGET(it->second->view);
  GtkTargetList* target_list = gtk_target_list_new(nullptr, 0);
  gtk_target_list_add_uri_targets(target_list, 0);

  active_drag_.reset(new OutboundDragState());
  active_drag_->batch = batch;
  active_drag_->pending_call = static_cast<FlMethodCall*>(g_object_ref(pending_call));

  GdkDragContext* ctx = gtk_drag_begin_with_coordinates(
      widget,
      target_list,
      GDK_ACTION_COPY,
      1,
      event,
      static_cast<gint>(cached_x_),
      static_cast<gint>(cached_y_));
  gtk_target_list_unref(target_list);

  if (!ctx) {
    g_object_unref(active_drag_->pending_call);
    active_drag_.reset();
    return false;
  }
  active_drag_->context = ctx;

  const char* icon_name = (batch->items.size() == 1 && batch->items[0].is_dir)
      ? "folder"
      : "text-x-generic";
  gtk_drag_set_icon_name(ctx, icon_name, 0, 0);
  if (IsKdeDesktop()) {
    // Plasma task switcher may focus briefly during drag; keep state intact.
  }
  return true;
}

void DndLinux::OnDragDataGet(GtkWidget*,
                             GdkDragContext* context,
                             GtkSelectionData* sdata,
                             guint,
                             guint,
                             gpointer user_data) {
  auto* st = static_cast<ViewState*>(user_data);
  if (!st || !st->owner || !st->owner->active_drag_) return;
  OutboundDragState* drag = st->owner->active_drag_.get();
  if (drag->context != context || !drag->batch) return;
  if (drag->batch->cancelled.load()) return;

  std::vector<std::string> paths;
  bool ok = false;

  if (drag->batch->vol_id < 0) {
    ok = st->owner->bridge_->StageBatch(drag->batch.get(), &paths);
  } else {
    {
      std::lock_guard<std::mutex> lock(drag->batch->mu);
      if (drag->batch->realized) {
        paths = drag->batch->staged_root_paths;
        ok = !paths.empty();
      }
    }
    if (!ok && !drag->batch->cancelled.load()) {
      std::atomic<bool> done(false);
      std::thread worker([&]() {
        ok = st->owner->bridge_->StageBatch(drag->batch.get(), &paths);
        done.store(true);
        g_main_context_wakeup(nullptr);
      });
      while (!done.load()) {
        g_main_context_iteration(nullptr, TRUE);
      }
      worker.join();
    }
  }

  if (!ok || paths.empty() || drag->batch->cancelled.load()) return;

  if (drag->batch->vol_id >= 0 && !drag->realized_emitted) {
    drag->realized_emitted = true;
    if (st->owner->callbacks_) {
      st->owner->callbacks_->EmitBatchRealized(drag->batch->batch_id, paths);
    }
  }

  std::vector<gchar*> uri_ptrs;
  uri_ptrs.reserve(paths.size() + 1);
  for (const std::string& p : paths) {
    gchar* uri = g_filename_to_uri(p.c_str(), nullptr, nullptr);
    if (uri) uri_ptrs.push_back(uri);
  }
  uri_ptrs.push_back(nullptr);

  if (uri_ptrs.size() > 1) {
    gtk_selection_data_set_uris(sdata, uri_ptrs.data());
    drag->data_sent = true;
  }
  for (gchar* u : uri_ptrs) {
    g_free(u);
  }
}

gboolean DndLinux::OnDragFailed(
    GtkWidget*, GdkDragContext* context, GtkDragResult, gpointer user_data) {
  auto* st = static_cast<ViewState*>(user_data);
  if (!st || !st->owner || !st->owner->active_drag_) return FALSE;
  if (st->owner->active_drag_->context != context) return FALSE;
  if (st->owner->active_drag_->batch) {
    st->owner->active_drag_->batch->cancelled.store(true);
  }
  return FALSE;
}

void DndLinux::OnDragEnd(GtkWidget*, GdkDragContext* context, gpointer user_data) {
  auto* st = static_cast<ViewState*>(user_data);
  if (!st || !st->owner || !st->owner->active_drag_) return;
  if (st->owner->active_drag_->context != context) return;
  const bool ok = st->owner->active_drag_->data_sent &&
                  !st->owner->active_drag_->batch->cancelled.load();
  st->owner->FinishOutboundDrag(ok);
}

void DndLinux::FinishOutboundDrag(bool ok) {
  if (!active_drag_) return;
  std::unique_ptr<OutboundDragState> finished = std::move(active_drag_);
  primary_button_down_ = false;

  if (finished->pending_call) {
    g_autoptr(FlValue) res = fl_value_new_string(ok ? "copied" : "cancelled");
    fl_method_call_respond_success(finished->pending_call, res, nullptr);
    g_object_unref(finished->pending_call);
    finished->pending_call = nullptr;
  }
  if (callbacks_ && finished->batch) {
    // On Linux, Nautilus/Dolphin reads staged files asynchronously after drag-end.
    callbacks_->EmitBatchTransferFinished(
        finished->batch->batch_id, ok, /*immediate_if_unused=*/!ok);
  }
}

void DndLinux::OnWidgetDestroy(GtkWidget* widget, gpointer user_data) {
  auto* st = static_cast<ViewState*>(user_data);
  if (!st || !st->owner) return;
  if (st->owner->active_drag_ && st->owner->active_drag_->batch) {
    st->owner->active_drag_->batch->cancelled.store(true);
    st->owner->FinishOutboundDrag(false);
  }
  const int64_t id = st->view_id;
  st->view = nullptr;  // Already destroying
  st->owner->views_.erase(id);
}

}  // namespace ve_transfer
