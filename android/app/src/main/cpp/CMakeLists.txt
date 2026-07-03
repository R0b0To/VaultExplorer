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

# 2b. Local VeraCrypt Directory Configuration
# Since you have copied the 'Crypto' and 'Common' folders locally to 
# 'android/app/src/main/cpp/veracrypt/' (where this CMakeLists.txt lives):
set(VC_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/veracrypt)
set(VC_CRYPTO_DIR ${VC_SRC_DIR}/Crypto)
set(VC_COMMON_DIR ${VC_SRC_DIR}/Common)

# 3. Build target: FatFs + our code + vendored crypto primitives
add_library(
        vaultexplorer
        SHARED
        vaultexplorer.cpp
        crypto/cipher_shim.cpp     # adapter — isolates us from upstream fn-signature drift
        crypto/cascade.cpp         # cipher-agnostic XTS + cascade chaining
        crypto/kdf_table.cpp       # per-hash iteration-count table + hash dispatch
        ${fatfs_SOURCE_DIR}/src/ff.c
        ${fatfs_SOURCE_DIR}/src/ffunicode.c
        # ── Locally Vendored primitives (No longer fetched via Git) ──
        ${VC_CRYPTO_DIR}/Twofish.c
        ${VC_CRYPTO_DIR}/Serpent.c
        ${VC_CRYPTO_DIR}/Whirlpool.c
        ${VC_CRYPTO_DIR}/Streebog.c
        ${VC_CRYPTO_DIR}/blake2s.c
        ${VC_CRYPTO_DIR}/cpu.c 
        ${VC_COMMON_DIR}/Endian.c 
)

target_compile_definitions(vaultexplorer PRIVATE
        CRYPTOPP_DISABLE_ASM  # Disables x86 assembly on ARM 
        CRYPTOPP_DISABLE_SSE2
        CRYPTOPP_DISABLE_SSSE3
)

# 4. Header search paths
target_include_directories(
        vaultexplorer PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/crypto
        ${mbedtls_SOURCE_DIR}/include
        ${fatfs_SOURCE_DIR}/src
        ${VC_CRYPTO_DIR}
        ${VC_SRC_DIR}         # Resolves #include "Common/..." and "Crypto/..."
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
    enable_testing()
    add_test(NAME sector_batching_test COMMAND sector_batching_test)
    add_test(NAME fs_scan_test COMMAND fs_scan_test)
    add_test(NAME cascade_test COMMAND cascade_test)
endif()