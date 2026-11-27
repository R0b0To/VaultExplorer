#!/bin/sh
# Regenerates the tiny test videos used by video_thumb_test.cpp (needs an ffmpeg with libx264, libx265, libvpx-vp9,
# libaom-av1, mpeg4, mpeg2video, aac). They are checked in, so this only matters if you change them.
#
# Every video shows four flat quadrants: top-left red, top-right green, bottom-left blue, bottom-right yellow,
# 160x90, 10 fps, a keyframe every second. The test checks the colours it gets back against that, so a
# wrong rotation, a wrong colour matrix or a wrong frame is visible.
set -e
W=160; H=90
QUAD="color=c=red:s=${W}x${H}:d=3,format=yuv420p,drawbox=x=${W}/2:y=0:w=${W}/2:h=${H}/2:color=lime:t=fill,drawbox=x=0:y=${H}/2:w=${W}/2:h=${H}/2:color=blue:t=fill,drawbox=x=${W}/2:y=${H}/2:w=${W}/2:h=${H}/2:color=yellow:t=fill"
Q="-hide_banner -loglevel error -y -f lavfi -i $QUAD -r 10 -an"
ffmpeg $Q -c:v libx264 -g 10 -pix_fmt yuv420p -crf 28 h264.mp4
ffmpeg $Q -c:v libx265 -x265-params log-level=error:keyint=10 -pix_fmt yuv420p -crf 30 hevc.mp4
ffmpeg $Q -c:v libvpx-vp9 -g 10 -b:v 80k webm_vp9.webm
ffmpeg $Q -c:v libx264 -g 10 -pix_fmt yuv420p -crf 28 h264.mkv
ffmpeg $Q -c:v mpeg4 -g 10 -q:v 6 mpeg4.avi
ffmpeg $Q -c:v mpeg2video -g 10 -q:v 6 mpeg2.mpg
ffmpeg $Q -c:v libx264 -g 10 -pix_fmt yuv420p -crf 28 -t 1.5 -f mpegts h264.ts
ffmpeg $Q -c:v libaom-av1 -cpu-used 8 -g 10 -crf 40 -b:v 0 av1.mp4      # a codec this build does not decode
# black for 1.5 s, then the quadrants: the first frame is blank, so 'hybrid' has to retry
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "color=c=black:s=${W}x${H}:d=1.5" -f lavfi -i "$QUAD" \
  -filter_complex "[0:v]format=yuv420p[a];[1:v]format=yuv420p[b];[a][b]concat=n=2:v=1[o]" -map "[o]" -r 10 -an \
  -c:v libx264 -g 5 -pix_fmt yuv420p -crf 28 black_start.mp4
# phone-style: stored landscape, rotation in the container
ffmpeg -hide_banner -loglevel error -y -display_rotation 90 -i h264.mp4 -c copy rot90.mp4    # 90 CCW
ffmpeg -hide_banner -loglevel error -y -display_rotation -90 -i h264.mp4 -c copy rot270.mp4  # 90 CW
ffmpeg -hide_banner -loglevel error -y -display_rotation 180 -i h264.mp4 -c copy rot180.mp4
ffmpeg -hide_banner -loglevel error -y -f lavfi -i sine=d=1 -c:a aac -b:a 16k audio_only.m4a
ffmpeg $Q -c:v libx264 -g 10 -pix_fmt yuv420p -crf 28 -vf "setsar=2/1" sar2.mp4              # non-square pixels
