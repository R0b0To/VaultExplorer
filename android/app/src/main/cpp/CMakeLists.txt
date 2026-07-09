cmake_minimum_required(VERSION 3.18.0)

project("vaultexplorer")

# 1. Download mbedTLS (Encryption Engine)
include(FetchContent)
FetchContent_Declare(
        mbedtls
        GIT_REPOSITORY https://github.com/Mbed-TLS/mbedtls.git
        GIT_TAG        v3.6.0
)
set(ENABLE_TESTING OFF CACHE BOOL "Disable mbedtls tests")
set(ENABLE_PROGRAMS OFF CACHE BOOL "Disable mbedtls programs")
FetchContent_MakeAvailable(mbedtls)

# 2. Download ChaN's FatFs (Filesystem Engine)
FetchContent_Declare(
        fatfs
        GIT_REPOSITORY https://github.com/stm32duino/FatFs.git
        GIT_TAG        4.0.4
)
FetchContent_MakeAvailable(fatfs)

# 3. Download Tuxera NTFS-3G (NTFS Filesystem Engine)
FetchContent_Declare(
        ntfs3g
        GIT_REPOSITORY https://github.com/tuxera/ntfs-3g.git
        GIT_TAG        edge
)
FetchContent_MakeAvailable(ntfs3g)

# 3b. Generate a robust config.h to compile ntfs-3g natively on Android NDK
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
#define HAVE_STDARG_H 1
#define HAVE_WCHAR_H 1
#define HAVE_WCTYPE_H 1
#define HAVE_LOCALE_H 1
#define HAVE_UTIMENSAT 1
#define HAVE_SYS_SYSMACROS_H 1
#define HAVE_TIME_H 1
#define HAVE_FFS 1

// Include system macros so makedev, major, and minor are fully declared
#ifdef HAVE_SYS_SYSMACROS_H
#include <sys/sysmacros.h>
#endif

// Bionic major/minor/makedev fallbacks
#ifndef major
#define major(dev) ((int)(((dev) >> 8) & 0xff))
#endif
#ifndef minor
#define minor(dev) ((int)((dev) & 0xff))
#endif
#ifndef makedev
#define makedev(maj, min) ( (((maj) & 0xfffff000ULL) << 32) | (((maj) & 0xfffULL) << 8) | (((min) & 0xfffff000ULL) << 12) | ((min) & 0xfffULL) )
#endif

// Bionic hd_geometry fallback
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

# 3c. Local VeraCrypt Directory Configuration
set(VC_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/veracrypt)
set(VC_CRYPTO_DIR ${VC_SRC_DIR}/Crypto)
set(VC_COMMON_DIR ${VC_SRC_DIR}/Common)

# 3d. Complete NTFS-3G Source Files list
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
)

# 4. Build target: FatFs + original code + vendored crypto primitives + NTFS-3G
add_library(
        vaultexplorer
        SHARED
        vaultexplorer.cpp
        crypto/cipher_shim.cpp     # adapter
        crypto/cascade.cpp         # cipher-agnostic XTS + cascade chaining
        crypto/kdf_table.cpp       # per-hash iteration-count table + hash dispatch
        ${fatfs_SOURCE_DIR}/src/ff.c
        ${fatfs_SOURCE_DIR}/src/ffunicode.c
        # ── Locally Vendored primitives ──
        ${VC_CRYPTO_DIR}/Twofish.c
        ${VC_CRYPTO_DIR}/Serpent.c
        ${VC_CRYPTO_DIR}/Whirlpool.c
        ${VC_CRYPTO_DIR}/Streebog.c
        ${VC_CRYPTO_DIR}/blake2s.c
        ${VC_CRYPTO_DIR}/cpu.c 
        ${VC_COMMON_DIR}/Endian.c 
        # ── NTFS-3G Sources ──
        ${NTFS_3G_SOURCES}
)

target_compile_definitions(vaultexplorer PRIVATE
        CRYPTOPP_DISABLE_ASM
        CRYPTOPP_DISABLE_SSE2
        CRYPTOPP_DISABLE_SSSE3
        HAVE_CONFIG_H  # Forces NTFS-3G files to look up our generated config.h
        _GNU_SOURCE
        _FILE_OFFSET_BITS=64
)

# 5. Header search paths
target_include_directories(
        vaultexplorer PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/crypto
        ${mbedtls_SOURCE_DIR}/include
        ${fatfs_SOURCE_DIR}/src
        ${ntfs3g_SOURCE_DIR}/include
        ${ntfs3g_SOURCE_DIR}/include/ntfs-3g
        ${CMAKE_CURRENT_BINARY_DIR} # config.h location
        ${VC_CRYPTO_DIR}
        ${VC_SRC_DIR}
)

find_library(log-lib log)

target_link_libraries(
        vaultexplorer
        ${log-lib}
        mbedcrypto)

if(NOT ANDROID)
    add_executable(sector_batching_test test/sector_batching_test.cpp)
    add_executable(fs_scan_test test/fs_scan_test.cpp)
    add_executable(cascade_test test/cascade_test.cpp crypto/cascade.cpp crypto/cipher_shim.cpp
                    ${VC_CRYPTO_DIR}/Twofish.c ${VC_CRYPTO_DIR}/Serpent.c)
    add_executable(kdf_table_test crypto/test/kdf_table_test.cpp crypto/kdf_table.cpp)
    enable_testing()
    add_test(NAME sector_batching_test COMMAND sector_batching_test)
    add_test(NAME fs_scan_test COMMAND fs_scan_test)
    add_test(NAME cascade_test COMMAND cascade_test)
    add_test(NAME kdf_table_test COMMAND kdf_table_test)
endif()