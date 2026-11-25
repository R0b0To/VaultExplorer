#include "ve_clipboard_linux.h"

#include <atomic>
#include <cstring>
#include <sstream>
#include <thread>

namespace ve_transfer {

namespace {

void ZeroWipeString(std::string* s) {
  if (!s || s->empty()) return;
  volatile char* p = &(*s)[0];
  for (size_t i = 0; i < s->size(); ++i) {
    p[i] = 0;
  }
  s->clear();
}

void ZeroWipeBytes(std::vector<uint8_t>* b) {
  if (!b || b->empty()) return;
  volatile uint8_t* p = b->data();
  for (size_t i = 0; i < b->size(); ++i) {
    p[i] = 0;
  }
  b->clear();
}

std::vector<std::string> ParseGnomeOrUriPayload(
    const char* raw, gint len, bool is_gnome, bool* is_move_out) {
  std::vector<std::string> out;
  if (!raw || len <= 0) return out;
  std::string payload(raw, static_cast<size_t>(len));
  std::istringstream iss(payload);
  std::string line;
  bool first = true;
  while (std::getline(iss, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (first && is_gnome) {
      first = false;
      if (is_move_out) *is_move_out = (line == "cut");
      continue;
    }
    first = false;
    if (line.empty() || line[0] == '#') continue;
    g_autofree gchar* filename = g_filename_from_uri(line.c_str(), nullptr, nullptr);
    if (filename != nullptr && filename[0] != '\0') {
      out.emplace_back(filename);
    }
  }
  return out;
}

}  // namespace

ClipboardLinux::ClipboardLinux(
    const EngineBridgeLinux* bridge, TransferCallbacksLinux* callbacks)
    : bridge_(bridge), callbacks_(callbacks) {
  clipboard_ = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  if (clipboard_) {
    owner_change_sig_ =
        g_signal_connect(clipboard_, "owner-change", G_CALLBACK(OnOwnerChange), this);
  }
}

ClipboardLinux::~ClipboardLinux() {
  ClearOwnedOnShutdown();
  if (clipboard_ && owner_change_sig_ != 0 &&
      g_signal_handler_is_connected(clipboard_, owner_change_sig_)) {
    g_signal_handler_disconnect(clipboard_, owner_change_sig_);
    owner_change_sig_ = 0;
  }
}

void ClipboardLinux::OnOwnerChange(GtkClipboard*, GdkEvent*, gpointer user_data) {
  auto* self = static_cast<ClipboardLinux*>(user_data);
  if (!self || self->suppress_owner_change_) return;
  if (self->active_files_ != nullptr) {
    // ClearFilesCb handles ownership loss when GTK replaces our data; this handles
    // external X11/Wayland owners that drop selection without clear_func firing yet.
    const gpointer owner = gtk_clipboard_get_owner(self->clipboard_);
    if (owner != static_cast<gpointer>(self->active_files_)) {
      FilesOwner* lost = self->active_files_;
      self->active_files_ = nullptr;
      const std::string id = lost->batch ? lost->batch->batch_id : std::string();
      if (!id.empty() && self->callbacks_) {
        self->callbacks_->EmitClipboardOwnershipLost(id);
      }
    }
  }
}

bool ClipboardLinux::SetFiles(std::shared_ptr<TransferBatch> batch) {
  if (!clipboard_ || !batch || batch->items.empty()) return false;
  batch->is_clipboard = true;

  auto* data = new FilesOwner();
  data->owner = this;
  data->batch = std::move(batch);

  static GtkTargetEntry targets[] = {
      {const_cast<gchar*>("x-special/gnome-copied-files"), 0, 0},
      {const_cast<gchar*>("text/uri-list"), 0, 1},
      {const_cast<gchar*>("UTF8_STRING"), 0, 2},
  };

  suppress_owner_change_ = true;
  const gboolean ok = gtk_clipboard_set_with_data(
      clipboard_, targets, 3, GetFilesCb, ClearFilesCb, data);
  suppress_owner_change_ = false;
  if (!ok) {
    delete data;
    return false;
  }
  active_files_ = data;
  return true;
}

void ClipboardLinux::GetFilesCb(
    GtkClipboard*, GtkSelectionData* sdata, guint info, gpointer user_data) {
  auto* state = static_cast<FilesOwner*>(user_data);
  if (!state || !state->owner || !state->batch) return;
  if (state->batch->cancelled.load()) return;

  std::vector<std::string> paths;
  bool ok = false;

  if (state->batch->vol_id < 0) {
    ok = state->owner->bridge_->StageBatch(state->batch.get(), &paths);
  } else {
    {
      std::lock_guard<std::mutex> lock(state->batch->mu);
      if (state->batch->realized) {
        paths = state->batch->staged_root_paths;
        ok = !paths.empty();
      }
    }
    if (!ok && !state->batch->cancelled.load()) {
      std::atomic<bool> done(false);
      std::thread worker([&]() {
        ok = state->owner->bridge_->StageBatch(state->batch.get(), &paths);
        done.store(true);
        g_main_context_wakeup(nullptr);
      });
      while (!done.load()) {
        g_main_context_iteration(nullptr, TRUE);
      }
      worker.join();
    }
  }

  if (!ok || paths.empty() || state->batch->cancelled.load()) return;

  if (state->batch->vol_id >= 0 && !state->realized_notified) {
    state->realized_notified = true;
    if (state->owner->callbacks_) {
      state->owner->callbacks_->EmitBatchRealized(state->batch->batch_id, paths);
    }
  }

  if (info == 0) {
    // x-special/gnome-copied-files: "copy\nfile:///...\nfile:///..."
    std::string payload = "copy";
    for (const std::string& p : paths) {
      g_autofree gchar* uri = g_filename_to_uri(p.c_str(), nullptr, nullptr);
      if (uri) {
        payload.push_back('\n');
        payload.append(uri);
      }
    }
    gtk_selection_data_set(
        sdata,
        gdk_atom_intern_static_string("x-special/gnome-copied-files"),
        8,
        reinterpret_cast<const guchar*>(payload.data()),
        static_cast<gint>(payload.size()));
    return;
  }

  if (info == 1) {
    std::vector<gchar*> uri_ptrs;
    uri_ptrs.reserve(paths.size() + 1);
    for (const std::string& p : paths) {
      gchar* uri = g_filename_to_uri(p.c_str(), nullptr, nullptr);
      if (uri) uri_ptrs.push_back(uri);
    }
    uri_ptrs.push_back(nullptr);
    if (uri_ptrs.size() > 1) {
      gtk_selection_data_set_uris(sdata, uri_ptrs.data());
    }
    for (gchar* u : uri_ptrs) g_free(u);
    return;
  }

  // Fallback UTF8_STRING newline-joined paths.
  std::string joined;
  for (size_t i = 0; i < paths.size(); ++i) {
    if (i > 0) joined.push_back('\n');
    joined.append(paths[i]);
  }
  gtk_selection_data_set_text(
      sdata, joined.data(), static_cast<gint>(joined.size()));
}

void ClipboardLinux::ClearFilesCb(GtkClipboard*, gpointer user_data) {
  auto* state = static_cast<FilesOwner*>(user_data);
  if (!state) return;
  ClipboardLinux* owner = state->owner;
  const std::string batch_id = state->batch ? state->batch->batch_id : std::string();
  if (owner && owner->active_files_ == state) {
    owner->active_files_ = nullptr;
  }
  delete state;
  if (owner && !owner->suppress_owner_change_ &&
      !batch_id.empty() && owner->callbacks_) {
    owner->callbacks_->EmitClipboardOwnershipLost(batch_id);
  }
}

bool ClipboardLinux::SetImage(const std::vector<uint8_t>& png_bytes, bool sensitive) {
  if (!clipboard_ || png_bytes.empty()) return false;

  auto* data = new ImageOwner();
  data->owner = this;
  data->png_bytes = png_bytes;
  data->sensitive = sensitive;

  GtkTargetList* tlist = gtk_target_list_new(nullptr, 0);
  gtk_target_list_add(tlist, gdk_atom_intern_static_string("image/png"), 0, 0);
  gtk_target_list_add_image_targets(tlist, 1, TRUE);
  gint n_targets = 0;
  GtkTargetEntry* entries = gtk_target_table_new_from_list(tlist, &n_targets);
  gtk_target_list_unref(tlist);

  suppress_owner_change_ = true;
  const gboolean ok = gtk_clipboard_set_with_data(
      clipboard_, entries, n_targets, GetImageCb, ClearImageCb, data);
  suppress_owner_change_ = false;
  gtk_target_table_free(entries, n_targets);

  if (!ok) {
    ZeroWipeBytes(&data->png_bytes);
    delete data;
    return false;
  }
  active_image_ = data;
  return true;
}

void ClipboardLinux::GetImageCb(
    GtkClipboard*, GtkSelectionData* sdata, guint info, gpointer user_data) {
  auto* state = static_cast<ImageOwner*>(user_data);
  if (!state || state->png_bytes.empty()) return;

  if (info == 0) {
    gtk_selection_data_set(
        sdata,
        gdk_atom_intern_static_string("image/png"),
        8,
        state->png_bytes.data(),
        static_cast<gint>(state->png_bytes.size()));
    return;
  }

  g_autoptr(GdkPixbufLoader) loader = gdk_pixbuf_loader_new_with_type("png", nullptr);
  if (!loader) return;
  if (gdk_pixbuf_loader_write(loader, state->png_bytes.data(), state->png_bytes.size(), nullptr)) {
    gdk_pixbuf_loader_close(loader, nullptr);
    GdkPixbuf* pixbuf = gdk_pixbuf_loader_get_pixbuf(loader);
    if (pixbuf) {
      gtk_selection_data_set_pixbuf(sdata, pixbuf);
    }
  }
}

void ClipboardLinux::ClearImageCb(GtkClipboard*, gpointer user_data) {
  auto* state = static_cast<ImageOwner*>(user_data);
  if (!state) return;
  if (state->owner && state->owner->active_image_ == state) {
    state->owner->active_image_ = nullptr;
  }
  ZeroWipeBytes(&state->png_bytes);
  delete state;
}

bool ClipboardLinux::SetSensitiveText(const std::string& text) {
  if (!clipboard_) return false;

  auto* data = new TextOwner();
  data->owner = this;
  data->text = text;

  GtkTargetList* tlist = gtk_target_list_new(nullptr, 0);
  gtk_target_list_add_text_targets(tlist, 0);
  gtk_target_list_add(
      tlist, gdk_atom_intern_static_string("x-kde-passwordManagerHint"), 0, 1);
  gint n_targets = 0;
  GtkTargetEntry* entries = gtk_target_table_new_from_list(tlist, &n_targets);
  gtk_target_list_unref(tlist);

  suppress_owner_change_ = true;
  const gboolean ok = gtk_clipboard_set_with_data(
      clipboard_, entries, n_targets, GetTextCb, ClearTextCb, data);
  suppress_owner_change_ = false;
  gtk_target_table_free(entries, n_targets);

  if (!ok) {
    ZeroWipeString(&data->text);
    delete data;
    return false;
  }
  active_text_ = data;
  return true;
}

void ClipboardLinux::GetTextCb(
    GtkClipboard*, GtkSelectionData* sdata, guint info, gpointer user_data) {
  auto* state = static_cast<TextOwner*>(user_data);
  if (!state) return;
  if (info == 1) {
    static const char kSecret[] = "secret";
    gtk_selection_data_set(
        sdata,
        gdk_atom_intern_static_string("x-kde-passwordManagerHint"),
        8,
        reinterpret_cast<const guchar*>(kSecret),
        static_cast<gint>(sizeof(kSecret) - 1));
    return;
  }
  gtk_selection_data_set_text(
      sdata, state->text.data(), static_cast<gint>(state->text.size()));
}

void ClipboardLinux::ClearTextCb(GtkClipboard*, gpointer user_data) {
  auto* state = static_cast<TextOwner*>(user_data);
  if (!state) return;
  if (state->owner && state->owner->active_text_ == state) {
    state->owner->active_text_ = nullptr;
  }
  ZeroWipeString(&state->text);
  delete state;
}

bool ClipboardLinux::ClearSensitiveText(const std::string* expected_text) {
  if (!clipboard_ || !active_text_) return false;
  if (expected_text != nullptr && active_text_->text != *expected_text) {
    return true;  // Newer secret copied; keep it.
  }
  suppress_owner_change_ = true;
  gtk_clipboard_clear(clipboard_);
  suppress_owner_change_ = false;
  return true;
}

bool ClipboardLinux::ClearIfBatch(const std::string* batch_id,
                                  const int32_t* vol_id,
                                  bool clear_image) {
  if (!clipboard_) return false;
  bool cleared = false;
  if (active_files_ && active_files_->batch) {
    const bool id_matches = !batch_id || active_files_->batch->batch_id == *batch_id;
    const bool vol_matches = !vol_id || active_files_->batch->vol_id == *vol_id;
    if (id_matches && vol_matches) {
      suppress_owner_change_ = true;
      gtk_clipboard_clear(clipboard_);
      suppress_owner_change_ = false;
      cleared = true;
    }
  }
  if (clear_image && active_image_) {
    suppress_owner_change_ = true;
    gtk_clipboard_clear(clipboard_);
    suppress_owner_change_ = false;
    cleared = true;
  }
  return cleared;
}

void ClipboardLinux::ClearOwnedOnShutdown() {
  if (!clipboard_) return;
  if (active_files_ || active_image_ || active_text_) {
    suppress_owner_change_ = true;
    gtk_clipboard_clear(clipboard_);
    suppress_owner_change_ = false;
  }
}

ClipboardInspectLinux ClipboardLinux::Inspect() const {
  ClipboardInspectLinux out;
  if (!clipboard_) return out;

  if (active_files_ != nullptr &&
      gtk_clipboard_get_owner(clipboard_) == static_cast<gpointer>(active_files_)) {
    out.has_files = true;
    out.is_own_files = true;
    if (active_files_->batch) out.own_batch_id = active_files_->batch->batch_id;
    return out;
  }

  GtkSelectionData* gnome = gtk_clipboard_wait_for_contents(
      clipboard_, gdk_atom_intern_static_string("x-special/gnome-copied-files"));
  if (gnome != nullptr) {
    const gint len = gtk_selection_data_get_length(gnome);
    const char* raw = reinterpret_cast<const char*>(gtk_selection_data_get_data(gnome));
    out.file_paths = ParseGnomeOrUriPayload(raw, len, true, &out.is_move);
    gtk_selection_data_free(gnome);
    out.has_files = !out.file_paths.empty();
  }

  if (!out.has_files && gtk_clipboard_wait_is_uris_available(clipboard_)) {
    gchar** uris = gtk_clipboard_wait_for_uris(clipboard_);
    if (uris != nullptr) {
      for (int i = 0; uris[i] != nullptr; ++i) {
        g_autofree gchar* fn = g_filename_from_uri(uris[i], nullptr, nullptr);
        if (fn != nullptr && fn[0] != '\0') out.file_paths.emplace_back(fn);
      }
      g_strfreev(uris);
    }
    out.has_files = !out.file_paths.empty();
  }

  out.has_image = gtk_clipboard_wait_is_image_available(clipboard_) != FALSE;
  return out;
}

std::vector<uint8_t> ClipboardLinux::ReadImagePng() const {
  std::vector<uint8_t> out;
  if (!clipboard_) return out;

  GtkSelectionData* png = gtk_clipboard_wait_for_contents(
      clipboard_, gdk_atom_intern_static_string("image/png"));
  if (png != nullptr) {
    const gint len = gtk_selection_data_get_length(png);
    const guchar* data = gtk_selection_data_get_data(png);
    if (len > 0 && data != nullptr) {
      out.assign(data, data + len);
    }
    gtk_selection_data_free(png);
    if (!out.empty()) return out;
  }

  g_autoptr(GdkPixbuf) pixbuf = gtk_clipboard_wait_for_image(clipboard_);
  if (pixbuf != nullptr) {
    gchar* buf = nullptr;
    gsize size = 0;
    if (gdk_pixbuf_save_to_buffer(pixbuf, &buf, &size, "png", nullptr, nullptr) &&
        buf != nullptr && size > 0) {
      out.assign(reinterpret_cast<uint8_t*>(buf), reinterpret_cast<uint8_t*>(buf) + size);
      g_free(buf);
    }
  }
  return out;
}

}  // namespace ve_transfer
