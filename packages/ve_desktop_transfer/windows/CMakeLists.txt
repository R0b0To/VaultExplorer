cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "ve_desktop_transfer")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "ve_desktop_transfer_plugin")

add_library(${PLUGIN_NAME} SHARED
  "ve_desktop_transfer_plugin.cpp"
  "ve_engine_bridge_win.cpp"
  "ve_vault_stream.cpp"
  "ve_data_object.cpp"
  "ve_drop_target.cpp"
  "ve_clipboard_win.cpp"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE
  FLUTTER_PLUGIN_IMPL
  NOMINMAX
  WIN32_LEAN_AND_MEAN
  _CRT_SECURE_NO_WARNINGS)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  ole32
  shell32
  shlwapi
  advapi32)

set(ve_desktop_transfer_bundled_libraries
  ""
  PARENT_SCOPE
)
