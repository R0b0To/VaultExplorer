# ─────────────────────────────────────────────────────────────────────────
# BitLocker support: Dislocker (https://github.com/Aorimn/dislocker)
#
# Unlike the previous libbde (libyal) backend, dislocker supports both
# read AND write (decrypt + re-encrypt) via its dislock()/enlock() API.
#
# The upstream sources are fetched via FetchContent, then the app's own
# patched files (android/app/src/main/cpp/dislocker/) are copied on top
# to add the virtual I/O backend -- see virtual_io.h for the design.
# ─────────────────────────────────────────────────────────────────────────

FetchContent_Declare(
    dislocker_upstream
    GIT_REPOSITORY https://github.com/Aorimn/dislocker.git
    GIT_TAG        master
)
FetchContent_GetProperties(dislocker_upstream)
if(NOT dislocker_upstream_POPULATED)
    FetchContent_Populate(dislocker_upstream)
endif()

set(DISLOCKER_SRC ${dislocker_upstream_SOURCE_DIR}/src)
set(DISLOCKER_INC ${dislocker_upstream_SOURCE_DIR}/include)
set(DISLOCKER_PATCHES ${CMAKE_CURRENT_SOURCE_DIR}/dislocker)

# ── Overlay our patched files onto the fetched source tree ──────────────
# These are the files from the user's virtual_io patch set. They modify
# existing dislocker files (to route I/O through dis_virtual_io_t) and
# add one new source file (virtual_io.c). Using file(COPY) during
# configure means the patched versions are what actually get compiled.
file(COPY ${DISLOCKER_PATCHES}/common.c    DESTINATION ${DISLOCKER_SRC})
file(COPY ${DISLOCKER_PATCHES}/config.c    DESTINATION ${DISLOCKER_SRC})
file(COPY ${DISLOCKER_PATCHES}/dislocker.c DESTINATION ${DISLOCKER_SRC})
file(COPY ${DISLOCKER_PATCHES}/sectors.c   DESTINATION ${DISLOCKER_SRC}/inouts)
file(COPY ${DISLOCKER_PATCHES}/virtual_io.c DESTINATION ${DISLOCKER_SRC})
file(COPY ${DISLOCKER_PATCHES}/encoding.c  DESTINATION ${DISLOCKER_SRC}/ntfs)

# Headers go into the include tree so #include "dislocker/..." resolves.
file(COPY ${DISLOCKER_PATCHES}/common.h      DESTINATION ${DISLOCKER_INC}/dislocker)
file(COPY ${DISLOCKER_PATCHES}/config.h      DESTINATION ${DISLOCKER_INC}/dislocker)
file(COPY ${DISLOCKER_PATCHES}/config.priv.h DESTINATION ${DISLOCKER_INC}/dislocker)
file(COPY ${DISLOCKER_PATCHES}/virtual_io.h  DESTINATION ${DISLOCKER_INC}/dislocker)

# ── Patch metadata.c to support negative virtual fds ─────────────────────
file(READ ${DISLOCKER_SRC}/metadata/metadata.c METADATA_C)
string(REPLACE "fd < 0" "fd == -1" METADATA_C "${METADATA_C}")
string(REPLACE "volume_fd < 0" "volume_fd == -1" METADATA_C "${METADATA_C}")
file(WRITE ${DISLOCKER_SRC}/metadata/metadata.c "${METADATA_C}")

# ── Library sources (no CLI tools, no FUSE, no Ruby) ────────────────────
set(DISLOCKER_LIB_SOURCES
    ${DISLOCKER_SRC}/dislocker.c
    ${DISLOCKER_SRC}/common.c
    ${DISLOCKER_SRC}/config.c
    ${DISLOCKER_SRC}/virtual_io.c
    ${DISLOCKER_SRC}/xstd/xstdio.c
    ${DISLOCKER_SRC}/xstd/xstdlib.c
    ${DISLOCKER_SRC}/metadata/datums.c
    ${DISLOCKER_SRC}/metadata/metadata.c
    ${DISLOCKER_SRC}/metadata/vmk.c
    ${DISLOCKER_SRC}/metadata/fvek.c
    ${DISLOCKER_SRC}/metadata/extended_info.c
    ${DISLOCKER_SRC}/metadata/guid.c
    ${DISLOCKER_SRC}/metadata/print_metadata.c
    ${DISLOCKER_SRC}/accesses/stretch_key.c
    ${DISLOCKER_SRC}/accesses/accesses.c
    ${DISLOCKER_SRC}/accesses/rp/recovery_password.c
    ${DISLOCKER_SRC}/accesses/user_pass/user_pass.c
    ${DISLOCKER_SRC}/accesses/bek/bekfile.c
    ${DISLOCKER_SRC}/encryption/encommon.c
    ${DISLOCKER_SRC}/encryption/decrypt.c
    ${DISLOCKER_SRC}/encryption/encrypt.c
    ${DISLOCKER_SRC}/encryption/diffuser.c
    ${DISLOCKER_SRC}/encryption/crc32.c
    ${DISLOCKER_SRC}/encryption/aes-xts.c
    ${DISLOCKER_SRC}/ntfs/clock.c
    ${DISLOCKER_SRC}/ntfs/encoding.c
    ${DISLOCKER_SRC}/inouts/inouts.c
    ${DISLOCKER_SRC}/inouts/prepare.c
    ${DISLOCKER_SRC}/inouts/sectors.c
)

add_library(dislocker_lib STATIC ${DISLOCKER_LIB_SOURCES})

target_include_directories(dislocker_lib PUBLIC
    ${DISLOCKER_INC}
    ${mbedtls_SOURCE_DIR}/include
)

target_compile_definitions(dislocker_lib PRIVATE
    PROGNAME="dislocker"
    AUTHOR="Romain_Coltel"
    VERSION="master-vaultexplorer"
    _FILE_OFFSET_BITS=64
    _GNU_SOURCE
    __LINUX
    __OS="Android"
    __ARCH="aarch64"
    __ARCH_X86_64
    # Disable core dump restriction (we're in an Android app, not a
    # security-sensitive standalone tool)
    __DIS_CORE_DUMPS
)

# Suppress warnings in upstream C code that we don't want to fix
target_compile_options(dislocker_lib PRIVATE
    -Wno-sign-conversion
    -Wno-conversion
    -Wno-pointer-sign
    -Wno-unused-parameter
    -Wno-missing-field-initializers
    -Wno-format
)

target_link_libraries(dislocker_lib PRIVATE mbedcrypto)

# Public include path for consumers (bitlocker_backend.cpp)
set(DISLOCKER_INCLUDE_DIRS
    ${DISLOCKER_INC}
    CACHE INTERNAL "dislocker public include dirs"
)
