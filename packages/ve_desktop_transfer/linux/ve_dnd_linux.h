#ifndef VE_DESKTOP_TRANSFER_DND_LINUX_H_
#define VE_DESKTOP_TRANSFER_DND_LINUX_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstdint>
#include <map>
#include <memory>
#include <string>

#include "ve_engine_bridge_linux.h"
#include "ve_transfer_callbacks_linux.h"

namespace ve_transfer {

// Manages GTK3 (X11 + Wayland) inbound drop targets, Wayland pointer event caching,
// and outbound lazy gtk_drag_begin_with_coordinates transfers across all FlView windows.
class DndLinux {
 public:
  DndLinux(const EngineBridgeLinux* bridge, TransferCallbacksLinux* callbacks);
  ~DndLinux();

  void AttachView(int64_t view_id, FlView* view);
  void DetachView(int64_t view_id);
  void DetachAll();

  bool BeginOutboundDrag(int64_t view_id,
                         std::shared_ptr<TransferBatch> batch,
                         FlMethodCall* pending_call);

  bool HasActiveView(int64_t view_id) const;

 private:
  struct ViewState {
    int64_t view_id = 0;
    FlView* view = nullptr;
    DndLinux* owner = nullptr;
    gulong motion_sig = 0;
    gulong leave_sig = 0;
    gulong data_recv_sig = 0;
    gulong press_sig = 0;
    gulong ptr_motion_sig = 0;
    gulong release_sig = 0;
    gulong drag_data_get_sig = 0;
    gulong drag_end_sig = 0;
    gulong drag_failed_sig = 0;
    gulong destroy_sig = 0;
  };

  struct OutboundDragState {
    std::shared_ptr<TransferBatch> batch;
    FlMethodCall* pending_call = nullptr;
    GdkDragContext* context = nullptr;
    bool data_sent = false;
    bool realized_emitted = false;
  };

  static gboolean OnDragMotion(GtkWidget* widget,
                               GdkDragContext* context,
                               gint x,
                               gint y,
                               guint time,
                               gpointer user_data);
  static void OnDragLeave(GtkWidget* widget,
                          GdkDragContext* context,
                          guint time,
                          gpointer user_data);
  static void OnDragDataReceived(GtkWidget* widget,
                                 GdkDragContext* context,
                                 gint x,
                                 gint y,
                                 GtkSelectionData* sdata,
                                 guint info,
                                 guint time,
                                 gpointer user_data);

  static gboolean OnButtonPress(GtkWidget* widget, GdkEventButton* event, gpointer user_data);
  static gboolean OnPointerMotion(GtkWidget* widget, GdkEventMotion* event, gpointer user_data);
  static gboolean OnButtonRelease(GtkWidget* widget, GdkEventButton* event, gpointer user_data);

  static void OnDragDataGet(GtkWidget* widget,
                            GdkDragContext* context,
                            GtkSelectionData* sdata,
                            guint info,
                            guint time,
                            gpointer user_data);
  static void OnDragEnd(GtkWidget* widget, GdkDragContext* context, gpointer user_data);
  static gboolean OnDragFailed(GtkWidget* widget,
                               GdkDragContext* context,
                               GtkDragResult result,
                               gpointer user_data);
  static void OnWidgetDestroy(GtkWidget* widget, gpointer user_data);

  void CachePointerEvent(const GdkEvent* event, int64_t view_id, double x, double y);
  void ResolvePortalKeyAsync(int64_t view_id, double x, double y, const std::string& key);
  void FinishOutboundDrag(bool ok);

  const EngineBridgeLinux* bridge_;
  TransferCallbacksLinux* callbacks_;
  std::map<int64_t, std::unique_ptr<ViewState>> views_;

  GdkEvent* cached_pointer_event_ = nullptr;
  int64_t cached_event_view_id_ = -1;
  double cached_x_ = 0.0;
  double cached_y_ = 0.0;
  bool primary_button_down_ = false;

  std::unique_ptr<OutboundDragState> active_drag_;
};

}  // namespace ve_transfer

#endif  // VE_DESKTOP_TRANSFER_DND_LINUX_H_
