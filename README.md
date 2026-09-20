# ffmpeg for the Nokia N9 / N950 (MeeGo Harmattan)

A small, statically linked `ffmpeg` and `ffprobe` for Harmattan, built with
**MADDE's own toolchain** — no modern cross-GCC needed. Audio only: enough to
pull the sound out of a `.webm` into something the phone's own player handles.

The N9 and the N950 run the same OS on the same OMAP3630, and the binaries are
static, so one package covers both.

    devel-su dpkg -i ffmpeg-n9_1.0_armel.deb
    webm2audio clip.webm            # -> clip.m4a, AAC 128k

## Does MADDE manage it?

Yes, and without a single source patch. MADDE's compiler is CodeSourcery
2009q3 / **GCC 4.4.1**, which is old enough to be the obvious worry, but
ffmpeg 4.4 builds with it clean: it falls back to `compat/atomics/gcc` where a
C11 `<stdatomic.h>` is missing, and everything else it needs is C99.

Two things had to be got right:

* **The toolchain ships no libc.** A bare `arm-none-linux-gnueabi-gcc` cannot
  even link `int main(){}` — `crt1.o: No such file`. `crt1.o`, `libc.a`,
  `libm.a` and `libpthread.a` come from the MADDE Harmattan sysroot, which is
  **glibc 2.10.1 — the device's own glibc**. So `--sysroot=` is not a detail,
  it is what makes the result a Harmattan binary.
* **No `-m` flags.** MADDE's gcc already defaults to `armv7-a`, `cortex-a8`,
  `-mfloat-abi=hard` and `-mfpu=neon`. ffmpeg's configure reads that and turns
  the **NEON** assembly on by itself. Passing a float ABI by hand is how you
  get a binary that links and then dies on the phone.

Harmattan is `armel` by dpkg's naming but hard-float in fact — see the same
note in `harbour-snapszer/meego/README.md`.

The binaries are linked `-static` (2.7 MB each). Nothing is installed on the
device, and nothing can break when Harmattan's own libraries move.

## Which format — and what the DSP actually does

`ffmpeg` itself never touches the DSP. It decodes and encodes on the A8 core;
the IVA2.2 only matters afterwards, when the phone *plays* the result. So the
question is which output the N9's player decodes in hardware:

| target | on the N9 | in this build |
| --- | --- | --- |
| **AAC in `.m4a`** | DSP path, cheapest playback | native encoder, **no external library** |
| MP3 | DSP path | would need libmp3lame cross-built |
| Ogg Vorbis | software (CPU) | decode + stream copy only, no encoder |
| Opus | not supported — 2012 codec, 2011 phone | decode only |

**AAC/M4A is the recommendation on two independent grounds**: it is the DSP
path, and ffmpeg's native AAC encoder needs no external library at all, which
is why this build has no dependencies to speak of. Its quality has been fine
since ffmpeg 3.0.

> The DSP column is **expectation, not measurement** — the N9 was unreachable
> for this whole session. To settle it on the phone:
> `ls /usr/lib/gstreamer-0.10/ | grep -iE 'dsp|aac|mp3|vorbis|opus'`

MP3 is a small follow-up if wanted: libmp3lame is plain C with autotools and
cross-builds against the same sysroot in a couple of minutes.

## Why a wrapper script

The obvious command is a trap:

    ffmpeg -i clip.webm -c:a aac clip.m4a
    # Default encoder for format ipod (codec h264) is probably disabled

That is ffmpeg trying to carry the **video** into the `.m4a`, and the message
never says so. `-vn` is what is missing. `webm2audio` always passes it, and
picks the cheap path when there is one:

* webm with **Vorbis** → `.ogg` is a **stream copy**: lossless, about a second,
  no re-encode.
* webm with **Opus** (what YouTube gives you now) → must be transcoded, since
  the N9 cannot play Opus.
* input already AAC → copied, not re-encoded.

It accepts `.m4a`, `.mp4`, `.ogg` and `.wav` and refuses anything else by
name. `.aac` and `.oga` look like they ought to work and do not: they need the
`adts` and `oga` muxers, which this build leaves out, and all ffmpeg says is
`Unable to find a suitable output format`. Refusing them with a sentence that
names the three that do work is the whole point of the wrapper.

## Building

    tools/build.sh      # cross-build on the build machine -> build/ffmpeg, build/ffprobe
    tools/selftest.sh   # run the ARM binaries under qemu-arm and check the output
    tools/mkdeb.sh      # -> build/ffmpeg-n9_1.0_armel.deb

`tools/buildhost.sh` from `nfsshift-sfos` picks LAN or tunnel; the tree lives
in `/tmp` on that machine.

## Testing without the phone

`tools/selftest.sh` runs the **ARM** binaries under `qemu-arm` on the build
machine. Because they are static, qemu needs no sysroot at all.

The test signal is a 440 Hz sine, so the check is more than "a file appeared":
the host ffmpeg decodes what the ARM binary wrote, and both the level and the
peak frequency have to come back. A file full of silence passes a file-size
check and fails this one.

Measured, all green:

| case | result |
| --- | --- |
| Opus webm → AAC m4a | aac 48 kHz, 5.007 s, −21.1 dB (source −21.1 dB) |
| Vorbis webm → AAC m4a | aac 44.1 kHz, 5.003 s, −21.0 dB (source −21.0 dB) |
| Vorbis webm → ogg, copy | vorbis 44.1 kHz, 5.008 s, −21.0 dB |
| tone through the AAC encoder | peak at **440.4 Hz** |
| VP9+Opus webm via `webm2audio` | video dropped, audio converted |
| `webm2audio` output types | `.m4a .mp4 .ogg .wav` convert; `.aac .oga .xyz` refused by name |
| same run under `qemu-arm -cpu cortex-a8` | identical output, −21.1 dB |

The last row is worth the extra command: qemu's default CPU model is a newer
core than the N9's, so anything the real A8 cannot execute would go unnoticed.
Pinning the model is as close to the device as this machine gets.

A 60 s stereo Opus → AAC run took 13 s under qemu. That is an emulator on a
desktop, **not** a Cortex-A8 at 1 GHz, so treat it as "the same order of
magnitude as realtime", not as a device measurement.

## Packaging notes

Installs to `/opt/ffmpeg/bin`, with symlinks into `/usr/bin` made by
`postinst`. **Not `MyDocs`** — that is vfat and mounted `noexec`, so a binary
copied there does not run and the error does not explain why.

`tools/mkdeb.py` is the Harmattan packager from the Snapszer port: Harmattan's
dpkg is 1.15.x, so members must be `debian-binary`, `control.tar.gz`,
`data.tar.gz`, gzip only, and without GNU ar's trailing slash on member names.
It packs regular files only, which is why the symlinks are made in `postinst`
rather than shipped — teaching this copy about symlinks would let it drift
from the one in `meecast-wind`.

## Licence and provenance

FFmpeg is **LGPL v2.1 or later** here: this is a stock upstream tree with no
patches and `--enable-gpl` is deliberately *not* passed, so no GPL-only code is
linked in.

The binaries in the release are built from

    https://git.ffmpeg.org/ffmpeg.git
    branch release/4.4, commit 75728c54b88a3a3e4f72c822bcff56a146acd1ee (4.4.8)

`tools/build.sh` in this repository is the complete recipe — nothing is patched
and nothing is hand-edited, so that commit plus that script reproduces the
binaries. The full configure line is also compiled into the binary itself and
comes back out of `ffmpeg -version`, which is the easiest way to check what a
copy of it actually is.

The scripts in `tools/` are this repository's own work; `tools/mkdeb.py` comes
from the Snapszer port.

## Status

* [x] Builds with MADDE GCC 4.4.1, no source patches, NEON on.
* [x] Conversions verified under qemu-arm, output checked by level and
      frequency rather than by existence.
* [x] `ffmpeg-n9_1.0_armel.deb` built and structurally checked.
* [ ] **Nothing has run on a device yet.** The N9 was unreachable all
      session; the N950 at 192.168.1.8 answers SSH but does not accept the
      `id_rsa_n9` key. Speed on the device and the DSP table above are both
      unverified — qemu proves the code is right, not that it is fast enough.
* [ ] If MP3 output is wanted, cross-build libmp3lame and add
      `--enable-libmp3lame`.
