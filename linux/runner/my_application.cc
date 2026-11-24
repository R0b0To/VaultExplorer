#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;

  // The window the engine and the main widget tree live in. Not owned: GTK
  // owns it, and the weak pointer below clears this when it is destroyed.
  GtkWindow* main_window;

  // Answers the "vaultexplorer/window" calls the Dart side makes about the
  // main window (see lib/core/windowing/main_window_host.dart).
  FlMethodChannel* window_channel;

  // Whether closing the main window hides it instead of destroying it.
  //
  // The main window owns the Flutter engine and the widget tree that every
  // secondary window is drawn into, so it cannot go while one of them is open.
  // While the Dart side has a window that must outlive the main one it sets
  // this ("setHideOnClose"), and a close request then only hides the window.
  // The Dart side ends the app ("quitIfMainHidden") when the last such window
  // has closed.
  gboolean hide_main_on_close;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Sets the window icon (taskbar / Alt-Tab / title bar, mainly on X11) from
// <bundle>/data/app_icon.png, which linux/CMakeLists.txt installs next to the
// executable. If that file is missing (e.g. running the unbundled binary), fall
// back to a themed icon named after the application id, which is what an
// installed .desktop file / icon theme entry provides. Wayland shells ignore
// the window icon and take it from the .desktop file instead.
static void set_window_icon(GtkWindow* window) {
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
    g_autofree gchar* icon_path =
        g_build_filename(exe_dir, "data", "app_icon.png", nullptr);
    g_autoptr(GError) error = nullptr;
    if (gtk_window_set_icon_from_file(window, icon_path, &error)) {
      return;
    }
  }
  gtk_window_set_icon_name(window, APPLICATION_ID);
}

// Handles a request to close the main window (the close button, Alt+F4, the
// window manager's close). While another window depends on this one it is
// hidden instead of destroyed; returning TRUE stops GTK, and the Flutter
// embedder's own close handling, from going on to destroy it.
static gboolean main_window_delete_event_cb(GtkWidget* widget,
                                            GdkEvent* event,
                                            gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->hide_main_on_close) {
    return FALSE;
  }
  gtk_widget_hide(widget);
  return TRUE;
}

// Implements the "vaultexplorer/window" channel.
static void window_channel_cb(FlMethodChannel* channel,
                              FlMethodCall* method_call,
                              gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "setHideOnClose") == 0) {
    FlValue* enabled = nullptr;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      enabled = fl_value_lookup_string(args, "enabled");
    }
    self->hide_main_on_close = enabled != nullptr &&
                               fl_value_get_type(enabled) == FL_VALUE_TYPE_BOOL &&
                               fl_value_get_bool(enabled);
    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "revealMainWindow") == 0) {
    // Brings the main window back if it was hidden on close, without taking
    // the focus from the window the person is working in. A window that is
    // merely minimized or behind others is left alone.
    if (self->main_window != nullptr &&
        !gtk_widget_get_visible(GTK_WIDGET(self->main_window))) {
      gtk_window_set_focus_on_map(self->main_window, FALSE);
      gtk_widget_show(GTK_WIDGET(self->main_window));
      gtk_window_set_focus_on_map(self->main_window, TRUE);
    }
    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "quitIfMainHidden") == 0) {
    // The last window that could stand on its own has closed. A main window
    // that was hidden for its sake has no reason left to exist, so end the
    // app. A main window that is on screen means the person never closed it:
    // nothing to do.
    if (self->main_window == nullptr ||
        !gtk_widget_get_visible(GTK_WIDGET(self->main_window))) {
      self->hide_main_on_close = FALSE;
      g_application_quit(G_APPLICATION(self));
    }
    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send window channel response: %s", error->message);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  set_window_icon(window);

  // Connected before the Flutter view exists, so that this handler runs ahead
  // of any close handling the embedder attaches to the window later.
  self->main_window = window;
  g_object_add_weak_pointer(G_OBJECT(window),
                            reinterpret_cast<gpointer*>(&self->main_window));
  g_signal_connect(window, "delete-event",
                   G_CALLBACK(main_window_delete_event_cb), self);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "vaultexplorer");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "vaultexplorer");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlPluginRegistrar) window_registrar =
      fl_plugin_registry_get_registrar_for_plugin(FL_PLUGIN_REGISTRY(view),
                                                  "VaultExplorerWindow");
  g_autoptr(FlStandardMethodCodec) window_codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(window_registrar),
      "vaultexplorer/window", FL_METHOD_CODEC(window_codec));
  fl_method_channel_set_method_call_handler(self->window_channel,
                                            window_channel_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->window_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
