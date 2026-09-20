#!/bin/sh
# Runs the cross-built ARM binaries under qemu-arm on the build host and
# checks the conversions really happened.
#
# The N9 is not needed for this and is not a substitute either: qemu proves
# the code is correct, not that it is fast enough. Both binaries are static,
# so qemu needs no sysroot.
#
# Test signal is a 440 Hz sine, so the check can be more than "the file
# exists": the host ffmpeg decodes what the ARM binary wrote and the levels
# and the peak frequency have to come back out.
#
#   tools/selftest.sh
set -e
cd "$(dirname "$0")/.."

REMOTE=/tmp/ffmpeg-n9
HOST=$(sh "$HOME/ps/nfsshift-sfos/tools/buildhost.sh")
echo "== test host: $HOST"

ssh "$HOST" "set -e
    cd $REMOTE
    FF='qemu-arm ./ffmpeg/ffmpeg'
    FP='qemu-arm ./ffmpeg/ffprobe'

    ffmpeg -y -loglevel error -f lavfi -i 'sine=frequency=440:duration=5' -c:a libopus   opus.webm
    ffmpeg -y -loglevel error -f lavfi -i 'sine=frequency=440:duration=5' -c:a libvorbis vorbis.webm

    echo '-- opus webm -> aac m4a'
    \$FF -y -loglevel error -i opus.webm   -c:a aac -b:a 128k opus.m4a
    echo '-- vorbis webm -> aac m4a'
    \$FF -y -loglevel error -i vorbis.webm -c:a aac -b:a 128k vorbis.m4a
    echo '-- vorbis webm -> ogg, stream copy'
    \$FF -y -loglevel error -i vorbis.webm -vn -c:a copy vorbis.ogg

    echo
    printf '%-12s %-8s %-7s %-9s %s\n' file codec rate dur level
    for f in opus.m4a vorbis.m4a vorbis.ogg; do
        info=\$(\$FP -v error -show_entries stream=codec_name,sample_rate,duration \
               -of csv=p=0 \"\$f\")
        lvl=\$(ffmpeg -i \"\$f\" -af volumedetect -f null - 2>&1 \
              | grep -oE 'mean_volume: [-0-9.]+ dB')
        echo \"\$f \$info \$lvl\" | tr ',' ' '
    done

    # A file full of silence would pass every check above.
    echo
    ffmpeg -v error -i opus.m4a -ac 1 -ar 8000 -f f32le -t 2 - > t.f32
    python3 -c \"
import struct, cmath, math
d = open('t.f32','rb').read()
x = struct.unpack('<%df' % (len(d)//4), d)[:8192]
best = max(((abs(sum(v*cmath.exp(-2j*math.pi*k*n/8192) for n,v in enumerate(x))), k)
            for k in range(1, 1200)))
hz = best[1]*8000.0/8192
print('peak frequency %.1f Hz (expected 440)' % hz)
raise SystemExit(0 if abs(hz-440) < 5 else 'WRONG TONE')
\"
"
