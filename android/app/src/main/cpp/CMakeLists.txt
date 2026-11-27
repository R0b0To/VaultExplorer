cmake_minimum_required(VERSION 3.18.0)

project("vaultexplorer")

# Desktop mode (Linux / Windows): build the engine as a plain shared library with a
# C ABI (ffi/ve_engine.h) for dart:ffi, instead of the Android JNI library. The
# engine core is shared; only the platform glue differs:
#   Android: jni/*.cpp                    (JNI bridges + JVM callbacks)
#   Desktop: ffi/ve_engine.cpp + ffi/ve_callbacks.cpp (no JNI or NDK header is needed any more: logging goes
#            through platform/engine_log.h, callbacks through platform/engine_hooks.h; ffi/compat/ holds only
#            the Windows POSIX shims).
# Off by default, so the Android build is exactly what it was.
option(VAULTEXPLORER_DESKTOP "Build the desktop (dart:ffi) engine library instead of the Android JNI library" OFF)
if(VAULTEXPLORER_DESKTOP)
    # Every static dependency (mbedTLS, BoringSSL, libarchive, e2fsprogs bits, ...) is linked
    # into one shared library, so it must all be PIC. The NDK toolchain does this implicitly;
    # a desktop toolchain does not.
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif()

# Strip CMAKE_BINARY_DIR (which contains .cxx/release/<hash>) from compiled C/C++ binaries
add_compile_options("-ffile-prefix-map=${CMAKE_BINARY_DIR}=/build_tree")
add_compile_options("-ffile-prefix-map=${CMAKE_SOURCE_DIR}=/source_tree")

# 1. Download mbedTLS (Encryption Engine)
include(FetchContent)
FetchContent_Declare(
        mbedtls
        GIT_REPOSITORY https://github.com/Mbed-TLS/mbedtls.git
        GIT_TAG        068ff080b369adfac81509f9b57b2afabaf82dc5 # v3.6.7 (was v3.6.0; same LTS branch, 7 patch releases of security/bugfixes)
)
set(ENABLE_TESTING OFF CACHE BOOL "Disable mbedtls tests")
set(ENABLE_PROGRAMS OFF CACHE BOOL "Disable mbedtls programs")
FetchContent_MakeAvailable(mbedtls)


# Fetch BoringSSL via GitHub ZIP archive (prevents shallow clone failures with commit SHAs)
FetchContent_Declare(
    boringssl
    URL https://github.com/google/boringssl/archive/ef0c0723156ff8014feb6b6789afe1e43d7e8710.zip
)

# Find Git's built-in Perl on Windows so BoringSSL builds ARM64 assembly (AESE + PMULL)
if(WIN32 AND NOT PERL_EXECUTABLE)
    find_program(PERL_EXECUTABLE perl HINTS "C:/Program Files/Git/usr/bin" "C:/Program Files/Git/bin")
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

# For x86/x86_64, disable ASM if NASM isn't present to avoid build failure
if(ANDROID_ABI MATCHES "x86" OR (VAULTEXPLORER_DESKTOP AND WIN32))
    set(OPENSSL_NO_ASM ON CACHE BOOL "" FORCE)
else()
    set(OPENSSL_NO_ASM OFF CACHE BOOL "" FORCE)
endif()

FetchContent_MakeAvailable(boringssl)


# AVIF decoding is only reachable through jni/avif_bridge.cpp today, so the desktop
# build skips libgav1 + libavif entirely.
if(NOT VAULTEXPLORER_DESKTOP)
    # ── AVIF Decoder (libgav1 + libavif) ──
    FetchContent_Declare(
        libgav1
        GIT_REPOSITORY https://chromium.googlesource.com/codecs/libgav1
        GIT_TAG        c05bf9be660cf170d7c26bd06bb42b3322180e58
    )
    set(LIBGAV1_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
    set(LIBGAV1_ENABLE_EXAMPLES OFF CACHE BOOL "" FORCE)
    if(NOT ANDROID)
        # Without this, libgav1's own CMakeLists.txt requires Abseil for the
        # core library (not just its tests/examples, which are already off
        # above) -- LIBGAV1_THREADPOOL_USE_STD_MUTEX defaults to 1 (std::mutex,
        # no Abseil) only on Android & iOS, and to 0 otherwise, per libgav1's
        # README. That default-0 case is exactly what breaks the "Native
        # host-side tests (no NDK)" CI job: it configures this same
        # CMakeLists.txt without the Android toolchain, so libgav1 falls back
        # to absl::Mutex and fails configure with "Abseil not found" -- even
        # though none of the host tests touch libgav1/AVIF decoding at all.
        # Gated on NOT ANDROID so the real Android build never sets this and
        # keeps getting libgav1's own default-1 behavior untouched -- setting
        # it unconditionally previously broke the real Android/NDK build.
        set(LIBGAV1_THREADPOOL_USE_STD_MUTEX "1" CACHE STRING "" FORCE)
    endif()
    FetchContent_MakeAvailable(libgav1)

    if(TARGET libgav1_static)
        target_include_directories(libgav1_static PUBLIC ${libgav1_SOURCE_DIR}/src)
        if(NOT TARGET libgav1::libgav1)
            add_library(libgav1::libgav1 ALIAS libgav1_static)
        endif()
        set(libgav1_FOUND TRUE CACHE BOOL "" FORCE)
    endif()

    FetchContent_Declare(
        libavif
        GIT_REPOSITORY https://github.com/AOMediaCodec/libavif.git
        GIT_TAG        c5240fc79fe5c2407e10afd35f5505ef6333ea49
    )
    set(AVIF_CODEC_LIBGAV1 SYSTEM CACHE STRING "" FORCE)
    set(AVIF_LIBYUV LOCAL CACHE STRING "" FORCE)
    set(AVIF_BUILD_APPS OFF CACHE BOOL "" FORCE)
    set(AVIF_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(libavif)
endif()

# Enable ARMv8 Cryptography Extensions ONLY for ARM targets
if(ANDROID_ABI STREQUAL "arm64-v8a")
    target_compile_options(mbedcrypto PRIVATE -march=armv8-a+crypto+sha2 -Wno-macro-redefined)
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    target_compile_options(mbedcrypto PRIVATE -mfpu=neon)
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT VAULTEXPLORER_DESKTOP)  # ZXing is only used by jni/qr_bridge.cpp
    # 1z. ZXing-C++ (Lightweight offline barcode/QR decoder)
    FetchContent_Declare(
        zxing_cpp
        GIT_REPOSITORY https://github.com/zxing-cpp/zxing-cpp.git
        GIT_TAG        v3.1.1
    )
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(ZXING_READERS ON CACHE BOOL "" FORCE)
    set(ZXING_WRITERS OFF CACHE BOOL "" FORCE)
    set(ZXING_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(ZXING_C_API OFF CACHE BOOL "" FORCE)
    set(ZXING_UNIT_TESTS OFF CACHE BOOL "" FORCE)
    set(ZXING_BLACKBOX_TESTS OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(zxing_cpp)
endif()

# 1a. Archive engine (libarchive + its compression filters) -- see
# archive_deps.cmake's file-level comment for what's vendored vs. reused
# from the NDK/BoringSSL, and for a caveat on what could/couldn't be
# verified without an actual Android build.
if(VAULTEXPLORER_DESKTOP AND WIN32)
    # The NDK and a Linux host provide libz; a MinGW toolchain has none, so vendor it. libarchive's own
    # find_package(ZLIB) is pre-seeded below so it uses this copy instead of searching.
    FetchContent_Declare(
            zlib_upstream
            GIT_REPOSITORY https://github.com/madler/zlib.git
            GIT_TAG        v1.3.1
            GIT_SHALLOW    TRUE
    )
    set(ZLIB_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(SKIP_INSTALL_ALL ON CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(zlib_upstream)
    set(VE_ZLIB_LIB zlibstatic)
    set(VE_ZLIB_INCLUDE_DIRS ${zlib_upstream_SOURCE_DIR} ${zlib_upstream_BINARY_DIR})
    set(ZLIB_FOUND TRUE CACHE BOOL "" FORCE)
    set(ZLIB_INCLUDE_DIR ${zlib_upstream_SOURCE_DIR} CACHE PATH "" FORCE)
    set(ZLIB_INCLUDE_DIRS "${VE_ZLIB_INCLUDE_DIRS}" CACHE STRING "" FORCE)
    set(ZLIB_LIBRARY zlibstatic CACHE STRING "" FORCE)
    set(ZLIB_LIBRARIES zlibstatic CACHE STRING "" FORCE)
    set(HAVE_LIBZ 1 CACHE BOOL "" FORCE)
    set(HAVE_ZLIB_H 1 CACHE BOOL "" FORCE)
else()
    set(VE_ZLIB_LIB z)
    set(VE_ZLIB_INCLUDE_DIRS "")
endif()

include(${CMAKE_CURRENT_SOURCE_DIR}/archive_deps.cmake)

# 2. Download ChaN's FatFs (Filesystem Engine)
FetchContent_Declare(
        fatfs
        GIT_REPOSITORY https://github.com/stm32duino/FatFs.git
        GIT_TAG        cef1acad37d563e6b7dfd1c4fd3d48e7ff348947 # 4.0.4
)
FetchContent_MakeAvailable(fatfs)

# 3. Download Tuxera NTFS-3G (NTFS Filesystem Engine)
#
# Patched with filesystems/patches/ntfs-3g-lookup-by-mbsname.patch. Without it,
# anything touching a reparse point fails on volumes mounted via
# ntfs_device_mount() (no lookup cache): ntfs_create_symlink() returns NULL with
# EINVAL, i.e. symbolic links cannot be created on NTFS. The full explanation is
# in filesystems/patches/apply_ntfs3g_patches.cmake. The script is idempotent
# and fails configure if the patch stops applying (e.g. after a version bump).
#
# The patch files are configure dependencies so an incremental build (Ninja, as
# used by Gradle) notices an edited patch instead of keeping the old tree.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/filesystems/patches/ntfs-3g-lookup-by-mbsname.patch"
    "${CMAKE_CURRENT_SOURCE_DIR}/filesystems/patches/apply_ntfs3g_patches.cmake")
FetchContent_Declare(
        ntfs3g
        GIT_REPOSITORY https://github.com/tuxera/ntfs-3g.git
        GIT_TAG        d327833ec1d5eb1358b6f2c37139f10a3460944d
        PATCH_COMMAND  ${CMAKE_COMMAND}
                       -DPATCH_FILE=${CMAKE_CURRENT_SOURCE_DIR}/filesystems/patches/ntfs-3g-lookup-by-mbsname.patch
                       -P ${CMAKE_CURRENT_SOURCE_DIR}/filesystems/patches/apply_ntfs3g_patches.cmake
)
FetchContent_MakeAvailable(ntfs3g)

# Re-apply when the patch changes, even inside an existing .cxx build tree
# (PATCH_COMMAND only runs when the dependency is first populated).
execute_process(
    COMMAND ${CMAKE_COMMAND}
            -DPATCH_FILE=${CMAKE_CURRENT_SOURCE_DIR}/filesystems/patches/ntfs-3g-lookup-by-mbsname.patch
            -P ${CMAKE_CURRENT_SOURCE_DIR}/filesystems/patches/apply_ntfs3g_patches.cmake
    WORKING_DIRECTORY ${ntfs3g_SOURCE_DIR}
    RESULT_VARIABLE ntfs3g_patch_res
)
if(NOT ntfs3g_patch_res EQUAL 0)
    message(FATAL_ERROR "Failed to patch ntfs-3g sources")
endif()

# 3a. e2fsprogs/libext2fs
FetchContent_Declare(
        e2fsprogs
        GIT_REPOSITORY https://github.com/tytso/e2fsprogs.git
        GIT_TAG        7ee1d505ef3b37831215f490411f346fe57e9053 # v1.47.4
)
FetchContent_GetProperties(e2fsprogs)
if(NOT e2fsprogs_POPULATED)
    FetchContent_Populate(e2fsprogs)
endif()

# 3a-bde. BitLocker support
include(${CMAKE_CURRENT_SOURCE_DIR}/bitlocker_deps.cmake)
set(E2FS_SRC_DIR ${e2fsprogs_SOURCE_DIR})
set(E2FS_EXT2FS_DIR ${E2FS_SRC_DIR}/lib/ext2fs)
set(E2FS_GENERATED_DIR ${CMAKE_CURRENT_BINARY_DIR}/e2fs-generated)
file(MAKE_DIRECTORY ${E2FS_GENERATED_DIR}/ext2fs ${E2FS_GENERATED_DIR}/uuid)

set(ASM_TYPES_HEADER "")
set(SIZEOF_INT 4)
set(SIZEOF_SHORT 2)
set(SIZEOF_LONG ${CMAKE_SIZEOF_VOID_P})
set(SIZEOF_LONG_LONG 8)
set(PUBLIC_CONFIG_HEADER "")
configure_file(${E2FS_EXT2FS_DIR}/ext2_types.h.in
               ${E2FS_GENERATED_DIR}/ext2fs/ext2_types.h @ONLY)
configure_file(${E2FS_SRC_DIR}/lib/uuid/uuid.h.in
               ${E2FS_GENERATED_DIR}/uuid/uuid.h @ONLY)
set(datadir /usr/share)
set(root_sysconfdir /etc)
configure_file(${E2FS_SRC_DIR}/lib/dirpaths.h.in
               ${CMAKE_CURRENT_BINARY_DIR}/dirpaths.h @ONLY)

file(READ ${E2FS_EXT2FS_DIR}/ext2_err.et.in E2FS_ERROR_TABLE)
string(REGEX MATCHALL "ec[ \t]+[A-Z0-9_]+," E2FS_ERROR_ENTRIES "${E2FS_ERROR_TABLE}")
set(E2FS_ERROR_HEADER "/* Generated from e2fsprogs ext2_err.et.in. */\n#include <et/com_err.h>\n")
set(E2FS_ERROR_INDEX 0)
foreach(E2FS_ERROR_ENTRY IN LISTS E2FS_ERROR_ENTRIES)
    string(REGEX REPLACE "ec[ \t]+([A-Z0-9_]+)," "\\1" E2FS_ERROR_NAME "${E2FS_ERROR_ENTRY}")
    math(EXPR E2FS_ERROR_VALUE "2133571328 + ${E2FS_ERROR_INDEX}")
    string(APPEND E2FS_ERROR_HEADER "#define ${E2FS_ERROR_NAME} (${E2FS_ERROR_VALUE}L)\n")
    math(EXPR E2FS_ERROR_INDEX "${E2FS_ERROR_INDEX} + 1")
endforeach()
string(APPEND E2FS_ERROR_HEADER "extern const struct error_table et_ext2_error_table;\nvoid initialize_ext2_error_table(void);\nvoid initialize_ext2_error_table_r(struct et_list **list);\n#define ERROR_TABLE_BASE_ext2 (2133571328L)\n#define init_ext2_err_tbl initialize_ext2_error_table\n#define ext2_err_base ERROR_TABLE_BASE_ext2\n")
file(WRITE ${E2FS_GENERATED_DIR}/ext2fs/ext2_err.h "${E2FS_ERROR_HEADER}")
file(WRITE ${E2FS_GENERATED_DIR}/ext2_err.c [=[
#include <stdlib.h>
#include <et/com_err.h>
static const char * const text[] = { "e2fsprogs ext2/ext3/ext4 error", 0 };
struct et_list { struct et_list *next; const struct error_table *table; };
extern struct et_list *_et_list;
const struct error_table et_ext2_error_table = { text, 2133571328L, 1 };
static struct et_list link = { 0, 0 };
void initialize_ext2_error_table_r(struct et_list **list) {
    struct et_list *et, **end;
    for (end = list, et = *list; et; end = &et->next, et = et->next)
        if (et->table->msgs == text) return;
    et = (struct et_list *) malloc(sizeof(*et));
    if (!et) { if (link.table) return; et = &link; }
    et->table = &et_ext2_error_table; et->next = 0; *end = et;
}
void initialize_ext2_error_table(void) { initialize_ext2_error_table_r(&_et_list); }
]=])

file(WRITE ${E2FS_EXT2FS_DIR}/crc32c_table.h [=[
/* Generated by VaultExplorer's Android CMake build. */
static const uint32_t crc32table_be[1][256] = {{ 0 }};
static const uint32_t crc32ctable_le[1][256] = {{ 0 }};
]=])

file(GLOB E2FS_EXT2FS_SOURCES ${E2FS_EXT2FS_DIR}/*.c)
list(SORT E2FS_EXT2FS_SOURCES COMPARE STRING)
foreach(E2FS_SOURCE IN LISTS E2FS_EXT2FS_SOURCES)
    get_filename_component(E2FS_SOURCE_NAME ${E2FS_SOURCE} NAME)
    if(E2FS_SOURCE_NAME MATCHES "^(tst_|test_io|tdbtool|bmove|brel_ma|irel_ma|dosio|nt_io|windows_io|write_bb_file|imager|flushb|unix_io|finddev|getsize|getsectsize|qcow2|sparse_io|undo_io|read_bb_file|tdb|gen_crc32ctable)")
        list(REMOVE_ITEM E2FS_EXT2FS_SOURCES ${E2FS_SOURCE})
    endif()
endforeach()
add_library(e2fs_com_err STATIC
        ${E2FS_SRC_DIR}/lib/et/error_message.c
        ${E2FS_SRC_DIR}/lib/et/et_name.c
        ${E2FS_SRC_DIR}/lib/et/init_et.c
        ${E2FS_SRC_DIR}/lib/et/com_err.c
        ${E2FS_SRC_DIR}/lib/et/com_right.c)
add_library(e2fs_uuid STATIC
        ${E2FS_SRC_DIR}/lib/uuid/clear.c
        ${E2FS_SRC_DIR}/lib/uuid/compare.c
        ${E2FS_SRC_DIR}/lib/uuid/copy.c
        ${E2FS_SRC_DIR}/lib/uuid/gen_uuid.c
        ${E2FS_SRC_DIR}/lib/uuid/isnull.c
        ${E2FS_SRC_DIR}/lib/uuid/pack.c
        ${E2FS_SRC_DIR}/lib/uuid/parse.c
        ${E2FS_SRC_DIR}/lib/uuid/unpack.c
        ${E2FS_SRC_DIR}/lib/uuid/unparse.c
        ${E2FS_SRC_DIR}/lib/uuid/uuid_time.c)
# resize2fs's engine (resize_fs): grows an ext2/3/4 file system in place -- see extGrowToFit in
# filesystems/ext_backend.cpp. Only resize2fs.c and extent.c are used; resource_track.c (sbrk/getrusage
# statistics) is replaced by the no-op glue, and main.c/online.c/sim_progress.c are CLI-only.
add_library(e2fs_ext2fs STATIC ${E2FS_EXT2FS_SOURCES}
        ${E2FS_GENERATED_DIR}/ext2_err.c
        ${E2FS_SRC_DIR}/resize/resize2fs.c
        ${E2FS_SRC_DIR}/resize/extent.c
        ${CMAKE_CURRENT_SOURCE_DIR}/filesystems/ext_resize_glue.c)
foreach(E2FS_TARGET e2fs_com_err e2fs_uuid e2fs_ext2fs)
    target_include_directories(${E2FS_TARGET} PRIVATE
            ${CMAKE_CURRENT_BINARY_DIR} ${E2FS_GENERATED_DIR}
            ${E2FS_SRC_DIR}/lib ${E2FS_SRC_DIR}/lib/et
            ${E2FS_SRC_DIR}/lib/uuid ${E2FS_EXT2FS_DIR})
    set(E2FS_DEFINITIONS
            HAVE_CONFIG_H HAVE_SYS_TYPES_H HAVE_SYS_STAT_H HAVE_UNISTD_H
            HAVE_STDLIB_H HAVE_STRING_H HAVE_ERRNO_H HAVE_INTTYPES_H
            HAVE_SNPRINTF HAVE_STRCASECMP HAVE_STRDUP HAVE_STRNLEN
            HAVE_PREAD HAVE_PWRITE HAVE_PREAD64 HAVE_PWRITE64
            HAVE_LINUX_TYPES_H HAVE_SYS_TIME_H HAVE_GETPAGESIZE
            CRC_LE_BITS=1 CRC_BE_BITS=1 DISABLE_BACKTRACE _GNU_SOURCE)
    if(WIN32)
        # No <linux/types.h> and no getpagesize() on a Windows C runtime (e2fsprogs falls back to constants).
        list(REMOVE_ITEM E2FS_DEFINITIONS HAVE_LINUX_TYPES_H HAVE_GETPAGESIZE)
        target_include_directories(${E2FS_TARGET} BEFORE PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ffi/compat_win)
        # getuid() & co. (gen_uuid.c, getenv.c) -- declared, not implicitly guessed (an error from GCC 14 on)
        target_compile_options(${E2FS_TARGET} PRIVATE
                "$<$<COMPILE_LANGUAGE:C>:SHELL:-include ${CMAKE_CURRENT_SOURCE_DIR}/ffi/compat/ve_win_types.h>")
    endif()
    target_compile_definitions(${E2FS_TARGET} PRIVATE ${E2FS_DEFINITIONS})
endforeach()
target_include_directories(e2fs_ext2fs PRIVATE ${E2FS_SRC_DIR}/resize)
target_link_libraries(e2fs_ext2fs PRIVATE e2fs_com_err e2fs_uuid)

# 3e. cJSON
FetchContent_Declare(
        cjson
        GIT_REPOSITORY https://github.com/DaveGamble/cJSON.git
        GIT_TAG        acc76239bee01d8e9c858ae2cab296704e52d916 # v1.7.18
)
set(ENABLE_CJSON_TEST OFF CACHE BOOL "Disable cJSON tests" FORCE)
set(ENABLE_CJSON_UNINSTALL OFF CACHE BOOL "Disable cJSON uninstall target" FORCE)
set(ENABLE_CUSTOM_COMPILER_FLAGS OFF CACHE BOOL "Disable cJSON custom compiler flags" FORCE)
set(BUILD_SHARED_AND_STATIC_LIBS OFF CACHE BOOL "Build only static cJSON" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Disable shared cJSON" FORCE)
# cJSON v1.7.18 declares cmake_minimum_required(VERSION 3.0), which CMake 4.x
# (what ubuntu-latest CI now ships) rejects outright. Let it configure under the
# 3.5 policy floor; the variable is ignored by older CMake and scoped to this call.
set(_vexp_saved_policy_min "${CMAKE_POLICY_VERSION_MINIMUM}")
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
FetchContent_MakeAvailable(cjson)
set(CMAKE_POLICY_VERSION_MINIMUM "${_vexp_saved_policy_min}")

# 3b. Generate config.h
set(CONFIG_H_CONTENT "
#ifndef CONFIG_H
#define CONFIG_H

#define HAVE_MALLOC 1
#define HAVE_REALLOC 1
#define HAVE_MEMSET 1
#define HAVE_MEMMOVE 1
#define HAVE_STRDUP 1
#define HAVE_STRCHR 1
#define HAVE_STRTOL 1
#define HAVE_STRTOULL 1
#define HAVE_GETTIMEOFDAY 1
#define HAVE_SYS_TIME_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDDEF_H 1
#define HAVE_SYS_IOCTL_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
#define HAVE_FCNTL_H 1
#define HAVE_ERRNO_H 1
#define HAVE_STRING_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STDIO_H 1
#define HAVE_LIMITS_H 1
#define HAVE_GETOPT_H 1
#define HAVE_STDARG_H 1
#define HAVE_WCHAR_H 1
#define HAVE_WCTYPE_H 1
#define HAVE_LOCALE_H 1
#define HAVE_UTIMENSAT 1
#define HAVE_SYS_SYSMACROS_H 1
#define HAVE_TIME_H 1
#define HAVE_CTYPE_H 1
#define HAVE_FFS 1

#ifdef HAVE_SYS_SYSMACROS_H
#include <sys/sysmacros.h>
#endif

#ifndef major
#define major(dev) ((int)(((dev) >> 8) & 0xff))
#endif
#ifndef minor
#define minor(dev) ((int)((dev) & 0xff))
#endif
#ifndef makedev
#define makedev(maj, min) ( (((maj) & 0xfffff000ULL) << 32) | (((maj) & 0xfffULL) << 8) | (((min) & 0xfffff000ULL) << 12) | ((min) & 0xfffULL) )
#endif

#ifndef HDIO_GETGEO
#define HDIO_GETGEO 0x301
#endif

struct hd_geometry {
    unsigned char heads;
    unsigned char sectors;
    unsigned short cylinders;
    unsigned long start;
};

#endif
")
if(WIN32)
    # MinGW's C runtime has no <sys/sysmacros.h> (major/minor/makedev are defined just below) and no utimensat.
    string(REPLACE "#define HAVE_SYS_SYSMACROS_H 1\n" "" CONFIG_H_CONTENT "${CONFIG_H_CONTENT}")
    string(REPLACE "#define HAVE_UTIMENSAT 1\n" "" CONFIG_H_CONTENT "${CONFIG_H_CONTENT}")
endif()
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/config.h "${CONFIG_H_CONTENT}")

# 3c. VeraCrypt crypto primitives
FetchContent_Declare(
        veracrypt
        GIT_REPOSITORY https://github.com/veracrypt/VeraCrypt.git
        GIT_TAG        d26216c294fdfb090ee856f6195c294176defa1d # VeraCrypt_1.26.29
)
FetchContent_GetProperties(veracrypt)
if(NOT veracrypt_POPULATED)
    FetchContent_Populate(veracrypt)
endif()

set(VC_SRC_DIR ${veracrypt_SOURCE_DIR}/src)
set(VC_CRYPTO_DIR ${VC_SRC_DIR}/Crypto)
set(VC_COMMON_DIR ${VC_SRC_DIR}/Common)
set(VC_ARGON2_DIR ${VC_CRYPTO_DIR}/Argon2)

set_source_files_properties(${VC_CRYPTO_DIR}/cpu.c PROPERTIES
        COMPILE_OPTIONS "-fgnu89-inline")

# 3d. NTFS-3G
set(NTFS_3G_SRC_DIR ${ntfs3g_SOURCE_DIR}/libntfs-3g)
set(NTFS_3G_SOURCES
    ${NTFS_3G_SRC_DIR}/acls.c
    ${NTFS_3G_SRC_DIR}/attrib.c
    ${NTFS_3G_SRC_DIR}/attrlist.c
    ${NTFS_3G_SRC_DIR}/bitmap.c
    ${NTFS_3G_SRC_DIR}/bootsect.c
    ${NTFS_3G_SRC_DIR}/cache.c          
    ${NTFS_3G_SRC_DIR}/collate.c
    ${NTFS_3G_SRC_DIR}/compat.c
    ${NTFS_3G_SRC_DIR}/compress.c
    ${NTFS_3G_SRC_DIR}/debug.c
    ${NTFS_3G_SRC_DIR}/device.c
    ${NTFS_3G_SRC_DIR}/dir.c
    ${NTFS_3G_SRC_DIR}/ea.c             
    ${NTFS_3G_SRC_DIR}/efs.c            
    ${NTFS_3G_SRC_DIR}/index.c
    ${NTFS_3G_SRC_DIR}/inode.c
    ${NTFS_3G_SRC_DIR}/lcnalloc.c
    ${NTFS_3G_SRC_DIR}/logfile.c
    ${NTFS_3G_SRC_DIR}/logging.c
    ${NTFS_3G_SRC_DIR}/mft.c
    ${NTFS_3G_SRC_DIR}/misc.c
    ${NTFS_3G_SRC_DIR}/mst.c
    ${NTFS_3G_SRC_DIR}/object_id.c      
    ${NTFS_3G_SRC_DIR}/reparse.c
    ${NTFS_3G_SRC_DIR}/runlist.c
    ${NTFS_3G_SRC_DIR}/security.c
    ${NTFS_3G_SRC_DIR}/unistr.c
    ${NTFS_3G_SRC_DIR}/volume.c
    ${NTFS_3G_SRC_DIR}/unix_io.c
    ${NTFS_3G_SRC_DIR}/xattrs.c         
    ${ntfs3g_SOURCE_DIR}/ntfsprogs/attrdef.c
    ${ntfs3g_SOURCE_DIR}/ntfsprogs/boot.c
    ${ntfs3g_SOURCE_DIR}/ntfsprogs/cluster.c
    ${ntfs3g_SOURCE_DIR}/ntfsprogs/sd.c
    ${ntfs3g_SOURCE_DIR}/ntfsprogs/utils.c
)

# Argon2 SIMD sources for x86 / x86_64. The reference dispatcher (ref.c) calls
# fill_segment_sse2/avx2 whenever the *compiler* targets x86, so a desktop x86 build needs
# them exactly like an Android x86 build does (ARM desktop builds fall back to ref.c).
set(ARGON2_SIMD_SOURCES)
set(VE_X86_TARGET OFF)
if(ANDROID_ABI MATCHES "x86")
    set(VE_X86_TARGET ON)
elseif(VAULTEXPLORER_DESKTOP AND CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86|X86|AMD64|amd64|i[3-6]86)")
    set(VE_X86_TARGET ON)
endif()
if(VE_X86_TARGET)
    set(ARGON2_SIMD_SOURCES
        ${VC_ARGON2_DIR}/src/opt_sse2.c
        ${VC_ARGON2_DIR}/src/opt_avx2.c
    )
    set_source_files_properties(${VC_ARGON2_DIR}/src/opt_sse2.c PROPERTIES COMPILE_FLAGS "-msse2")
    set_source_files_properties(${VC_ARGON2_DIR}/src/opt_avx2.c PROPERTIES COMPILE_FLAGS "-mavx2")
endif()

set(MKNTFS_EMBEDDED_SOURCE ${CMAKE_CURRENT_BINARY_DIR}/mkntfs_embedded.c)
set(NTFS3G_MKNTFS_SOURCE ${ntfs3g_SOURCE_DIR}/ntfsprogs/mkntfs.c)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/filesystems/mkntfs_embedded.c.in ${MKNTFS_EMBEDDED_SOURCE} @ONLY)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/filesystems/mkntfs_embedded.c.in)

# Folder-vault core (gocryptfs / Cryptomator / CryFS): platform-neutral C++ with
# no JNI/Android dependency -- the Android app reaches it through
# jni/foldervault_bridge.cpp, a desktop build can link it as-is (see
# foldervault/fv_vault.h). The shared primitives it builds on (scrypt, EME,
# AES-SIV, XChaCha20, the CryFS block cipher) stay in crypto/ and are linked in
# by the final target, so they are deliberately not listed here.
# Windows: fv_storage.cpp is POSIX-only (opendir/fstatat/statvfs/utimensat), so Windows builds foldervault/fv_storage_win.cpp
# instead -- the same Storage interface (PosixStorage) on the Win32 API, UTF-16 and \\?\ paths. The rest of the core
# is platform-neutral.
set(VE_FV_LIB "")
set(VE_VOLMAN_LIB "")
if(WIN32)
    set(VE_FV_STORAGE_SOURCE foldervault/fv_storage_win.cpp)
else()
    set(VE_FV_STORAGE_SOURCE foldervault/fv_storage.cpp)
endif()
add_library(foldervault_core STATIC
        foldervault/fv_common.cpp
        foldervault/fv_crypto.cpp
        ${VE_FV_STORAGE_SOURCE}
        foldervault/fv_engine.cpp
        foldervault/fv_json.cpp
        foldervault/fv_gocryptfs.cpp
        foldervault/fv_gocryptfs_vault.cpp
        foldervault/fv_cryptomator.cpp
        foldervault/fv_cryptomator_vault.cpp
        foldervault/fv_cryfs.cpp
        foldervault/fv_cryfs_vault.cpp
        foldervault/fv_check.cpp
        foldervault/fv_formats.cpp
        foldervault/fv_check_gocryptfs.cpp
        foldervault/fv_check_cryptomator.cpp
        foldervault/fv_check_cryfs.cpp)
set_target_properties(foldervault_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_features(foldervault_core PUBLIC cxx_std_20)
target_compile_options(foldervault_core PRIVATE -Wall -Wextra)
# 32-bit ABIs (armeabi-v7a, x86) have a 32-bit off_t unless this is defined. Without it, files >= 2 GiB are
# invisible in directory listings (fstatat -> EOVERFLOW) and cannot be read. The vaultexplorer target already
# sets it, but this library is a separate target. No header exposes off_t, so PRIVATE is safe.
target_compile_definitions(foldervault_core PRIVATE _FILE_OFFSET_BITS=64)
if(WIN32)
    # windows.h must not define min()/max() (the code uses std::min/std::max); fv_crypto.cpp draws its random
    # bytes from BCryptGenRandom.
    target_compile_definitions(foldervault_core PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
    target_link_libraries(foldervault_core PUBLIC bcrypt)
endif()
target_include_directories(foldervault_core PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${mbedtls_SOURCE_DIR}/include)
target_link_libraries(foldervault_core PUBLIC mbedcrypto)
if(ANDROID)
    # Bulk AEAD through BoringSSL's EVP (what the app used before the move to
    # C++; ARMv8 AES+PMULL) and the user-entropy mixing for creation flows.
    target_compile_definitions(foldervault_core PRIVATE FV_AEAD_EVP=1 FV_USE_USERENTROPY=1)
    target_link_libraries(foldervault_core PUBLIC crypto)
endif()
if(VAULTEXPLORER_DESKTOP)
    # Same key-generation entropy mixing as Android (crypto/user_entropy.cpp is part of the engine).
    target_compile_definitions(foldervault_core PRIVATE FV_USE_USERENTROPY=1)
    # Bulk AEAD through BoringSSL's EVP, as on Android. The engine already links BoringSSL, and its AES-NI/PCLMUL
    # AES-GCM and vectorised XChaCha20-Poly1305 are far faster than mbedTLS' GCM and the portable XChaCha code the
    # desktop build used until now. Measured on an Intel Xeon (AES-NI, PCLMUL, AVX2), single thread, seal/open of
    # 4 KiB and 32 KiB chunks: AES-256-GCM ~300-360 MB/s with mbedTLS vs 7-13 GB/s with EVP (25-40x), XChaCha20-
    # Poly1305 ~390-430 MB/s vs 1.5-2.1 GB/s (4-5x). Both backends give byte-identical ciphertext and tags and
    # reject tampered data and a wrong AAD alike (checked for AES-128/256-GCM with 12- and 16-byte nonces and
    # XChaCha20-Poly1305, sizes 0 to 32 KiB), so vaults are interchangeable between them.
    target_compile_definitions(foldervault_core PRIVATE FV_AEAD_EVP=1)
    target_link_libraries(foldervault_core PUBLIC crypto)
endif()
set(VE_FV_LIB foldervault_core)

# Transfer helpers: content hashing (MD5 / SHA-1 / SHA-256 / SHA-512, several in one pass)
# and splitting / joining files into numbered parts, on abstract byte sources and sinks.
# Platform-neutral C++ like foldervault_core and volman_core -- no JNI, Android or Flutter
# types. xfer_core is pure (it only needs mbedtls and is what volman_core links); xfer_host
# adds the std::filesystem front end a desktop program calls directly, and is left out of the
# default build so the Android library does not compile code it never uses.
add_library(xfer_core STATIC
        xfer/xfer_hash.cpp
        xfer/xfer_split.cpp)
set_target_properties(xfer_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_features(xfer_core PUBLIC cxx_std_20)
target_compile_options(xfer_core PRIVATE $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall> $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wextra>)
target_include_directories(xfer_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR} ${mbedtls_SOURCE_DIR}/include)
target_link_libraries(xfer_core PUBLIC mbedcrypto)

add_library(xfer_host STATIC EXCLUDE_FROM_ALL xfer/xfer_host.cpp)
set_target_properties(xfer_host PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_options(xfer_host PRIVATE $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall> $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wextra>)
target_link_libraries(xfer_host PUBLIC xfer_core)

# Volume manager: the slot table of unlocked volumes and every operation addressed
# by slot (listing, I/O, read streams, copy between any two volumes), over one
# vm::Volume interface. Platform-neutral C++ like foldervault_core -- no JNI, Android
# or Flutter types -- so the Android JNI layer and a desktop front-end sit on the
# same calls (see volman/vm_manager.h). Folder vaults plug in through vm_foldervault;
# block-device volumes through volman/vm_block_volume.cpp, which needs the engine
# (volumes[], fs_ops.h) and is therefore compiled into the engine target below, not here.
if(TARGET foldervault_core)
    add_library(volman_core STATIC
            volman/vm_manager.cpp
            volman/vm_foldervault.cpp
            volman/vm_xfer.cpp)
    set_target_properties(volman_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
    target_compile_features(volman_core PUBLIC cxx_std_20)
    target_compile_options(volman_core PRIVATE $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall> $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wextra>)
    target_include_directories(volman_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(volman_core PUBLIC foldervault_core xfer_core)
    set(VE_VOLMAN_LIB volman_core)
endif()

# 4. Build target
set(VE_ENGINE_SOURCES
        io/virtual_block_device.cpp
        jni/jni_bridge_common.cpp
        jni/crypto_bridge.cpp
        jni/foldervault_bridge.cpp
        jni/volman_bridge.cpp
        jni/prims_bridge.cpp
        crypto/prims.cpp
        jni/session_bridge.cpp
        jni/container_lifecycle_bridge.cpp
        jni/filesystem_bridge.cpp
        session/session_prepare.cpp
        session/bitlocker_backend.cpp
        containers/container_create.cpp
        containers/container_expand_bitlocker.cpp
        containers/bl_disk_expand.cpp
        containers/vdisk.cpp
        containers/vhdx_image.cpp
        containers/vhd_image.cpp
        jni/jni_runtime.cpp
        jni/jni_callbacks.cpp
        jni/avif_bridge.cpp
        io/carrier_fd_cache.cpp
        containers/carrier_profiler.cpp
        containers/composite_block_device.cpp
        containers/composite_map.cpp
        containers/container_create_composite.cpp
        jni/composite_bridge.cpp
        io/block_io.cpp
        io/partition_writer.cpp
        containers/container_create_usb.cpp
        session/volume_state.cpp
        filesystems/ext_backend.cpp
        filesystems/fat_backend.cpp
        filesystems/filesystem_paths.cpp
        filesystems/ntfs_backend.cpp
        filesystems/fs_ops.cpp
        session/session_guard.cpp
        jni/session_guard_jni.cpp
        containers/container_header.cpp
        containers/container_utils.cpp
        containers/container_repair.cpp
        jni/archive_bridge.cpp
        jni/repair_bridge.cpp
        crypto/cipher_shim.cpp
        crypto/cascade.cpp
        crypto/kdf_table.cpp
        crypto/luks_header.cpp
        crypto/luks_cipher.cpp
        crypto/scrypt.cpp
        crypto/cryfs_block_cipher.cpp crypto/cryfs_legacy_ciphers.cpp
        crypto/single_file_crypto.cpp
        crypto/user_entropy.cpp
        crypto/xchacha20poly1305.cpp
        crypto/eme.cpp
        crypto/siv.cpp
        ${fatfs_SOURCE_DIR}/src/ff.c
        ${fatfs_SOURCE_DIR}/src/ffunicode.c
        Common/Endian.c
        ${VC_CRYPTO_DIR}/Twofish.c
        ${VC_CRYPTO_DIR}/Serpent.c
        ${VC_CRYPTO_DIR}/Camellia.c
        ${VC_CRYPTO_DIR}/kuznyechik.c
        ${VC_CRYPTO_DIR}/Whirlpool.c
        ${VC_CRYPTO_DIR}/Streebog.c
        ${VC_CRYPTO_DIR}/blake2s.c
        ${VC_CRYPTO_DIR}/cpu.c
        ${VC_ARGON2_DIR}/src/argon2.c
        ${VC_ARGON2_DIR}/src/core.c
        ${VC_ARGON2_DIR}/src/ref.c
        ${ARGON2_SIMD_SOURCES}
        ${VC_ARGON2_DIR}/src/blake2/blake2b.c
        crypto/thread.c 
        ${NTFS_3G_SOURCES}
        ${MKNTFS_EMBEDDED_SOURCE}
        archive/archive_engine.cpp
        archive/archive_split.cpp
        jni/qr_bridge.cpp
        docscan/doc_scan.cpp
        docscan/doc_pdf.cpp
        jni/docscan_bridge.cpp
)

if(TARGET volman_core)
    list(APPEND VE_ENGINE_SOURCES volman/vm_block_volume.cpp)
endif()

if(VAULTEXPLORER_DESKTOP)
    # Unicode NFC for Cryptomator names (fv::setNfcNormalizer, ffi/ve_nfc.cpp). Android asks java.text.Normalizer;
    # the desktop engine has no JVM, so it carries utf8proc (MIT; the Unicode data tables fall under the Unicode
    # license -- see NOTICE.md). Static, and PIC through CMAKE_POSITION_INDEPENDENT_CODE above.
    FetchContent_Declare(
        utf8proc
        URL https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v2.10.0.tar.gz
        URL_HASH SHA256=6f4f1b639daa6dca9f80bc5db1233e9cbaa31a67790887106160b33ef743f136
    )
    set(UTF8PROC_INSTALL OFF CACHE BOOL "" FORCE)
    set(UTF8PROC_ENABLE_TESTING OFF CACHE BOOL "" FORCE)
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(utf8proc)
    # Drop every JNI bridge / JVM-callback file and add the C ABI + desktop callbacks.
    list(FILTER VE_ENGINE_SOURCES EXCLUDE REGEX "^jni/")
    list(APPEND VE_ENGINE_SOURCES
            ffi/ve_engine.cpp
            ffi/ve_crypto.cpp
            ffi/ve_foldervault.cpp
            ffi/ve_callbacks.cpp
            ffi/ve_nfc.cpp
            ffi/ve_archive.cpp
            ffi/ve_image.cpp
            ffi/ve_repair.cpp
            ffi/ve_tools.cpp
            ffi/ve_composite.cpp
            ffi/ve_mount_fs.cpp
            ffi/ve_mount_fuse.cpp
            ffi/ve_raw_device.cpp)  # raw disks / partitions (BitLocker, VeraCrypt, LUKS) behind the USB hooks
    if(WIN32)
        # pread/pwrite over CRT descriptors + BCryptGenRandom. With ve_rawdev_win.cpp (raw \\.\PhysicalDriveN)
        # these are the only files that include <windows.h>; neither includes an engine header.
        list(APPEND VE_ENGINE_SOURCES ffi/ve_win_platform.cpp ffi/ve_rawdev_win.cpp)
    else()
        list(APPEND VE_ENGINE_SOURCES ffi/ve_rawdev_posix.cpp)
    endif()
    # Native image thumbnails (imaging/thumb.cpp) and the codecs behind them. Desktop only: Android decodes with
    # BitmapFactory and does not build, fetch or link any of this. A static library of its own, so the codec
    # headers (jpeglib.h, png.h, webp/) are visible to that one file and nothing else in the engine.
    include(${CMAKE_CURRENT_SOURCE_DIR}/imaging_deps.cmake)
    # Video thumbnails (imaging/video_thumb.cpp) additionally need FFmpeg; without it (ffmpeg_deps.cmake could not
    # build it) that file compiles to a stub that answers "unsupported" and the desktop code uses libmpv instead.
    include(${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg_deps.cmake)
    add_library(ve_imaging STATIC imaging/thumb.cpp imaging/video_thumb.cpp)
    target_include_directories(ve_imaging PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${VE_IMAGING_INCLUDE_DIRS})
    if(VE_HAVE_FFMPEG)
        target_compile_definitions(ve_imaging PRIVATE VE_HAVE_FFMPEG)
        target_link_libraries(ve_imaging PUBLIC ${VE_FFMPEG_LIBS})
        add_dependencies(ve_imaging ffmpeg_ep)  # its headers must be installed before video_thumb.cpp compiles
    endif()
    target_compile_features(ve_imaging PRIVATE cxx_std_17)
    target_compile_options(ve_imaging PRIVATE -Wall -Wextra)
    set_target_properties(ve_imaging PROPERTIES
            POSITION_INDEPENDENT_CODE ON
            C_VISIBILITY_PRESET hidden
            CXX_VISIBILITY_PRESET hidden)
    target_link_libraries(ve_imaging PUBLIC ${VE_JPEG_LIB} ${VE_PNG_LIB} ${VE_WEBP_DECODER_LIB})
    add_dependencies(ve_imaging libjpeg_turbo_ep)  # its headers must be installed before thumb.cpp compiles
endif()

add_library(vaultexplorer SHARED ${VE_ENGINE_SOURCES})

if(ANDROID_ABI STREQUAL "arm64-v8a")
    target_compile_options(vaultexplorer PRIVATE -march=armv8-a+crypto+sha2)
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    target_compile_options(vaultexplorer PRIVATE -mfpu=neon)
endif()

# GCC 14+ makes implicit function declarations a hard error, and some legacy C in the vendored
# dependencies (ntfs-3g, e2fsprogs, dislocker) still relies on them. Desktop toolchains are GCC;
# the Android NDK (clang) build keeps its flags exactly as before.
if(VAULTEXPLORER_DESKTOP AND NOT MSVC)
    set(VE_LEGACY_C_FLAGS -Wno-error=implicit-function-declaration -Wno-error=int-conversion
                          -Wno-error=incompatible-pointer-types)
    target_compile_options(vaultexplorer PRIVATE "$<$<COMPILE_LANGUAGE:C>:${VE_LEGACY_C_FLAGS}>")
    # the other vendored legacy-C libraries built in this directory
    foreach(VE_LEGACY_TARGET e2fs_com_err e2fs_ext2fs e2fs_uuid dislocker_lib)
        if(TARGET ${VE_LEGACY_TARGET})
            target_compile_options(${VE_LEGACY_TARGET} PRIVATE "$<$<COMPILE_LANGUAGE:C>:${VE_LEGACY_C_FLAGS}>")
        endif()
    endforeach()
endif()

if(NOT VAULTEXPLORER_DESKTOP)
    target_link_options(vaultexplorer PRIVATE
            "-Wl,-z,max-page-size=16384"
            "-Wl,-z,common-page-size=16384")
endif()

set_source_files_properties(${VC_ARGON2_DIR}/src/core.c
        TARGET_DIRECTORY vaultexplorer
        PROPERTIES COMPILE_OPTIONS "-include;${CMAKE_CURRENT_SOURCE_DIR}/crypto/thread.h")

target_compile_definitions(vaultexplorer PRIVATE
        CRYPTOPP_DISABLE_ASM
        CRYPTOPP_DISABLE_SSE2
        CRYPTOPP_DISABLE_SSSE3
        CRYPTOPP_DISABLE_SHANI
        HAVE_CONFIG_H  # Forces NTFS-3G files to look up our generated config.h
        _GNU_SOURCE
        _FILE_OFFSET_BITS=64
        CpuId=VeraCrypt_CpuId  # Prevents duplicate symbol collision with libyuv's CpuId on x86/x86_64
)

# 5. Header search paths
if(VAULTEXPLORER_DESKTOP)
    # BEFORE: ffi/compat now only holds the Windows POSIX shims (ve_win_compat.h, ve_win_types.h) and the FatFs
    # stand-ins; it must win over any system header of the same name.
    target_include_directories(vaultexplorer BEFORE PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/ffi/compat)
    target_include_directories(vaultexplorer PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ffi ${VE_ZLIB_INCLUDE_DIRS})
else()
    target_include_directories(vaultexplorer PRIVATE ${zxing_cpp_SOURCE_DIR}/core/src)
endif()

target_include_directories(
        vaultexplorer PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/Common
        ${CMAKE_CURRENT_SOURCE_DIR}/crypto
        ${CMAKE_CURRENT_SOURCE_DIR}/jni
        ${CMAKE_CURRENT_SOURCE_DIR}/io
        ${CMAKE_CURRENT_SOURCE_DIR}/containers
        ${CMAKE_CURRENT_SOURCE_DIR}/filesystems
        ${CMAKE_CURRENT_SOURCE_DIR}/session
        ${mbedtls_SOURCE_DIR}/include
        ${fatfs_SOURCE_DIR}/src
        ${ntfs3g_SOURCE_DIR}/include
        ${ntfs3g_SOURCE_DIR}/include/ntfs-3g
        ${ntfs3g_SOURCE_DIR}/ntfsprogs
        ${CMAKE_CURRENT_BINARY_DIR}
        ${VC_CRYPTO_DIR}
        ${VC_SRC_DIR}
        ${VC_ARGON2_DIR}/include
        ${VC_ARGON2_DIR}/src
        ${E2FS_GENERATED_DIR}
        ${E2FS_SRC_DIR}/lib
        ${E2FS_EXT2FS_DIR}
        ${cjson_SOURCE_DIR}
        ${DISLOCKER_INCLUDE_DIRS}
        ${CMAKE_CURRENT_SOURCE_DIR}/archive
        ${ARCHIVE_ENGINE_INCLUDE_DIRS}
)

if(ANDROID)
    find_library(log-lib log)
else()
    set(log-lib "")
endif()

target_compile_features(vaultexplorer PRIVATE cxx_std_20)

# Same link order as before for Android (avif/libgav1 between dislocker and the
# archive engine, ZXing last); the desktop build simply has none of the three.
if(VAULTEXPLORER_DESKTOP)
    set(VE_AVIF_LIBS "")
    set(VE_ZXING_LIB "")
else()
    set(VE_AVIF_LIBS avif libgav1_static)
    set(VE_ZXING_LIB ZXing::ZXing)
endif()

target_link_libraries(
        vaultexplorer
        ${log-lib}
        ${VE_ZLIB_LIB}
        mbedcrypto
        crypto
        e2fs_ext2fs
        e2fs_com_err
        e2fs_uuid
        cjson
        dislocker_lib
        ${VE_AVIF_LIBS}
        ${ARCHIVE_ENGINE_LIBRARY}
        ${VE_ZXING_LIB}
        ${VE_FV_LIB}
        ${VE_VOLMAN_LIB})

if(VAULTEXPLORER_DESKTOP)
    find_package(Threads REQUIRED)
    target_link_libraries(vaultexplorer Threads::Threads ve_imaging utf8proc)
    # Lets session/session_prepare.cpp treat a whole raw device (no partition table) as one candidate volume.
    target_compile_definitions(vaultexplorer PRIVATE VE_DESKTOP_RAW_DEVICES=1)
    if(WIN32)
        # OS mounts through WinFsp's FUSE 3 API (ffi/ve_mount_winfsp.cpp). winfsp-x64.dll is loaded at run time
        # from WinFsp's install dir, so only WinFsp's *headers* (the "Developer" install component, or
        # -DVE_WINFSP_INCLUDE_DIR=<winfsp>/inc) are needed to build. They are not vendored: WinFsp is
        # GPLv3 with a FLOSS exception -- check that against this project's license.
        find_path(VE_WINFSP_INCLUDE_DIR fuse3/fuse.h
            PATHS "$ENV{ProgramFiles\(x86\)}/WinFsp/inc" "$ENV{ProgramFiles}/WinFsp/inc" "C:/Program Files (x86)/WinFsp/inc")
        if(VE_WINFSP_INCLUDE_DIR)
            target_sources(vaultexplorer PRIVATE ffi/ve_mount_winfsp.cpp)
            target_compile_definitions(vaultexplorer PRIVATE VE_HAVE_WINFSP=1)
            target_include_directories(vaultexplorer PRIVATE ${VE_WINFSP_INCLUDE_DIR})
            message(STATUS "WinFsp headers found (${VE_WINFSP_INCLUDE_DIR}): OS mounts enabled")
        else()
            message(WARNING "WinFsp headers not found: building WITHOUT OS mounts (install WinFsp with the Developer component, or pass -DVE_WINFSP_INCLUDE_DIR=...)")
        endif()
    endif()
    if(NOT WIN32)
        # OS mounts (ffi/ve_mount_*.cpp). libfuse3 is dlopen()ed at runtime, so the library never links to it
        # and still loads on machines without FUSE; only the *headers* are needed here, for the struct layouts.
        find_path(VE_FUSE3_INCLUDE_DIR fuse3/fuse.h)
        if(VE_FUSE3_INCLUDE_DIR)
            target_compile_definitions(vaultexplorer PRIVATE VE_HAVE_FUSE3=1)
            target_include_directories(vaultexplorer PRIVATE ${VE_FUSE3_INCLUDE_DIR})
            set_source_files_properties(ffi/ve_mount_fuse.cpp PROPERTIES COMPILE_DEFINITIONS "_FILE_OFFSET_BITS=64")
            message(STATUS "FUSE 3 headers found (${VE_FUSE3_INCLUDE_DIR}): OS mounts enabled")
        else()
            message(WARNING "\n  ***  libfuse3 development headers not found: building WITHOUT OS mounts  ***\n  Install them (Debian/Ubuntu/KDE neon: libfuse3-dev, Fedora/openSUSE: fuse3-devel, Arch: fuse3),\n  then rebuild the engine.\n")
        endif()
        target_link_libraries(vaultexplorer ${CMAKE_DL_LIBS})
        target_sources(vaultexplorer PRIVATE ffi/ve_mount_places.cpp)  # sidebar entries (Dolphin / GTK bookmarks)
    endif()
    # The C ABI's file calls all go through one vm::VolumeManager (ffi/ve_volumes.h), and a folder vault is a volume
    # in it, so the desktop engine cannot be built without foldervault_core / volman_core. (The "unsupported" stubs
    # that used to cover that case, VE_NO_FOLDERVAULT, are gone.)
    if(NOT VE_FV_LIB OR NOT VE_VOLMAN_LIB)
        message(FATAL_ERROR "The desktop engine needs foldervault_core and volman_core")
    endif()
    if(WIN32)
        # Self-contained DLL: link the MinGW runtime (libgcc / libstdc++ / winpthread) statically, so it depends
        # only on system DLLs and a Flutter Windows bundle needs nothing from an MSYS2 install.
        target_link_options(vaultexplorer PRIVATE -static)
        target_link_libraries(vaultexplorer bcrypt ws2_32)  # BCryptGenRandom (ffi/ve_win_platform.cpp); htonl & co. (e2fsprogs)
        # POSIX shims (pread/pwrite/...) for every engine C++ file; declarations only, no windows.h.
        target_compile_options(vaultexplorer PRIVATE
                "$<$<COMPILE_LANGUAGE:CXX>:SHELL:-include ${CMAKE_CURRENT_SOURCE_DIR}/ffi/compat/ve_win_compat.h>")
        # ntfs-3g's ntfstime.h declares its own `struct timespec` unless glibc's marker is set;
        # MinGW already has one (via <time.h>/pthread), so tell it so.
        target_compile_definitions(vaultexplorer PRIVATE __timespec_defined=1)
        # uid_t/gid_t, S_IFSOCK, flock/fcntl ... for the vendored C code (ntfs-3g); see ffi/compat/ve_win_types.h
        target_compile_options(vaultexplorer PRIVATE
                "$<$<COMPILE_LANGUAGE:C>:SHELL:-include ${CMAKE_CURRENT_SOURCE_DIR}/ffi/compat/ve_win_types.h>")
    endif()
    # Export only the ve_* C ABI (VE_API); keep every engine symbol private so the
    # library cannot clash with anything the host process (Flutter) already loads.
    if(UNIX AND NOT APPLE)
        # The static dependencies (bzip2, zstd, mbedTLS, BoringSSL, ...) were not built with hidden
        # visibility, so without this their symbols would be exported from the .so and could clash
        # with copies already loaded into the host process. Only the ve_* ABI should be visible.
        target_link_options(vaultexplorer PRIVATE "-Wl,--exclude-libs,ALL")
    endif()
    if(WIN32)
        # POSIX header stand-ins (termios.h, pwd.h, grp.h, sys/ioctl.h, ...). Windows ONLY: on Linux they would
        # shadow the real system headers.
        target_include_directories(vaultexplorer BEFORE PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ffi/compat_win)
        # MinGW would name it libvaultexplorer_engine.dll; the Dart loader expects vaultexplorer_engine.dll
        set_target_properties(vaultexplorer PROPERTIES PREFIX "")
    endif()
    set_target_properties(vaultexplorer PROPERTIES
            OUTPUT_NAME vaultexplorer_engine
            C_VISIBILITY_PRESET hidden
            CXX_VISIBILITY_PRESET hidden
            VISIBILITY_INLINES_HIDDEN ON)

    # Black-box smoke test: only touches the exported ve_* C ABI, like a dart:ffi host.
    add_executable(ve_smoke_test ffi/test/ve_smoke_test.cpp)
    target_include_directories(ve_smoke_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ffi)
    target_link_libraries(ve_smoke_test vaultexplorer)
    if(WIN32)
        target_link_options(ve_smoke_test PRIVATE -static)
    endif()

    # Raw-device layer unit test: compiles ffi/ve_raw_device.cpp into itself against an in-memory fake disk that
    # enforces raw-handle alignment (4Kn adapter, bounds, same-device guard, BitLocker/LUKS probing, JSON).
    add_executable(ve_raw_device_test ffi/test/ve_raw_device_test.cpp ffi/ve_raw_device.cpp)
    target_include_directories(ve_raw_device_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ffi)

    # Mount-layer test. It compiles ffi/ve_mount_fs.cpp into itself (the library keeps its internals
    # hidden) and drives it through the exported ve_* ABI, on every container format and a folder vault.
    # (POSIX-only: it drives real FUSE mounts with fusermount3, cp, sed, ...)
    if(NOT WIN32)
        add_executable(ve_mount_test ffi/test/ve_mount_test.cpp ffi/ve_mount_fs.cpp ffi/ve_mount_places.cpp)
        target_include_directories(ve_mount_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ffi)
        target_link_libraries(ve_mount_test vaultexplorer mbedcrypto)
    endif()
endif()


set_source_files_properties(
        crypto/cryfs_block_cipher.cpp crypto/cryfs_legacy_ciphers.cpp
        crypto/eme.cpp
        crypto/siv.cpp
        crypto/xchacha20poly1305.cpp
        jni/crypto_bridge.cpp
        jni/foldervault_bridge.cpp
        jni/volman_bridge.cpp
        volman/vm_block_volume.cpp
        jni/prims_bridge.cpp
        crypto/prims.cpp
        PROPERTIES COMPILE_OPTIONS "-Wall;-Wextra"
)

if(NOT ANDROID)
    # Opt-in ASan+UBSan for the host-side test executables below. Off by
    # default (sanitizers add runtime overhead and shouldn't surprise a
    # plain `cmake --build .`); a CI job can turn this on with
    # -DVAULTEXPLORER_ENABLE_SANITIZERS=ON. Scoped to the host tests rather
    # than the full Android-target build because they already build outside
    # the NDK toolchain with zero extra setup -- the lowest-friction place to
    # start. Verified clean (and, for cryfs_block_cipher_test specifically,
    # also verified clean under -fsanitize=thread) against every test in this
    # block before this option was added.
    option(VAULTEXPLORER_ENABLE_SANITIZERS "Build host-side tests with ASan+UBSan" OFF)

    add_executable(sector_batching_test io/test/sector_batching_test.cpp)
    add_executable(fs_scan_test test/fs_scan_test.cpp)
    add_executable(doc_scan_test docscan/test/doc_scan_test.cpp docscan/doc_scan.cpp docscan/doc_pdf.cpp)
    add_executable(kdf_table_test crypto/test/kdf_table_test.cpp crypto/kdf_table.cpp)
    add_executable(decrypted_block_cache_test io/test/decrypted_block_cache_test.cpp)
    add_executable(fd_write_buffer_test io/test/fd_write_buffer_test.cpp)
    # UsbBlockCache coherence (write ordering across the two streams, read-ahead
    # invalidation, failed-flush retry). Header-only class. Its host callbacks are
    # declared in platform/engine_hooks.h (no JNI types), so no <jni.h> is needed
    # at all; the stub include dirs below date from when it pulled in jni_callbacks.h
    # and are no longer required.
    add_executable(usb_block_cache_test io/test/usb_block_cache_test.cpp)
    target_include_directories(usb_block_cache_test PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/filesystems/test/host_stubs
            ${CMAKE_CURRENT_SOURCE_DIR}/jni)
    # Header-area arithmetic (backup header offsets, hidden-volume protected range).
    add_executable(vc_geometry_test containers/test/vc_geometry_test.cpp)
    # Random fill of the reserved header areas (hidden-volume deniability).
    add_executable(vc_header_areas_test containers/test/vc_header_areas_test.cpp)
    # Free-space fill: uses stand-in crypto headers, which must win over the real
    # crypto/ ones on the include path (hence BEFORE).
    add_executable(vc_free_space_fill_test containers/test/vc_free_space_fill_test.cpp)
    target_include_directories(vc_free_space_fill_test BEFORE PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/containers/test/host_stubs)
    # Lock ordering policy, driven with the real UsbBlockCache (no <jni.h> needed, as above).
    add_executable(lock_policy_test session/test/lock_policy_test.cpp)
    target_include_directories(lock_policy_test PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/filesystems/test/host_stubs
            ${CMAKE_CURRENT_SOURCE_DIR}/jni)
    add_executable(cryfs_block_cipher_test
            test/cryfs_block_cipher_test.cpp
            crypto/cryfs_block_cipher.cpp crypto/cryfs_legacy_ciphers.cpp
            crypto/xchacha20poly1305.cpp)
    target_include_directories(cryfs_block_cipher_test PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${mbedtls_SOURCE_DIR}/include)
    target_link_libraries(cryfs_block_cipher_test mbedcrypto)
    # User-collected entropy mixing (crypto/user_entropy.cpp): known-answer
    # vectors shared with the JVM-side util/UserEntropy.kt test, plus scoping
    # (nesting, per-thread) behavior.
    add_executable(user_entropy_test
            crypto/test/user_entropy_test.cpp
            crypto/user_entropy.cpp)
    target_include_directories(user_entropy_test PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${mbedtls_SOURCE_DIR}/include)
    target_link_libraries(user_entropy_test mbedcrypto)
    # Header-only (crypto/utf16le_password.h is all `static inline`), so no
    # extra .cpp sources or link libraries needed. Regression coverage for
    # the OOB read fixed in dislocker/encoding.c::toutf16() and for the
    # CESU-8/emoji password behavior documented in the header.
    add_executable(utf16le_password_test crypto/test/utf16le_password_test.cpp)

    add_executable(composite_block_device_test
            containers/test/composite_block_device_test.cpp
            containers/composite_block_device.cpp
            containers/composite_map.cpp
            containers/carrier_profiler.cpp
            io/carrier_fd_cache.cpp)
    target_link_libraries(composite_block_device_test crypto)

    list(APPEND VAULTEXPLORER_HOST_TESTS composite_block_device_test)
    add_test(NAME composite_block_device_test COMMAND composite_block_device_test)
    # These three had been sitting on disk with a working, self-documented
    # `g++ -std=c++17 ...` build command in their own header comment, but no
    # add_executable/add_test entry here -- so `ctest` never ran them and
    # nothing caught that gap. Verified compiling and passing standalone
    # with that exact command before wiring in below.
    add_executable(container_header_test
            containers/test/container_header_test.cpp
            containers/container_header.cpp)
    add_executable(container_utils_crc32_test containers/test/container_utils_crc32_test.cpp)
    # BitLocker expand core (containers/bl_expand.h): synthetic FVE metadata, rewrite + re-seal checks.
    add_executable(bl_expand_test containers/test/bl_expand_test.cpp)
    target_include_directories(bl_expand_test PRIVATE ${mbedtls_SOURCE_DIR}/include)
    target_link_libraries(bl_expand_test mbedcrypto)
    list(APPEND VAULTEXPLORER_HOST_TESTS bl_expand_test)
    add_test(NAME bl_expand_test COMMAND bl_expand_test)
    # Disk-image expansion: partition tables (MBR/GPT, in memory) and the legacy-VHD half of the virtual-disk growth
    # (synthetic images). The VHDX growth and the real-BitLocker-in-VHD/VHDX checks are shell scripts that need qemu-img
    # (containers/test/*_qemu_check.sh) and are not part of ctest.
    add_executable(disk_partition_test containers/test/disk_partition_test.cpp)
    target_include_directories(disk_partition_test PRIVATE ${mbedtls_SOURCE_DIR}/include)
    target_link_libraries(disk_partition_test mbedcrypto)
    list(APPEND VAULTEXPLORER_HOST_TESTS disk_partition_test)
    add_test(NAME disk_partition_test COMMAND disk_partition_test)
    add_executable(vdisk_vhd_test
            containers/test/vdisk_vhd_test.cpp
            containers/vdisk.cpp
            containers/vhd_image.cpp
            containers/vhdx_image.cpp)
    target_include_directories(vdisk_vhd_test PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/filesystems/test/host_stubs
            ${CMAKE_CURRENT_SOURCE_DIR}/containers)
    list(APPEND VAULTEXPLORER_HOST_TESTS vdisk_vhd_test)
    add_test(NAME vdisk_vhd_test COMMAND vdisk_vhd_test)
    add_executable(chunked_block_device_test
            containers/test/chunked_block_device_test.cpp
            containers/chunked_block_device.cpp)

    # Use the same pinned, patched libarchive as the Android engine. In
    # particular, the 7-Zip encryption coverage below depends on the
    # libarchive-7zip-encryption.patch applied by archive_deps.cmake; a host
    # system libarchive may accept the writer passphrase but silently emit a
    # plain archive.
    add_executable(archive_engine_test
            archive/test/archive_engine_test.cpp
            archive/archive_engine.cpp)
    target_include_directories(archive_engine_test PRIVATE ${ARCHIVE_ENGINE_INCLUDE_DIRS})
    target_link_libraries(archive_engine_test ${ARCHIVE_ENGINE_LIBRARY})
    list(APPEND VAULTEXPLORER_HOST_TESTS archive_engine_test)

    # Compression level, source-byte progress and cancellation of archiveCreate.
    # Separate executable so it isn't skipped if archive_engine_test aborts early.
    add_executable(archive_create_options_test
            archive/test/archive_create_options_test.cpp
            archive/archive_engine.cpp)
    target_include_directories(archive_create_options_test PRIVATE ${ARCHIVE_ENGINE_INCLUDE_DIRS})
    target_link_libraries(archive_create_options_test ${ARCHIVE_ENGINE_LIBRARY})
    list(APPEND VAULTEXPLORER_HOST_TESTS archive_create_options_test)

    add_executable(archive_split_test
            archive/test/archive_split_test.cpp
            archive/archive_engine.cpp
            archive/archive_split.cpp)
    target_include_directories(archive_split_test PRIVATE ${ARCHIVE_ENGINE_INCLUDE_DIRS})
    target_link_libraries(archive_split_test ${ARCHIVE_ENGINE_LIBRARY})
    list(APPEND VAULTEXPLORER_HOST_TESTS archive_split_test)

    # The archive C ABI (ffi/ve_archive.cpp) over an in-memory fake vault: vault and host sources and sinks,
    # split sets, short stream reads, folder-vault finish semantics, cancel and failure cleanup.
    add_executable(ve_archive_test
            ffi/test/ve_archive_test.cpp
            ffi/ve_archive.cpp
            archive/archive_engine.cpp
            archive/archive_split.cpp)
    target_include_directories(ve_archive_test PRIVATE ${ARCHIVE_ENGINE_INCLUDE_DIRS})
    target_link_libraries(ve_archive_test ${ARCHIVE_ENGINE_LIBRARY})
    list(APPEND VAULTEXPLORER_HOST_TESTS ve_archive_test)

    # Native image thumbnails (imaging/thumb.cpp): every format and size, EXIF orientations, alpha, truncated and
    # hostile input, size guards, many threads. Desktop engine builds only (it needs the codecs of
    # imaging_deps.cmake, and the libwebp ENCODER for its fixtures). Compiles thumb.cpp into itself rather than
    # linking ve_imaging, because it links libwebp's full library (encoder + decoder) instead of the decoder-only one.
    if(VAULTEXPLORER_DESKTOP AND TARGET ve_png AND TARGET webp)
        add_executable(thumb_test imaging/test/thumb_test.cpp imaging/thumb.cpp)
        target_include_directories(thumb_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${VE_IMAGING_INCLUDE_DIRS})
        target_link_libraries(thumb_test ${VE_JPEG_LIB} ${VE_PNG_LIB} webp Threads::Threads)
        add_dependencies(thumb_test libjpeg_turbo_ep)
        list(APPEND VAULTEXPLORER_HOST_TESTS thumb_test)
    endif()

    # Native video thumbnails (imaging/video_thumb.cpp): every container and codec of the minimal FFmpeg build,
    # rotation, pixel aspect, frame selection, what must be refused, many threads -- on the tiny videos of
    # imaging/test/fixtures. Only when FFmpeg is part of this build.
    if(VAULTEXPLORER_DESKTOP AND VE_HAVE_FFMPEG AND TARGET ve_png)
        add_executable(video_thumb_test imaging/test/video_thumb_test.cpp imaging/video_thumb.cpp imaging/thumb.cpp)
        target_include_directories(video_thumb_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${VE_IMAGING_INCLUDE_DIRS})
        target_compile_definitions(video_thumb_test PRIVATE VE_HAVE_FFMPEG)
        target_link_libraries(video_thumb_test ${VE_JPEG_LIB} ${VE_PNG_LIB} ${VE_WEBP_DECODER_LIB} ${VE_FFMPEG_LIBS}
                              Threads::Threads)
        add_dependencies(video_thumb_test libjpeg_turbo_ep ffmpeg_ep)
        list(APPEND VAULTEXPLORER_HOST_TESTS video_thumb_test)
    endif()

    # Folder-vault core: known-answer vectors, per-format scenarios, tamper /
    # rollback / legacy-name handling and thread stress. The interop scripts in
    # foldervault/test/interop additionally drive `fvcli` against the real
    # gocryptfs, Cryptomator and CryFS binaries (not part of ctest: they need
    # those programs and FUSE).
    set(FV_CRYPTO_SOURCES
            crypto/eme.cpp crypto/siv.cpp crypto/scrypt.cpp
            crypto/xchacha20poly1305.cpp crypto/cryfs_block_cipher.cpp crypto/cryfs_legacy_ciphers.cpp)
    add_executable(foldervault_test foldervault/test/fv_tests.cpp ${FV_CRYPTO_SOURCES})
    target_link_libraries(foldervault_test foldervault_core mbedcrypto)
    # The gocryptfs known-answer vectors are located via an absolute path baked in
    # here, not via __FILE__: the global -ffile-prefix-map above rewrites
    # CMAKE_SOURCE_DIR to /source_tree inside __FILE__, so deriving the path from it
    # points at a directory that doesn't exist on the host (FV_VECTORS still overrides).
    target_compile_definitions(foldervault_test PRIVATE
            FV_VECTORS_DIR="${CMAKE_CURRENT_LIST_DIR}/foldervault/test/vectors/gocryptfs")
    add_executable(fvcli foldervault/test/fvcli.cpp ${FV_CRYPTO_SOURCES})
    target_link_libraries(fvcli foldervault_core mbedcrypto)
    list(APPEND VAULTEXPLORER_HOST_TESTS foldervault_test)
    # The same scenarios on any platform's directory storage (Windows: fv_storage_win.cpp): empty-folder listing,
    # create / find the config / unlock / work / unlock again for all three formats, Unicode and over-long paths.
    add_executable(foldervault_storage_test foldervault/test/fv_storage_test.cpp ${FV_CRYPTO_SOURCES})
    target_link_libraries(foldervault_storage_test foldervault_core mbedcrypto)
    list(APPEND VAULTEXPLORER_HOST_TESTS foldervault_storage_test)

    # Volume manager: slots, streams, copy and close semantics on an in-memory
    # volume, plus real gocryptfs / Cryptomator / CryFS vaults behind the same
    # manager (copies between every pair of formats, cancellation, close while
    # calls are in flight).
    add_executable(volman_test volman/test/vm_tests.cpp ${FV_CRYPTO_SOURCES})
    target_link_libraries(volman_test volman_core foldervault_core mbedcrypto)
    list(APPEND VAULTEXPLORER_HOST_TESTS volman_test)

    # Crypto primitives behind the channel's hmac / aesCbcDecrypt / ... methods (crypto/prims.cpp):
    # HMAC, PBKDF2, AES-GCM and AES-CBC against vectors generated with independent implementations
    # (test/gen_prims_vectors.py: Python hmac/hashlib + `cryptography`; its RFC 6238 TOTP table is
    # asserted against the RFC), plus the strict input contracts and tamper detection.
    add_executable(prims_test crypto/test/prims_tests.cpp crypto/prims.cpp)
    target_include_directories(prims_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${mbedtls_SOURCE_DIR}/include)
    target_link_libraries(prims_test mbedcrypto)
    list(APPEND VAULTEXPLORER_HOST_TESTS prims_test)

    # Logging shim of the portable engine (platform/engine_log.h), non-Android path: levels, tags,
    # formatting, truncation, and installing a sink while other threads log.
    add_executable(engine_log_test platform/test/engine_log_test.cpp)
    target_include_directories(engine_log_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    list(APPEND VAULTEXPLORER_HOST_TESTS engine_log_test)

    # Default (do-nothing) engine hooks for builds without a JVM (platform/engine_hooks_default.cpp):
    # links on its own, defines every hook declared in platform/engine_hooks.h, and behaves as
    # documented. Built with no <jni.h> and no <android/...> anywhere on the include path.
    add_executable(engine_hooks_default_test
            platform/test/engine_hooks_default_test.cpp
            platform/engine_hooks_default.cpp)
    target_include_directories(engine_hooks_default_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    list(APPEND VAULTEXPLORER_HOST_TESTS engine_hooks_default_test)

    # Transfer helpers: hashing against known answers (vectors from hashlib), part naming and
    # sequence resolution, split / join on in-memory streams (part boundaries, cancel, write /
    # close / read failures) and on real files (round trips, UTF-8 names, refusing to overwrite
    # a part).
    add_executable(xfer_test xfer/test/xfer_tests.cpp)
    target_link_libraries(xfer_test xfer_host xfer_core)
    list(APPEND VAULTEXPLORER_HOST_TESTS xfer_test)

    # BlockVolume (volman/vm_block_volume.cpp) on the real VolumeState table, with an
    # in-memory fake of the filesystem layer underneath (the fsXxx() functions) and real
    # gocryptfs / Cryptomator vaults beside it in one VolumeManager: refusal on a locked or
    # read-only volume, end-of-file vs failure, streams, a container locked (and another
    # unlocked into the same slot) behind the manager's back, close() draining.
    # volume_state.h pulls in crypto/cipher_shim.h (<openssl/aes.h>), so this test is only
    # registered where those headers exist (libssl-dev); the stub <jni.h> is enough.
    find_path(VM_OPENSSL_INCLUDE_DIR openssl/aes.h)
    if(VM_OPENSSL_INCLUDE_DIR)
        add_executable(volman_block_test
                volman/test/vm_block_tests.cpp volman/vm_block_volume.cpp ${FV_CRYPTO_SOURCES})
        # volman/test/ntfs_stub comes first: its volume.h adds ntfs-3g's min()/max() macros to the
        # stub, so a bare std::min in a TU that sees volume_state.h fails here as it does in the Android build.
        target_include_directories(volman_block_test PRIVATE
                ${CMAKE_CURRENT_SOURCE_DIR}/volman/test/ntfs_stub
                ${CMAKE_CURRENT_SOURCE_DIR}/filesystems/test/host_stubs
                ${CMAKE_CURRENT_SOURCE_DIR}/session
                ${CMAKE_CURRENT_SOURCE_DIR}/io
                ${CMAKE_CURRENT_SOURCE_DIR}/filesystems
                ${CMAKE_CURRENT_SOURCE_DIR}/containers
                ${CMAKE_CURRENT_SOURCE_DIR}/crypto
                ${CMAKE_CURRENT_SOURCE_DIR}/jni
                ${CMAKE_CURRENT_SOURCE_DIR}/archive
                ${CMAKE_CURRENT_SOURCE_DIR}/Common
                ${mbedtls_SOURCE_DIR}/include
                ${VM_OPENSSL_INCLUDE_DIR})
        target_link_libraries(volman_block_test volman_core foldervault_core mbedcrypto)
        list(APPEND VAULTEXPLORER_HOST_TESTS volman_block_test)
    endif()

    set(VAULTEXPLORER_HOST_TESTS
            sector_batching_test
            fs_scan_test
            doc_scan_test
            kdf_table_test
            decrypted_block_cache_test
            fd_write_buffer_test
            usb_block_cache_test
            vc_geometry_test
            vc_header_areas_test
            vc_free_space_fill_test
            lock_policy_test
            cryfs_block_cipher_test
            user_entropy_test
            utf16le_password_test
            container_header_test
            container_utils_crc32_test
            chunked_block_device_test
            ${VAULTEXPLORER_HOST_TESTS})
    list(REMOVE_DUPLICATES VAULTEXPLORER_HOST_TESTS)

    foreach(host_test ${VAULTEXPLORER_HOST_TESTS})
        target_include_directories(${host_test} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
        target_compile_options(${host_test} PRIVATE -Wall -Wextra)
        if(VAULTEXPLORER_ENABLE_SANITIZERS)
            target_compile_options(${host_test} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer -g)
            target_link_options(${host_test} PRIVATE -fsanitize=address,undefined)
        endif()
    endforeach()

    add_custom_target(host_tests DEPENDS ${VAULTEXPLORER_HOST_TESTS})

    enable_testing()
    add_test(NAME sector_batching_test COMMAND sector_batching_test)
    add_test(NAME fs_scan_test COMMAND fs_scan_test)
    add_test(NAME doc_scan_test COMMAND doc_scan_test)
    add_test(NAME kdf_table_test COMMAND kdf_table_test)
    add_test(NAME decrypted_block_cache_test COMMAND decrypted_block_cache_test)
    add_test(NAME fd_write_buffer_test COMMAND fd_write_buffer_test)
    add_test(NAME usb_block_cache_test COMMAND usb_block_cache_test)
    add_test(NAME vc_geometry_test COMMAND vc_geometry_test)
    add_test(NAME vc_header_areas_test COMMAND vc_header_areas_test)
    add_test(NAME vc_free_space_fill_test COMMAND vc_free_space_fill_test)
    add_test(NAME lock_policy_test COMMAND lock_policy_test)
    add_test(NAME cryfs_block_cipher_test COMMAND cryfs_block_cipher_test)
    add_test(NAME user_entropy_test COMMAND user_entropy_test)
    add_test(NAME utf16le_password_test COMMAND utf16le_password_test)
    add_test(NAME foldervault_test COMMAND foldervault_test)
    add_test(NAME volman_test COMMAND volman_test)
    add_test(NAME xfer_test COMMAND xfer_test)
    add_test(NAME prims_test COMMAND prims_test)
    add_test(NAME engine_log_test COMMAND engine_log_test)
    add_test(NAME engine_hooks_default_test COMMAND engine_hooks_default_test)
    # The portable engine must not include JNI or Android headers (static check, no compiler needed).
    find_package(Python3 COMPONENTS Interpreter QUIET)
    if(Python3_FOUND)
        add_test(NAME engine_portable
                COMMAND ${Python3_EXECUTABLE}
                        ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../scripts/check_engine_portable.py)
    endif()
    if(TARGET volman_block_test)
        add_test(NAME volman_block_test COMMAND volman_block_test)
    endif()
    add_test(NAME container_header_test COMMAND container_header_test)
    add_test(NAME container_utils_crc32_test COMMAND container_utils_crc32_test)
    add_test(NAME chunked_block_device_test COMMAND chunked_block_device_test)
    if(TARGET archive_engine_test)
        add_test(NAME archive_engine_test COMMAND archive_engine_test)
    endif()
    if(TARGET archive_create_options_test)
        add_test(NAME archive_create_options_test COMMAND archive_create_options_test)
    endif()
    if(TARGET archive_split_test)
        add_test(NAME archive_split_test COMMAND archive_split_test)
    endif()
    if(TARGET ve_archive_test)
        add_test(NAME ve_archive_test COMMAND ve_archive_test)
    endif()
    if(TARGET thumb_test)
        add_test(NAME thumb_test COMMAND thumb_test)
    endif()
    if(TARGET video_thumb_test)
        add_test(NAME video_thumb_test COMMAND video_thumb_test ${CMAKE_CURRENT_SOURCE_DIR}/imaging/test/fixtures)
    endif()
endif()
