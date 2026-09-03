cmake_minimum_required(VERSION 3.18.0)

project("vaultexplorer")

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
if(ANDROID_ABI MATCHES "x86")
    set(OPENSSL_NO_ASM ON CACHE BOOL "" FORCE)
else()
    set(OPENSSL_NO_ASM OFF CACHE BOOL "" FORCE)
endif()

FetchContent_MakeAvailable(boringssl)


# ── AVIF Decoder (libgav1 + libavif) ──
FetchContent_Declare(
    libgav1
    GIT_REPOSITORY https://chromium.googlesource.com/codecs/libgav1
    GIT_TAG        c05bf9be660cf170d7c26bd06bb42b3322180e58
)
set(LIBGAV1_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(LIBGAV1_ENABLE_EXAMPLES OFF CACHE BOOL "" FORCE)
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

# Enable ARMv8 Cryptography Extensions ONLY for ARM targets
if(ANDROID_ABI STREQUAL "arm64-v8a")
    target_compile_options(mbedcrypto PRIVATE -march=armv8-a+crypto+sha2 -Wno-macro-redefined)
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    target_compile_options(mbedcrypto PRIVATE -mfpu=neon)
endif()

# 1a. Archive engine (libarchive + its compression filters) -- see
# archive_deps.cmake's file-level comment for what's vendored vs. reused
# from the NDK/BoringSSL, and for a caveat on what could/couldn't be
# verified without an actual Android build.
include(${CMAKE_CURRENT_SOURCE_DIR}/archive_deps.cmake)

# 2. Download ChaN's FatFs (Filesystem Engine)
FetchContent_Declare(
        fatfs
        GIT_REPOSITORY https://github.com/stm32duino/FatFs.git
        GIT_TAG        cef1acad37d563e6b7dfd1c4fd3d48e7ff348947 # 4.0.4
)
FetchContent_MakeAvailable(fatfs)

# 3. Download Tuxera NTFS-3G (NTFS Filesystem Engine)
FetchContent_Declare(
        ntfs3g
        GIT_REPOSITORY https://github.com/tuxera/ntfs-3g.git
        GIT_TAG        d327833ec1d5eb1358b6f2c37139f10a3460944d
)
FetchContent_MakeAvailable(ntfs3g)

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
add_library(e2fs_ext2fs STATIC ${E2FS_EXT2FS_SOURCES}
        ${E2FS_GENERATED_DIR}/ext2_err.c)
foreach(E2FS_TARGET e2fs_com_err e2fs_uuid e2fs_ext2fs)
    target_include_directories(${E2FS_TARGET} PRIVATE
            ${CMAKE_CURRENT_BINARY_DIR} ${E2FS_GENERATED_DIR}
            ${E2FS_SRC_DIR}/lib ${E2FS_SRC_DIR}/lib/et
            ${E2FS_SRC_DIR}/lib/uuid ${E2FS_EXT2FS_DIR})
    target_compile_definitions(${E2FS_TARGET} PRIVATE
            HAVE_CONFIG_H HAVE_SYS_TYPES_H HAVE_SYS_STAT_H HAVE_UNISTD_H
            HAVE_STDLIB_H HAVE_STRING_H HAVE_ERRNO_H HAVE_INTTYPES_H
            HAVE_SNPRINTF HAVE_STRCASECMP HAVE_STRDUP HAVE_STRNLEN
            HAVE_PREAD HAVE_PWRITE HAVE_PREAD64 HAVE_PWRITE64
            HAVE_LINUX_TYPES_H HAVE_SYS_TIME_H HAVE_GETPAGESIZE
            CRC_LE_BITS=1 CRC_BE_BITS=1 DISABLE_BACKTRACE _GNU_SOURCE)
endforeach()
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
FetchContent_MakeAvailable(cjson)

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

# Argon2 SIMD sources for x86 / x86_64
set(ARGON2_SIMD_SOURCES)
if(ANDROID_ABI MATCHES "x86")
    set(ARGON2_SIMD_SOURCES
        ${VC_ARGON2_DIR}/src/opt_sse2.c
        ${VC_ARGON2_DIR}/src/opt_avx2.c
    )
    set_source_files_properties(${VC_ARGON2_DIR}/src/opt_sse2.c PROPERTIES COMPILE_FLAGS "-msse2")
    set_source_files_properties(${VC_ARGON2_DIR}/src/opt_avx2.c PROPERTIES COMPILE_FLAGS "-mavx2")
endif()

set(MKNTFS_EMBEDDED_SOURCE ${CMAKE_CURRENT_BINARY_DIR}/mkntfs_embedded.c)
file(WRITE ${MKNTFS_EMBEDDED_SOURCE}
"#include <ntfs-3g/device.h>\nextern struct ntfs_device_operations vExplorer_ntfs_ops;\n#undef ntfs_device_default_io_ops\n#define ntfs_device_default_io_ops vExplorer_ntfs_ops\n#define VERSION \"embedded\"\n#define main vaultexplorer_mkntfs_main\n#include \"${ntfs3g_SOURCE_DIR}/ntfsprogs/mkntfs.c\"\n")

# 4. Build target
add_library(
        vaultexplorer
        SHARED
        io/virtual_block_device.cpp
        jni/jni_bridge_common.cpp
        jni/crypto_bridge.cpp
        jni/session_bridge.cpp
        jni/container_lifecycle_bridge.cpp
        jni/filesystem_bridge.cpp
        session/session_prepare.cpp
        session/bitlocker_backend.cpp
        containers/container_create.cpp
        containers/vhdx_image.cpp
        containers/vhd_image.cpp
        jni/jni_runtime.cpp
        jni/jni_callbacks.cpp
        jni/avif_bridge.cpp
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
        containers/container_header.cpp
        containers/container_utils.cpp
        containers/container_repair.cpp
        jni/archive_bridge.cpp
        jni/repair_bridge.cpp
        crypto/cipher_shim.cpp
        crypto/cascade.cpp
        crypto/kdf_table.cpp
        crypto/luks_header.cpp
        crypto/scrypt.cpp
        crypto/cryfs_block_cipher.cpp
        crypto/single_file_crypto.cpp
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
)

if(ANDROID_ABI STREQUAL "arm64-v8a")
    target_compile_options(vaultexplorer PRIVATE -march=armv8-a+crypto+sha2)
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    target_compile_options(vaultexplorer PRIVATE -mfpu=neon)
endif()

target_link_options(vaultexplorer PRIVATE
        "-Wl,-z,max-page-size=16384"
        "-Wl,-z,common-page-size=16384")

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

find_library(log-lib log)

target_link_libraries(
        vaultexplorer
        ${log-lib}
        z
        mbedcrypto
        crypto
        e2fs_ext2fs
        e2fs_com_err
        e2fs_uuid
        cjson
        dislocker_lib
        avif
        libgav1_static
        ${ARCHIVE_ENGINE_LIBRARY})


set_source_files_properties(
        crypto/cryfs_block_cipher.cpp
        crypto/eme.cpp
        crypto/siv.cpp
        crypto/xchacha20poly1305.cpp
        jni/crypto_bridge.cpp
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
    add_executable(kdf_table_test crypto/test/kdf_table_test.cpp crypto/kdf_table.cpp)
    add_executable(decrypted_block_cache_test io/test/decrypted_block_cache_test.cpp)
    add_executable(cryfs_block_cipher_test
            crypto/test/cryfs_block_cipher_test.cpp
            crypto/cryfs_block_cipher.cpp
            crypto/xchacha20poly1305.cpp)
    target_link_libraries(cryfs_block_cipher_test mbedcrypto)
    # Header-only (crypto/utf16le_password.h is all `static inline`), so no
    # extra .cpp sources or link libraries needed. Regression coverage for
    # the OOB read fixed in dislocker/encoding.c::toutf16() and for the
    # CESU-8/emoji password behavior documented in the header.
    add_executable(utf16le_password_test crypto/test/utf16le_password_test.cpp)
    # These three had been sitting on disk with a working, self-documented
    # `g++ -std=c++17 ...` build command in their own header comment, but no
    # add_executable/add_test entry here -- so `ctest` never ran them and
    # nothing caught that gap. Verified compiling and passing standalone
    # with that exact command before wiring in below.
    add_executable(container_header_test
            containers/test/container_header_test.cpp
            containers/container_header.cpp)
    add_executable(container_utils_crc32_test containers/test/container_utils_crc32_test.cpp)
    add_executable(chunked_block_device_test
            containers/test/chunked_block_device_test.cpp
            containers/chunked_block_device.cpp)

    # archive_engine.cpp is deliberately independent of libarchive's
    # Android/FetchContent vendoring above -- it just needs *a* libarchive
    # to link against, so the host test links whatever's installed on the
    # machine running `cmake --build .` (e.g. `apt-get install
    # libarchive-dev`) rather than pulling in the full archive_deps.cmake
    # vendoring chain. Skips gracefully, rather than failing configure, if
    # no libarchive is present on this host.
    find_package(LibArchive)
    if(LibArchive_FOUND)
        add_executable(archive_engine_test
                archive/test/archive_engine_test.cpp
                archive/archive_engine.cpp)
        target_include_directories(archive_engine_test PRIVATE ${LibArchive_INCLUDE_DIRS})
        target_link_libraries(archive_engine_test ${LibArchive_LIBRARIES})
        list(APPEND VAULTEXPLORER_HOST_TESTS archive_engine_test)
    else()
        message(STATUS "libarchive not found on this host -- skipping archive_engine_test (install libarchive-dev to enable it)")
    endif()

    set(VAULTEXPLORER_HOST_TESTS
            sector_batching_test
            fs_scan_test
            kdf_table_test
            decrypted_block_cache_test
            cryfs_block_cipher_test
            utf16le_password_test
            container_header_test
            container_utils_crc32_test
            chunked_block_device_test
            ${VAULTEXPLORER_HOST_TESTS})
    list(REMOVE_DUPLICATES VAULTEXPLORER_HOST_TESTS)

    foreach(host_test ${VAULTEXPLORER_HOST_TESTS})
        target_compile_options(${host_test} PRIVATE -Wall -Wextra)
        if(VAULTEXPLORER_ENABLE_SANITIZERS)
            target_compile_options(${host_test} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer -g)
            target_link_options(${host_test} PRIVATE -fsanitize=address,undefined)
        endif()
    endforeach()

    enable_testing()
    add_test(NAME sector_batching_test COMMAND sector_batching_test)
    add_test(NAME fs_scan_test COMMAND fs_scan_test)
    add_test(NAME kdf_table_test COMMAND kdf_table_test)
    add_test(NAME decrypted_block_cache_test COMMAND decrypted_block_cache_test)
    add_test(NAME cryfs_block_cipher_test COMMAND cryfs_block_cipher_test)
    add_test(NAME utf16le_password_test COMMAND utf16le_password_test)
    add_test(NAME container_header_test COMMAND container_header_test)
    add_test(NAME container_utils_crc32_test COMMAND container_utils_crc32_test)
    add_test(NAME chunked_block_device_test COMMAND chunked_block_device_test)
    if(TARGET archive_engine_test)
        add_test(NAME archive_engine_test COMMAND archive_engine_test)
    endif()
endif()