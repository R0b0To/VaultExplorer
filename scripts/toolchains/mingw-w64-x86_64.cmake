# Cross-compile the desktop engine for 64-bit Windows from Linux with MinGW-w64 (the "posix" thread
# model, which provides std::mutex / std::thread / pthreads).
#
#   sudo apt install g++-mingw-w64-x86-64-posix gcc-mingw-w64-x86-64-posix
#   cmake -S android/app/src/main/cpp -B build/desktop-engine-win -G Ninja \
#         -DCMAKE_TOOLCHAIN_FILE=scripts/toolchains/mingw-w64-x86_64.cmake -DVAULTEXPLORER_DESKTOP=ON
#
# On Windows itself, use the MSYS2 UCRT64 shell instead (no toolchain file needed).
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc-posix)
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++-posix)
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres)
set(CMAKE_FIND_ROOT_PATH /usr/x86_64-w64-mingw32)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
