cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "ve_desktop_transfer")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "ve_desktop_transfer_plugin")

add_library(${PLUGIN_NAME} SHARED
  "ve_desktop_transfer_plugin.cc"
  "ve_engine_bridge_linux.cc"
  "ve_dnd_linux.cc"
  "ve_clipboard_linux.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  PkgConfig::GTK
  ${CMAKE_DL_LIBS}
  pthread)

set(ve_desktop_transfer_bundled_libraries
  ""
  PARENT_SCOPE
)
