#!/bin/sh
# Cross-builds a small, static ffmpeg + ffprobe for the Nokia N9 (Harmattan)
# with MADDE's own toolchain, and fetches the binaries into build/.
#
# MADDE's gcc is CodeSourcery 2009q3 / GCC 4.4.1. It already defaults to
# armv7-a, cortex-a8, NEON and hard-float, so no -m flags are passed here --
# ffmpeg's configure picks all of that up and enables the NEON asm.
#
# The toolchain ships no libc of its own; crt1.o, libc.a, libm.a and
# libpthread.a come from the MADDE Harmattan sysroot (glibc 2.10.1), which is
# exactly the device's own glibc. The result is linked -static so the phone
# needs nothing installed.
#
#   tools/build.sh            # -> build/ffmpeg, build/ffprobe
set -e
cd "$(dirname "$0")/.."

FFMPEG_BRANCH=${FFMPEG_BRANCH:-release/4.4}
REMOTE=/tmp/ffmpeg-n9

HOST=$(sh "$HOME/ps/nfsshift-sfos/tools/buildhost.sh")
echo "== build host: $HOST"

ssh "$HOST" "set -e
    TC=\$HOME/QtSDK/Madde/toolchains/arm-2009q3-67-arm-none-linux-gnueabi-x86_64-unknown-linux-gnu/arm-2009q3-67
    SR=\$HOME/QtSDK/Madde/sysroots/harmattan_sysroot_10.2011.34-1_slim

    mkdir -p $REMOTE && cd $REMOTE
    [ -d ffmpeg ] || git clone --branch $FFMPEG_BRANCH --depth 1 \
        https://git.ffmpeg.org/ffmpeg.git ffmpeg
    cd ffmpeg

    # Audio only, and only what a webm actually carries. --disable-everything
    # keeps a 2009 compiler away from 90% of the tree as much as it keeps the
    # binary small.
    #
    # aresample is not optional: ffmpeg inserts it itself for any audio
    # transcode, and without it the binary builds and then fails at runtime.
    ./configure \
        --enable-cross-compile --arch=arm --cpu=cortex-a8 --target-os=linux \
        --cross-prefix=\$TC/bin/arm-none-linux-gnueabi- --sysroot=\$SR \
        --prefix=/opt/ffmpeg \
        --disable-everything --disable-autodetect --disable-doc \
        --disable-network --disable-ffplay --disable-debug \
        --disable-shared --enable-static --enable-small \
        --extra-ldflags=-static \
        --enable-demuxer=matroska,ogg,mov,mp3,wav \
        --enable-decoder=vorbis,opus,aac,mp3,pcm_s16le \
        --enable-encoder=aac,pcm_s16le \
        --enable-muxer=ipod,mp4,ogg,wav \
        --enable-parser=vorbis,opus,aac,mpegaudio \
        --enable-bsf=aac_adtstoasc \
        --enable-filter=aresample,aformat,anull \
        --enable-protocol=file,pipe \
        > /tmp/ffmpeg-cfg.log 2>&1 || {
            echo '-- configure failed'; tail -15 /tmp/ffmpeg-cfg.log
            tail -25 ffbuild/config.log; exit 1; }

    nice make -j8 > /tmp/ffmpeg-build.log 2>&1 || {
        echo '-- build failed'
        grep -n -E 'error:|Error [0-9]' /tmp/ffmpeg-build.log | head -20; exit 1; }

    file ffmpeg ffprobe
"

echo "== fetching binaries"
rsync -a -e ssh "$HOST:$REMOTE/ffmpeg/ffmpeg" "$HOST:$REMOTE/ffmpeg/ffprobe" build/
ls -la build/ffmpeg build/ffprobe
