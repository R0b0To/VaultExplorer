# ─────────────────────────────────────────────────────────────────────────
# Image codecs for the native thumbnailer (imaging/thumb.cpp).
#
# Desktop engine only: on Android thumbnails come from BitmapFactory / ImageDecoder, so the Android build does
# not fetch, compile or link any of this. Every library is built from a pinned source, like the rest of the
# engine's dependencies.
#
#   libjpeg-turbo  JPEG decode (scaled IDCT: 1/2, 1/4, 1/8 size straight from the DCT) and JPEG encode. Its SIMD
#                  code needs NASM on x86 / x86-64; without it the CMake falls back to plain C (about 2-3x slower)
#                  instead of failing. Install NASM for the full speed (MSYS2: mingw-w64-ucrt-x86_64-nasm,
#                  Debian/Ubuntu: nasm).
#   libpng         PNG decode and encode. Built straight from its sources (no find_package(ZLIB)), against the
#                  zlib the engine already uses (VE_ZLIB_LIB / VE_ZLIB_INCLUDE_DIRS), with the CPU-specific filter
#                  optimisations off so the same file list builds on every architecture.
#   libwebp        WebP decode with scaling inside the decoder. Only `webpdecoder` is linked into the engine; the
#                  encoder (`webp`) is built only for the host test's fixtures.
#
# Defines: VE_JPEG_LIB, VE_PNG_LIB, VE_WEBP_DECODER_LIB (link these) and VE_IMAGING_INCLUDE_DIRS.
# ─────────────────────────────────────────────────────────────────────────
include(FetchContent)

# ── libjpeg-turbo ───────────────────────────────────────────────────────
# Its CMakeLists refuses to be add_subdirectory()'d ("Use ExternalProject_Add() instead"), so it is built as a
# separate little project at build time and picked up as an imported static library. The compiler / toolchain
# settings are forwarded so a cross build (MinGW from Linux, see scripts/toolchains) builds it the same way.
include(ExternalProject)
set(VE_JPEG_PREFIX ${CMAKE_CURRENT_BINARY_DIR}/libjpeg-turbo-install)
set(VE_JPEG_CMAKE_ARGS
    -DCMAKE_INSTALL_PREFIX=${VE_JPEG_PREFIX}
    -DCMAKE_INSTALL_LIBDIR=lib
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DENABLE_SHARED=OFF
    -DENABLE_STATIC=ON
    -DWITH_TURBOJPEG=OFF
    -DWITH_TOOLS=OFF   # also turns its regression tests off
    -DWITH_JAVA=OFF
    -DWITH_FUZZ=OFF)
if(CMAKE_BUILD_TYPE)
    list(APPEND VE_JPEG_CMAKE_ARGS -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})
else()
    list(APPEND VE_JPEG_CMAKE_ARGS -DCMAKE_BUILD_TYPE=Release)
endif()
foreach(VE_JPEG_VAR CMAKE_TOOLCHAIN_FILE CMAKE_C_COMPILER CMAKE_C_COMPILER_TARGET CMAKE_SYSTEM_NAME
                    CMAKE_SYSTEM_PROCESSOR CMAKE_RC_COMPILER CMAKE_MAKE_PROGRAM CMAKE_SYSROOT)
    if(DEFINED ${VE_JPEG_VAR} AND NOT "${${VE_JPEG_VAR}}" STREQUAL "")
        list(APPEND VE_JPEG_CMAKE_ARGS -D${VE_JPEG_VAR}=${${VE_JPEG_VAR}})
    endif()
endforeach()
set(VE_JPEG_LIBRARY_FILE ${VE_JPEG_PREFIX}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}jpeg${CMAKE_STATIC_LIBRARY_SUFFIX})
ExternalProject_Add(libjpeg_turbo_ep
    GIT_REPOSITORY https://github.com/libjpeg-turbo/libjpeg-turbo.git
    GIT_TAG        e352b02f794f701407b39af08576035ba3360d60 # 3.1.4
    UPDATE_COMMAND ""
    CMAKE_ARGS     ${VE_JPEG_CMAKE_ARGS}
    BUILD_BYPRODUCTS ${VE_JPEG_LIBRARY_FILE}
)
file(MAKE_DIRECTORY ${VE_JPEG_PREFIX}/include)  # an imported target's include dir must exist when configuring
add_library(ve_jpeg STATIC IMPORTED GLOBAL)
set_target_properties(ve_jpeg PROPERTIES
    IMPORTED_LOCATION ${VE_JPEG_LIBRARY_FILE}
    INTERFACE_INCLUDE_DIRECTORIES ${VE_JPEG_PREFIX}/include)
add_dependencies(ve_jpeg libjpeg_turbo_ep)
set(VE_JPEG_INCLUDE_DIRS ${VE_JPEG_PREFIX}/include)
set(VE_JPEG_LIB ve_jpeg)

# ── libpng (from source) ────────────────────────────────────────────────
FetchContent_Declare(
    libpng_upstream
    GIT_REPOSITORY https://github.com/glennrp/libpng.git
    GIT_TAG        cd952f49f95bb27154ae77dbb103032d95f6e580 # v1.6.59
    SOURCE_SUBDIR  ve-no-cmake  # fetch only: its CMakeLists would want find_package(ZLIB)
)
FetchContent_MakeAvailable(libpng_upstream)
set(VE_PNG_SRC_DIR ${libpng_upstream_SOURCE_DIR})
set(VE_PNG_GEN_DIR ${CMAKE_CURRENT_BINARY_DIR}/libpng-generated)
file(MAKE_DIRECTORY ${VE_PNG_GEN_DIR})
configure_file(${VE_PNG_SRC_DIR}/scripts/pnglibconf.h.prebuilt ${VE_PNG_GEN_DIR}/pnglibconf.h COPYONLY)
add_library(ve_png STATIC
    ${VE_PNG_SRC_DIR}/png.c
    ${VE_PNG_SRC_DIR}/pngerror.c
    ${VE_PNG_SRC_DIR}/pngget.c
    ${VE_PNG_SRC_DIR}/pngmem.c
    ${VE_PNG_SRC_DIR}/pngpread.c
    ${VE_PNG_SRC_DIR}/pngread.c
    ${VE_PNG_SRC_DIR}/pngrio.c
    ${VE_PNG_SRC_DIR}/pngrtran.c
    ${VE_PNG_SRC_DIR}/pngrutil.c
    ${VE_PNG_SRC_DIR}/pngset.c
    ${VE_PNG_SRC_DIR}/pngtrans.c
    ${VE_PNG_SRC_DIR}/pngwio.c
    ${VE_PNG_SRC_DIR}/pngwrite.c
    ${VE_PNG_SRC_DIR}/pngwtran.c
    ${VE_PNG_SRC_DIR}/pngwutil.c
)
target_include_directories(ve_png PUBLIC ${VE_PNG_SRC_DIR} ${VE_PNG_GEN_DIR} ${VE_ZLIB_INCLUDE_DIRS})
target_compile_definitions(ve_png PRIVATE
    PNG_ARM_NEON_OPT=0 PNG_INTEL_SSE_OPT=0 PNG_MIPS_MSA_OPT=0 PNG_POWERPC_VSX_OPT=0 PNG_LOONGARCH_LSX_OPT=0)
target_link_libraries(ve_png PUBLIC ${VE_ZLIB_LIB})
set(VE_PNG_LIB ve_png)

# ── libwebp ─────────────────────────────────────────────────────────────
FetchContent_Declare(
    libwebp_upstream
    GIT_REPOSITORY https://github.com/webmproject/libwebp.git
    GIT_TAG        4fa21912338357f89e4fd51cf2368325b59e9bd9 # v1.6.0
)
set(WEBP_BUILD_ANIM_UTILS OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_CWEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_DWEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_GIF2WEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_IMG2WEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_VWEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_WEBPINFO OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_LIBWEBPMUX OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_WEBPMUX OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_EXTRAS OFF CACHE BOOL "" FORCE)
set(WEBP_USE_THREAD OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(libwebp_upstream)
if(NOT TARGET webpdecoder)
    message(FATAL_ERROR "libwebp did not define the webpdecoder target")
endif()
set(VE_WEBP_INCLUDE_DIRS ${libwebp_upstream_SOURCE_DIR}/src)
set(VE_WEBP_DECODER_LIB webpdecoder)

set(VE_IMAGING_INCLUDE_DIRS ${VE_JPEG_INCLUDE_DIRS} ${VE_PNG_SRC_DIR} ${VE_PNG_GEN_DIR} ${VE_WEBP_INCLUDE_DIRS})
