# ─────────────────────────────────────────────────────────────────────────
# FFmpeg for native video thumbnails (imaging/video_thumb.cpp).
#
# Desktop engine only (Android uses MediaMetadataRetriever). A deliberately tiny build: libavformat + libavcodec +
# libswscale + libavutil, software decoders only, no network, no encoders, no filters, no audio, nothing
# autodetected from the system (so it never links a library the machine happens to have), LGPL 2.1+ (no --enable-gpl,
# no --enable-nonfree). The demuxers and decoders are the ones a video library actually holds: MP4/MOV, Matroska/WebM,
# AVI, MPEG-PS/TS, FLV, ASF, Ogg, IVF with H.264, HEVC, VP8, VP9, MPEG-4 part 2, MPEG-1/2, H.263, WMV/VC-1, MJPEG,
# Theora, ProRes. AV1 is not in it (FFmpeg's own AV1 decoder is hardware-only; software needs dav1d): the engine
# answers "unsupported" for AV1 and the desktop code falls back to its libmpv route for those, as it does for any
# container or codec outside this list.
#
# FFmpeg builds with its own ./configure + make, so it goes through ExternalProject (at build time, the compiler and
# cross-compilation settings forwarded). Needs a POSIX `make` (MSYS2: `make` and `diffutils`) -- and `nasm` for the
# x86 assembly, without which FFmpeg's configure stops, so it is passed --disable-x86asm when NASM is missing (slower
# decoding). When `make` itself is missing this file turns video thumbnails off with a warning and the engine builds
# and runs without them (ve_video_thumbnail then answers VE_ERR_UNSUPPORTED).
#
# Defines: VE_HAVE_FFMPEG (ON/OFF) and, when ON, VE_FFMPEG_LIBS (link these).
# ─────────────────────────────────────────────────────────────────────────
include(ExternalProject)

set(VE_HAVE_FFMPEG OFF)
find_program(VE_MAKE_PROGRAM NAMES gmake make)
if(NOT VE_MAKE_PROGRAM)
    message(WARNING "No `make` found: building WITHOUT native video thumbnails (the desktop app falls back to libmpv "
                    "for them, which is much slower). Install make (MSYS2: `pacman -S make diffutils`).")
    return()
endif()
if(CMAKE_CROSSCOMPILING AND NOT WIN32)
    message(WARNING "Cross-compiling for a non-Windows target: building WITHOUT native video thumbnails.")
    return()
endif()

set(VE_FFMPEG_PREFIX ${CMAKE_CURRENT_BINARY_DIR}/ffmpeg-install)
set(VE_FFMPEG_CONFIGURE_ARGS
    --prefix=${VE_FFMPEG_PREFIX}
    --disable-everything --disable-programs --disable-doc --disable-network --disable-autodetect --disable-debug
    --disable-avdevice --disable-avfilter --disable-swresample
    --disable-shared --enable-static --enable-pic
    --enable-avcodec --enable-avformat --enable-swscale
    --enable-demuxer=mov,matroska,avi,mpegts,mpegps,flv,asf,ogg,mpegvideo,m4v,h264,hevc,ivf
    --enable-decoder=h264,hevc,vp8,vp9,mpeg4,msmpeg4v1,msmpeg4v2,msmpeg4v3,mpeg1video,mpeg2video,h263,h263p,wmv1,wmv2,wmv3,vc1,mjpeg,theora,prores,flv
    --enable-parser=h264,hevc,vp8,vp9,mpeg4video,mpegvideo,h263,vc1,mjpeg)

if(CMAKE_CROSSCOMPILING)  # Windows from Linux (scripts/toolchains/mingw-w64-x86_64.cmake)
    get_filename_component(VE_FFMPEG_CC_NAME "${CMAKE_C_COMPILER}" NAME)
    # x86_64-w64-mingw32-gcc-posix (the toolchain file's compiler) -> x86_64-w64-mingw32-  (ar, nm, ranlib, strip, windres)
    string(REGEX REPLACE "(gcc|clang)(-[A-Za-z0-9.]+)?(\\.exe)?$" "" VE_FFMPEG_CROSS_PREFIX "${VE_FFMPEG_CC_NAME}")
    if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "^(aarch64|arm64|ARM64)$")
        set(VE_FFMPEG_ARCH aarch64)
    else()
        set(VE_FFMPEG_ARCH x86_64)
    endif()
    list(APPEND VE_FFMPEG_CONFIGURE_ARGS --enable-cross-compile --target-os=mingw32 --arch=${VE_FFMPEG_ARCH}
         --cross-prefix=${VE_FFMPEG_CROSS_PREFIX} --cc=${CMAKE_C_COMPILER})
else()
    list(APPEND VE_FFMPEG_CONFIGURE_ARGS --cc=${CMAKE_C_COMPILER})
    if(WIN32)  # MSYS2 (UCRT64) natively
        list(APPEND VE_FFMPEG_CONFIGURE_ARGS --target-os=mingw32)
    endif()
endif()
find_program(VE_NASM_PROGRAM NAMES nasm yasm)
if(NOT VE_NASM_PROGRAM AND "${CMAKE_SYSTEM_PROCESSOR}" MATCHES "^(x86_64|AMD64|amd64|i[3-6]86)$")
    message(WARNING "NASM not found: FFmpeg is built without its x86 assembly (video thumbnails decode slower). "
                    "Install nasm for full speed.")
    list(APPEND VE_FFMPEG_CONFIGURE_ARGS --disable-x86asm)
endif()

cmake_host_system_information(RESULT VE_FFMPEG_JOBS QUERY NUMBER_OF_LOGICAL_CORES)
if(NOT VE_FFMPEG_JOBS OR VE_FFMPEG_JOBS LESS 1)
    set(VE_FFMPEG_JOBS 2)
endif()

set(VE_FFMPEG_LIB_FILES "")
foreach(VE_FF_LIB avformat avcodec swscale avutil)
    list(APPEND VE_FFMPEG_LIB_FILES ${VE_FFMPEG_PREFIX}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}${VE_FF_LIB}${CMAKE_STATIC_LIBRARY_SUFFIX})
endforeach()

ExternalProject_Add(ffmpeg_ep
    GIT_REPOSITORY https://github.com/FFmpeg/FFmpeg.git
    GIT_TAG        1041abdc962f4cc4f394aa8de9dc5236c0c3b9e7 # n8.1.3
    UPDATE_COMMAND ""
    CONFIGURE_COMMAND <SOURCE_DIR>/configure ${VE_FFMPEG_CONFIGURE_ARGS}
    BUILD_COMMAND  ${VE_MAKE_PROGRAM} -j${VE_FFMPEG_JOBS}
    INSTALL_COMMAND ${VE_MAKE_PROGRAM} install
    BUILD_BYPRODUCTS ${VE_FFMPEG_LIB_FILES}
)
file(MAKE_DIRECTORY ${VE_FFMPEG_PREFIX}/include)  # an imported target's include dir must exist when configuring
foreach(VE_FF_LIB avformat avcodec swscale avutil)
    add_library(ve_ff_${VE_FF_LIB} STATIC IMPORTED GLOBAL)
    set_target_properties(ve_ff_${VE_FF_LIB} PROPERTIES
        IMPORTED_LOCATION ${VE_FFMPEG_PREFIX}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}${VE_FF_LIB}${CMAKE_STATIC_LIBRARY_SUFFIX}
        INTERFACE_INCLUDE_DIRECTORIES ${VE_FFMPEG_PREFIX}/include)
    add_dependencies(ve_ff_${VE_FF_LIB} ffmpeg_ep)
endforeach()
# Static link order: a library after the ones it uses.
target_link_libraries(ve_ff_avformat INTERFACE ve_ff_avcodec)
target_link_libraries(ve_ff_avcodec INTERFACE ve_ff_swscale ve_ff_avutil)
target_link_libraries(ve_ff_swscale INTERFACE ve_ff_avutil)
if(WIN32)
    target_link_libraries(ve_ff_avutil INTERFACE bcrypt)  # av_get_random_seed
else()
    find_package(Threads REQUIRED)
    target_link_libraries(ve_ff_avutil INTERFACE Threads::Threads m)
endif()
set(VE_FFMPEG_LIBS ve_ff_avformat)
set(VE_HAVE_FFMPEG ON)
