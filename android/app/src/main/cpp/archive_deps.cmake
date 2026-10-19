# ─────────────────────────────────────────────────────────────────────────
# Archive engine: libarchive (https://github.com/libarchive/libarchive)
#
# Powers the native ZIP/RAR4/RAR5/7-Zip/TAR archive browser (see
# archive/archive_engine.h) that replaces the pure-Dart `archive` package.
# ─────────────────────────────────────────────────────────────────────────

# ── bzip2 ───────────────────────────────────────────────────────────────
FetchContent_Declare(
    bzip2_upstream
    GIT_REPOSITORY https://github.com/libarchive/bzip2.git
    GIT_TAG        bzip2-1.0.8
)
FetchContent_GetProperties(bzip2_upstream)
if(NOT bzip2_upstream_POPULATED)
    FetchContent_Populate(bzip2_upstream)
endif()

add_library(bz2_static STATIC
    ${bzip2_upstream_SOURCE_DIR}/blocksort.c
    ${bzip2_upstream_SOURCE_DIR}/huffman.c
    ${bzip2_upstream_SOURCE_DIR}/crctable.c
    ${bzip2_upstream_SOURCE_DIR}/randtable.c
    ${bzip2_upstream_SOURCE_DIR}/compress.c
    ${bzip2_upstream_SOURCE_DIR}/decompress.c
    ${bzip2_upstream_SOURCE_DIR}/bzlib.c
)
target_include_directories(bz2_static PUBLIC ${bzip2_upstream_SOURCE_DIR})
target_compile_definitions(bz2_static PRIVATE _FILE_OFFSET_BITS=64)
target_compile_options(bz2_static PRIVATE -Wno-unused-but-set-variable)

# ── xz / liblzma ──────────────────────────────────────────────────────
FetchContent_Declare(
    xz_upstream
    GIT_REPOSITORY https://github.com/tukaani-project/xz.git
    GIT_TAG        4b73f2ec19a99ef465282fbce633e8deb33691b3 # v5.8.3
)
set(BUILD_TESTING OFF CACHE BOOL "Disable xz tests" FORCE)
set(XZ_NLS OFF CACHE BOOL "Disable xz translations" FORCE)
set(XZ_DOC OFF CACHE BOOL "Disable xz documentation" FORCE)
set(XZ_TOOL_XZ OFF CACHE BOOL "Disable the xz CLI tool" FORCE)
set(XZ_TOOL_XZDEC OFF CACHE BOOL "Disable the xzdec CLI tool" FORCE)
set(XZ_TOOL_LZMADEC OFF CACHE BOOL "Disable the lzmadec CLI tool" FORCE)
set(XZ_TOOL_LZMAINFO OFF CACHE BOOL "Disable the lzmainfo CLI tool" FORCE)
set(XZ_TOOL_SCRIPTS OFF CACHE BOOL "Disable xz's helper scripts" FORCE)
FetchContent_MakeAvailable(xz_upstream)
if(TARGET liblzma)
    target_include_directories(liblzma INTERFACE $<BUILD_INTERFACE:${xz_upstream_SOURCE_DIR}/src/liblzma/api>)
endif()

# ── zstd ──────────────────────────────────────────────────────────────
FetchContent_Declare(
    zstd_upstream
    GIT_REPOSITORY https://github.com/facebook/zstd.git
    GIT_TAG        f8745da6ff1ad1e7bab384bd1f9d742439278e99 # v1.5.7
    SOURCE_SUBDIR  build/cmake
)
set(ZSTD_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(ZSTD_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_CONTRIB OFF CACHE BOOL "" FORCE)
set(ZSTD_MULTITHREAD_SUPPORT OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(zstd_upstream)

# ── Pre-seed libarchive's own find_package() & check results ───────────

# 1. BZip2
set(BZIP2_FOUND TRUE CACHE BOOL "" FORCE)
set(BZIP2_INCLUDE_DIR ${bzip2_upstream_SOURCE_DIR} CACHE PATH "" FORCE)
set(BZIP2_LIBRARIES bz2_static CACHE STRING "" FORCE)
set(BZIP2_NEED_PREFIX FALSE CACHE BOOL "" FORCE)
set(HAVE_LIBBZ2 1 CACHE BOOL "" FORCE)
set(HAVE_BZLIB_H 1 CACHE BOOL "" FORCE)

# 2. LibLZMA (xz)
set(LIBLZMA_FOUND TRUE CACHE BOOL "" FORCE)
set(LibLZMA_FOUND TRUE CACHE BOOL "" FORCE)
set(LIBLZMA_INCLUDE_DIR ${xz_upstream_SOURCE_DIR}/src/liblzma/api CACHE PATH "" FORCE)
set(LIBLZMA_INCLUDE_DIRS ${xz_upstream_SOURCE_DIR}/src/liblzma/api CACHE PATH "" FORCE)
set(LIBLZMA_LIBRARY liblzma CACHE STRING "" FORCE)
set(LIBLZMA_LIBRARIES liblzma CACHE STRING "" FORCE)
set(LIBLZMA_HAS_AUTO_DECODER TRUE CACHE BOOL "" FORCE)
set(LIBLZMA_HAS_EASY_ENCODER TRUE CACHE BOOL "" FORCE)
set(LIBLZMA_HAS_LZMA_PRESET TRUE CACHE BOOL "" FORCE)
set(HAVE_LIBLZMA 1 CACHE BOOL "" FORCE)
set(HAVE_LZMA_H 1 CACHE BOOL "" FORCE)
set(HAVE_LZMA_AUTO_DECODER 1 CACHE BOOL "" FORCE)
set(HAVE_LZMA_EASY_ENCODER 1 CACHE BOOL "" FORCE)
set(HAVE_LZMA_LZMA_PRESET 1 CACHE BOOL "" FORCE)
set(HAVE_LZMA_STREAM_ENCODER_MT 1 CACHE BOOL "" FORCE)

# 3. ZSTD
set(ZSTD_FOUND TRUE CACHE BOOL "" FORCE)
set(ZSTD_INCLUDE_DIR ${zstd_upstream_SOURCE_DIR}/lib CACHE PATH "" FORCE)
set(ZSTD_LIBRARY libzstd_static CACHE STRING "" FORCE)
set(HAVE_ZSTD_H 1 CACHE BOOL "" FORCE)
set(HAVE_LIBZSTD 1 CACHE BOOL "" FORCE)
set(HAVE_ZSTD_compressStream 1 CACHE BOOL "" FORCE)
set(HAVE_ZSTD_minCLevel 1 CACHE BOOL "" FORCE)

# 4. OpenSSL / BoringSSL
set(OPENSSL_FOUND TRUE CACHE BOOL "" FORCE)
set(OpenSSL_FOUND TRUE CACHE BOOL "" FORCE)
set(OPENSSL_INCLUDE_DIR ${boringssl_SOURCE_DIR}/include CACHE PATH "" FORCE)
set(OPENSSL_CRYPTO_LIBRARY crypto CACHE STRING "" FORCE)
set(OPENSSL_CRYPTO_LIBRARIES crypto CACHE STRING "" FORCE)
set(OPENSSL_SSL_LIBRARY ssl CACHE STRING "" FORCE)
set(OPENSSL_LIBRARIES crypto CACHE STRING "" FORCE)
set(OPENSSL_VERSION "1.1.1" CACHE STRING "" FORCE)
set(HAVE_LIBCRYPTO 1 CACHE BOOL "" FORCE)
set(HAVE_OPENSSL_EVP_H 1 CACHE BOOL "" FORCE)
set(HAVE_OPENSSL_OPENSSLV_H 1 CACHE BOOL "" FORCE)
set(HAVE_PKCS5_PBKDF2_HMAC_SHA1 1 CACHE BOOL "" FORCE)

# 5. Pre-seed crypto algorithms so CHECK_CRYPTO skips TRY_COMPILE entirely
set(ARCHIVE_CRYPTO_MD5 1 CACHE BOOL "" FORCE)
set(ARCHIVE_CRYPTO_MD5_OPENSSL 1 CACHE BOOL "" FORCE)
set(ARCHIVE_CRYPTO_SHA1 1 CACHE BOOL "" FORCE)
set(ARCHIVE_CRYPTO_SHA1_OPENSSL 1 CACHE BOOL "" FORCE)
set(ARCHIVE_CRYPTO_SHA256 1 CACHE BOOL "" FORCE)
set(ARCHIVE_CRYPTO_SHA256_OPENSSL 1 CACHE BOOL "" FORCE)
set(ARCHIVE_CRYPTO_SHA384 1 CACHE BOOL "" FORCE)
set(ARCHIVE_CRYPTO_SHA384_OPENSSL 1 CACHE BOOL "" FORCE)
set(ARCHIVE_CRYPTO_SHA512 1 CACHE BOOL "" FORCE)
set(ARCHIVE_CRYPTO_SHA512_OPENSSL 1 CACHE BOOL "" FORCE)
set(ARCHIVE_CRYPTO_RMD160 0 CACHE BOOL "" FORCE)
set(ARCHIVE_CRYPTO_RMD160_OPENSSL 0 CACHE BOOL "" FORCE)
set(ARCHIVE_CRYPTO_RMD160_LIBMD 0 CACHE BOOL "" FORCE)

# 6. Disable libmd checks
set(LIBMD_FOUND FALSE CACHE BOOL "" FORCE)
set(LIBMD_LIBRARY "" CACHE STRING "" FORCE)

# ── libarchive itself ─────────────────────────────────────────────────
# libarchive's 7-Zip writer accepts a passphrase but never encrypts, and its
# reader refuses encrypted streams. This patch adds 7zAES (AES-256-CBC with
# 7-Zip's SHA-256 key derivation) to both. The script resets the fetched tree
# before applying, so re-configuring is safe, and fails configure if the patch
# stops applying (e.g. after a libarchive version bump).
#
# The patch file is declared a configure dependency: otherwise an incremental
# build (Ninja, as used by Gradle) never notices an edited patch, keeps the
# previously patched libarchive and links it against the newer engine code, so
# features added in the patch fail at runtime with "Undefined option".
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_LIST_DIR}/archive/patches/libarchive-7zip-encryption.patch"
    "${CMAKE_CURRENT_LIST_DIR}/archive/patches/apply_patch_once.cmake"
    "${CMAKE_CURRENT_LIST_DIR}/archive/patches/rar5_crypt_core.inc"
    "${CMAKE_CURRENT_LIST_DIR}/archive/patches/rar5_crypt_parse.inc")
FetchContent_Declare(
    libarchive_upstream
    GIT_REPOSITORY https://github.com/libarchive/libarchive.git
    GIT_TAG        27cbc7827172698143e440801fc0ba39ccb4f1f5 # v3.8.9
    PATCH_COMMAND  ${CMAKE_COMMAND}
                   -DPATCH_FILE=${CMAKE_CURRENT_LIST_DIR}/archive/patches/libarchive-7zip-encryption.patch
                   -P ${CMAKE_CURRENT_LIST_DIR}/archive/patches/apply_patch_once.cmake
)

# Formats/filters required
set(ENABLE_ZLIB   ON  CACHE BOOL "" FORCE)  # gzip -- via NDK's system libz
set(ENABLE_BZip2  ON  CACHE BOOL "" FORCE)  # bzip2 -- vendored above
set(ENABLE_LZMA   ON  CACHE BOOL "" FORCE)  # xz/lzma -- vendored above
set(ENABLE_ZSTD   ON  CACHE BOOL "" FORCE)  # zstd -- vendored above
set(ENABLE_OPENSSL ON CACHE BOOL "" FORCE)  # AES-256 ZIP / RAR5 passphrases

# Disabled unnecessary backends
set(ENABLE_LZ4      OFF CACHE BOOL "" FORCE)
set(ENABLE_LZO      OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBB2    OFF CACHE BOOL "" FORCE)
set(ENABLE_MBEDTLS  OFF CACHE BOOL "" FORCE)
set(ENABLE_NETTLE   OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBXML2  OFF CACHE BOOL "" FORCE)
set(ENABLE_EXPAT    OFF CACHE BOOL "" FORCE)
set(ENABLE_PCREPOSIX OFF CACHE BOOL "" FORCE)
set(ENABLE_PCRE2POSIX OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBGCC   OFF CACHE BOOL "" FORCE)
set(ENABLE_CNG      OFF CACHE BOOL "" FORCE)
set(ENABLE_XATTR    OFF CACHE BOOL "" FORCE)
set(ENABLE_ACL      OFF CACHE BOOL "" FORCE)
set(ENABLE_ICONV    OFF CACHE BOOL "" FORCE)

# CLI tools
set(ENABLE_TAR   OFF CACHE BOOL "" FORCE)
set(ENABLE_CPIO  OFF CACHE BOOL "" FORCE)
set(ENABLE_CAT   OFF CACHE BOOL "" FORCE)
set(ENABLE_UNZIP OFF CACHE BOOL "" FORCE)

set(ENABLE_TEST    OFF CACHE BOOL "" FORCE)
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(ENABLE_WERROR  OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(libarchive_upstream)

# Re-apply patches whenever apply_patch_once.cmake or the patch changes, even inside an existing .cxx build tree
execute_process(
    COMMAND ${CMAKE_COMMAND}
            -DPATCH_FILE=${CMAKE_CURRENT_LIST_DIR}/archive/patches/libarchive-7zip-encryption.patch
            -P ${CMAKE_CURRENT_LIST_DIR}/archive/patches/apply_patch_once.cmake
    WORKING_DIRECTORY ${libarchive_upstream_SOURCE_DIR}
    RESULT_VARIABLE apply_patch_res
)
if(NOT apply_patch_res EQUAL 0)
    message(FATAL_ERROR "Failed to patch libarchive sources")
endif()

set(ARCHIVE_ENGINE_LIBRARY archive_static CACHE INTERNAL "libarchive target to link against")
set(ARCHIVE_ENGINE_INCLUDE_DIRS
    ${libarchive_upstream_SOURCE_DIR}/libarchive
    CACHE INTERNAL "libarchive public headers")
