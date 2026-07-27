#!/usr/bin/env bash
# Builds libavcodec/avformat/avutil/swscale/swresample from FFmpeg source for
# every Android ABI the app ships. Invoked automatically by
# android/app/build.gradle.kts (preBuild) and by the F-Droid build recipe
# (metadata/com.aeidolon.vaultexplorer.yml) -- the resulting .so files are
# NOT committed to the repo (see android/app/src/main/cpp/ffmpeg/.gitignore).
set -euo pipefail

cd "$(dirname "$0")"
PROJECT_ROOT="$(cd .. && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/android/app/src/main/cpp/ffmpeg"
FFMPEG_VERSION="8.1.2"
FFMPEG_TARBALL="ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_URL="https://ffmpeg.org/releases/${FFMPEG_TARBALL}"

# TODO: fill in the official sha256 from https://ffmpeg.org/releases/${FFMPEG_TARBALL}.sha256
# before shipping. Left blank here because this environment could not reach
# ffmpeg.org to fetch it. Do not remove this check for a real release --
# F-Droid and Play both expect fetched build inputs to be integrity-checked.
FFMPEG_SHA256=""

NDK_VERSION="r26d"
ABIS="arm64-v8a armeabi-v7a x86_64 x86"
API=24

# --- Idempotency: skip entirely if every ABI already has its .so files ---
all_present=true
for ABI in $ABIS; do
  for LIB in avcodec avformat avutil swscale swresample; do
    [ -f "$OUTPUT_DIR/$ABI/lib/lib${LIB}.so" ] || all_present=false
  done
done
if [ "$all_present" = true ]; then
  echo "ffmpeg libs already built for all ABIs, skipping."
  exit 0
fi

# 1. NDK Setup (Use ANDROID_NDK_HOME if defined, otherwise fallback to local $HOME download)
if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "$ANDROID_NDK_HOME" ]; then
  echo "Using system NDK from ANDROID_NDK_HOME: $ANDROID_NDK_HOME"
  NDK_PATH="$ANDROID_NDK_HOME"
else
  NDK_DIR="$HOME/android-ndk-${NDK_VERSION}"
  if [ ! -d "$NDK_DIR" ]; then
    echo "Downloading Android NDK ${NDK_VERSION} to $HOME ..."
    wget -c -P "$HOME" "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
    echo "Unzipping NDK into $HOME (this might take a minute)..."
    unzip -q "$HOME/android-ndk-${NDK_VERSION}-linux.zip" -d "$HOME/"
  fi
  NDK_PATH="$NDK_DIR"
fi

export PATH="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"

# 2. Download + verify FFmpeg source
if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
  if [ ! -f "$FFMPEG_TARBALL" ]; then
    echo "Downloading FFmpeg source..."
    wget -c "$FFMPEG_URL"
  fi
  if [ -n "$FFMPEG_SHA256" ]; then
    echo "${FFMPEG_SHA256}  ${FFMPEG_TARBALL}" | sha256sum -c -
  else
    echo "WARNING: FFMPEG_SHA256 is unset, skipping integrity check. Fill it in before release." >&2
  fi
  tar xf "$FFMPEG_TARBALL"
fi

build_arch() {
    TARGET_ABI=$1

    # Check if already built for this specific ABI
    local present=true
    for LIB in avcodec avformat avutil swscale swresample; do
      [ -f "$OUTPUT_DIR/$TARGET_ABI/lib/lib${LIB}.so" ] || present=false
    done
    if [ "$present" = true ]; then
      echo "ffmpeg already built for $TARGET_ABI, skipping."
      return
    fi

    echo "==========================================="
    echo "Building for $TARGET_ABI..."
    echo "==========================================="

    EXTRA_FLAGS=""

    case "$TARGET_ABI" in
        "x86_64")
            CFN="x86_64-linux-android${API}-clang"
            ARCH="x86_64"
            EXTRA_FLAGS="--disable-asm"
            ;;
        "x86")
            CFN="i686-linux-android${API}-clang"
            ARCH="i686"
            EXTRA_FLAGS="--disable-asm"
            ;;
        "arm64-v8a")
            CFN="aarch64-linux-android${API}-clang"
            ARCH="aarch64"
            ;;
        "armeabi-v7a")
            CFN="armv7a-linux-androideabi${API}-clang"
            ARCH="arm"
            ;;
        *)
            echo "Unknown architecture $TARGET_ABI"
            exit 1
            ;;
    esac

    (
      cd "ffmpeg-${FFMPEG_VERSION}"
      make clean > /dev/null 2>&1 || true
      rm -f config.h config.mak

      ./configure \
          --prefix="$OUTPUT_DIR/$TARGET_ABI" \
          --cc="$CFN" \
          --cxx="$CFN++" \
          --arch="$ARCH" \
          $EXTRA_FLAGS \
          --target-os=android \
          --enable-cross-compile \
          --disable-static \
          --enable-shared \
          --disable-stripping \
          --disable-doc \
          --disable-programs \
          --disable-everything \
          --enable-decoder=h264,hevc,vp8,vp9,av1,mpeg4,mpeg2video,mjpeg,gif,webp \
          --enable-decoder=aac,mp3,opus,vorbis,flac,pcm_s16le,pcm_s24le,ac3,eac3,dts \
          --enable-demuxer=mp4,matroska,avi,mov,webm,flv,mpegts,ogg,wav,flac,mp3,aac \
          --enable-parser=h264,hevc,vp8,vp9,av1,mpegaudio,aac \
          --enable-hwaccel=h264_mediacodec,hevc_mediacodec,vp8_mediacodec,vp9_mediacodec,av1_mediacodec \
          --enable-mediacodec \
          --enable-jni \
          --enable-protocol=file,pipe \
          --disable-network \
          --enable-swscale \
          --enable-swresample \
          --disable-vulkan \
          --disable-avdevice \
          --disable-avfilter \
          --extra-cflags="-O3 -fPIC" \
          --extra-ldflags="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"

      make -j"$(nproc 2>/dev/null || echo 4)"
      make install
    )
}

# Build all 4 standard Android architectures
build_arch "arm64-v8a"
build_arch "armeabi-v7a"
build_arch "x86_64"
build_arch "x86"

echo "==========================================="
echo "Build complete! Libraries installed to:"
echo "$OUTPUT_DIR"
echo "==========================================="