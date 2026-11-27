#ifndef FLUTTER_PLUGIN_VE_DESKTOP_TRANSFER_PLUGIN_H_
#define FLUTTER_PLUGIN_VE_DESKTOP_TRANSFER_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _VeDesktopTransferPlugin VeDesktopTransferPlugin;
typedef struct {
  GObjectClass parent_class;
} VeDesktopTransferPluginClass;

#define VE_TYPE_DESKTOP_TRANSFER_PLUGIN (ve_desktop_transfer_plugin_get_type())
#define VE_DESKTOP_TRANSFER_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), VE_TYPE_DESKTOP_TRANSFER_PLUGIN, \
                              VeDesktopTransferPlugin))

FLUTTER_PLUGIN_EXPORT GType ve_desktop_transfer_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void ve_desktop_transfer_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_VE_DESKTOP_TRANSFER_PLUGIN_H_
