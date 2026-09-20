#!/bin/sh
# Packages build/ffmpeg and build/ffprobe as a Harmattan deb.
#
# Run tools/build.sh first.
#
#   tools/mkdeb.sh [version]   # -> build/ffmpeg-n9_<version>_armel.deb
#
# Installs under /opt, not MyDocs: MyDocs is vfat and mounted noexec, so a
# binary copied there does not run and the error does not say why. /usr/bin
# gets two symlinks so the terminal finds them without touching PATH.
set -e
cd "$(dirname "$0")/.."

VERSION=${1:-1.0}
STAGE=build/stage
OUT=build/ffmpeg-n9_${VERSION}_armel.deb

for f in ffmpeg ffprobe; do
    [ -f "build/$f" ] || { echo "build/$f missing -- run tools/build.sh" >&2; exit 1; }
done

rm -rf "$STAGE"
mkdir -p "$STAGE/opt/ffmpeg/bin" "$STAGE/DEBIAN"
cp build/ffmpeg build/ffprobe tools/webm2audio "$STAGE/opt/ffmpeg/bin/"
chmod 755 "$STAGE/opt/ffmpeg/bin/ffmpeg" "$STAGE/opt/ffmpeg/bin/ffprobe" \
          "$STAGE/opt/ffmpeg/bin/webm2audio"

# The /usr/bin links are made by the maintainer scripts rather than shipped in
# data.tar.gz: mkdeb.py is shared with meecast-wind and packs regular files
# only, and teaching it symlinks here would let the two copies drift apart.
cat > "$STAGE/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
# The links are a convenience, not the package. If anything on the device
# refuses them, /opt/ffmpeg/bin still holds working binaries -- failing the
# whole install over a symlink would be the wrong trade.
ln -sf /opt/ffmpeg/bin/ffmpeg     /usr/bin/ffmpeg     || true
ln -sf /opt/ffmpeg/bin/ffprobe    /usr/bin/ffprobe    || true
ln -sf /opt/ffmpeg/bin/webm2audio /usr/bin/webm2audio || true
exit 0
POST
cat > "$STAGE/DEBIAN/prerm" <<'PRE'
#!/bin/sh
set -e
# Only our own links, in case something else ever owns these names.
[ "$(readlink /usr/bin/ffmpeg)"  = /opt/ffmpeg/bin/ffmpeg  ] && rm -f /usr/bin/ffmpeg
[ "$(readlink /usr/bin/ffprobe)" = /opt/ffmpeg/bin/ffprobe ] && rm -f /usr/bin/ffprobe
[ "$(readlink /usr/bin/webm2audio)" = /opt/ffmpeg/bin/webm2audio ] && rm -f /usr/bin/webm2audio
exit 0
PRE
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm"

cat > "$STAGE/DEBIAN/control" <<CTRL
Package: ffmpeg-n9
Version: $VERSION
Section: user/multimedia
Priority: optional
Architecture: armel
Maintainer: Sebastian Matkovich <sebastian.matkovich@gmail.com>
Description: Audio-only ffmpeg for the N9
 A small statically linked ffmpeg and ffprobe, built from ffmpeg 4.4 with
 MADDE's own GCC 4.4.1 against the Harmattan sysroot.
 .
 Reads WebM, Ogg, MP4/M4A, MP3 and WAV; decodes Opus, Vorbis, AAC and MP3;
 encodes AAC. Meant for pulling the audio out of a .webm into something the
 phone's own player handles: .m4a (AAC), or a straight stream copy to .ogg
 when the webm already carries Vorbis.
 .
 No video encoders or decoders, no network. Nothing else is needed on the
 device -- the binaries are static.
CTRL

python3 tools/mkdeb.py "$STAGE" "$OUT"
python3 tools/mkdeb.py --info "$OUT"
ls -la "$OUT"
