#!/usr/bin/env python3
"""Raccoglie i testi di licenza dei contrib di libVLC e scrive licenses/vlc/CONTRIB.md.

Uso:  python3 scripts/collect-vlc-licenses.py [arch]     (default aarch64)

Legge i sorgenti estratti in _libvlc_build/vlc-3.0.21/contrib/sfos-<arch>-full/
(prodotti da scripts/build-libvlc.sh) e copia i file di licenza di ogni libreria
in licenses/vlc/contrib/<libreria>/. La tabella (versione, licenza SPDX) e'
mantenuta a mano qui sotto: e' stata verificata leggendo i COPYING e le
intestazioni dei sorgenti (vedi anche il controllo "GPL senza or-later" descritto
in build-libvlc.sh).
"""
import os
import shutil
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARCH = sys.argv[1] if len(sys.argv) > 1 else "aarch64"
SRC = os.path.join(PROJ, "_libvlc_build", "vlc-3.0.21", "contrib", f"sfos-{ARCH}-full")
DST = os.path.join(PROJ, "licenses", "vlc", "contrib")

# nome mostrato, cartella sorgente, versione, licenza SPDX, file di licenza, plugin/ruolo, upstream
LIBS = [
    ("FFmpeg (libavcodec/libavformat/libavutil/libswscale)", "ffmpeg", "4.4.4", "LGPL-2.1-or-later",
     ["COPYING.LGPLv2.1", "LICENSE.md"], "avcodec/avformat/swscale plugins", "https://ffmpeg.org/"),
    ("libpostproc", "postproc", "git 3b7053f", "GPL-2.0-or-later", ["COPYING"], "postproc filter",
     "https://git.videolan.org/?p=libpostproc.git"),
    ("dav1d", "dav1d", "1.4.2", "BSD-2-Clause", ["COPYING"], "AV1 decoder", "https://code.videolan.org/videolan/dav1d"),
    ("libvpx", "libvpx", "1.14.1", "BSD-3-Clause", ["LICENSE"], "VP8/VP9", "https://chromium.googlesource.com/webm/libvpx"),
    ("x264", "x264", "snapshot 20180324", "GPL-2.0-or-later", ["COPYING"], "H.264 encoder", "https://www.videolan.org/developers/x264.html"),
    ("x265", "x265", "2.9", "GPL-2.0-or-later", ["COPYING"], "HEVC encoder", "https://www.videolan.org/developers/x265.html"),
    ("libogg", "libogg", "1.3.3", "BSD-3-Clause", ["COPYING"], "Ogg demux", "https://xiph.org/ogg/"),
    ("libvorbis", "libvorbis", "1.3.6", "BSD-3-Clause", ["COPYING"], "Vorbis", "https://xiph.org/vorbis/"),
    ("Opus", "opus", "1.3", "BSD-3-Clause", ["COPYING"], "Opus", "https://opus-codec.org/"),
    ("FLAC (libFLAC)", "flac", "1.3.4", "BSD-3-Clause", ["COPYING.Xiph"], "FLAC", "https://xiph.org/flac/"),
    ("libtheora", "libtheora", "1.1.1", "BSD-3-Clause", ["COPYING", "LICENSE"], "Theora", "https://www.theora.org/"),
    ("Speex", "speex", "1.2.1", "BSD-3-Clause", ["COPYING"], "Speex", "https://speex.org/"),
    ("SpeexDSP", "speexdsp", "1.2.1", "BSD-3-Clause", ["COPYING"], "resampler", "https://speex.org/"),
    ("liba52 (a52dec)", "a52dec", "0.7.4", "GPL-2.0-or-later", ["COPYING"], "AC-3", "https://liba52.sourceforge.io/"),
    ("libdca", "libdca", "0.0.7", "GPL-2.0-or-later", ["COPYING"], "DTS", "https://www.videolan.org/developers/libdca.html"),
    ("FAAD2", "faad2", "2.10.0", "GPL-2.0-or-later", ["COPYING"], "AAC", "https://github.com/knik0/faad2"),
    ("mpg123", "mpg123", "1.30.1", "LGPL-2.1-or-later", ["COPYING"], "MPEG audio", "https://www.mpg123.de/"),
    ("libmpeg2", "libmpeg2", "0.5.1", "GPL-2.0-or-later", ["COPYING"], "MPEG-1/2 video", "https://libmpeg2.sourceforge.io/"),
    ("TwoLAME", "twolame", "0.4.0", "LGPL-2.1-or-later", ["COPYING"], "MP2 encoder", "https://www.twolame.org/"),
    ("LAME", "lame", "3.100", "LGPL-2.0-or-later", ["COPYING", "LICENSE"], "MP3 encoder", "https://lame.sourceforge.io/"),
    ("libmpcdec (Musepack)", "musepack", "r481", "BSD-3-Clause", ["libmpcdec/COPYING"], "Musepack", "https://www.musepack.net/"),
    ("libebml", "ebml", "1.4.3", "LGPL-2.1-or-later", ["LICENSE.LGPL"], "MKV demux", "https://github.com/Matroska-Org/libebml"),
    ("libmatroska", "matroska", "1.6.3", "LGPL-2.1-or-later", ["LICENSE.LGPL"], "MKV demux", "https://github.com/Matroska-Org/libmatroska"),
    ("libass", "libass", "0.17.1", "ISC", ["COPYING"], "ASS/SSA subtitles", "https://github.com/libass/libass"),
    ("GNU FriBidi", "fribidi", "1.0.12", "LGPL-2.1-or-later", ["COPYING"], "bidi text", "https://github.com/fribidi/fribidi"),
    ("libkate", "libkate", "0.4.1", "BSD-3-Clause", ["COPYING"], "Kate subtitles", "https://code.google.com/archive/p/libkate/"),
    ("aribb24", "aribb24", "1.0.3", "LGPL-2.1-or-later", ["COPYING"], "ARIB captions", "https://github.com/nkoriyama/aribb24"),
    ("libmodplug", "libmodplug", "0.8.9.0", "LicenseRef-Public-Domain", ["COPYING"], "tracker music", "https://github.com/Konstanty/libmodplug"),
    ("Game_Music_Emu", "game-music-emu", "0.6.3", "LGPL-2.1-or-later", ["license.txt"], "chiptunes", "https://github.com/libgme/game-music-emu"),
    ("libsidplay2 / reSID", "sidplay-libs", "2.1.1", "GPL-2.0-or-later",
     ["libsidplay/COPYING", "resid/COPYING", "libsidutils/COPYING"], "C64 SID music", "https://sidplay2.sourceforge.net/"),
    ("libxml2", "libxml2", "2.9.14", "MIT", ["Copyright"], "XML (DASH, playlists)", "https://gitlab.gnome.org/GNOME/libxml2"),
    ("TagLib", "taglib", "1.12", "LGPL-2.1-only OR MPL-1.1", ["COPYING.LGPL", "COPYING.MPL"], "metadata", "https://taglib.org/"),
    ("LIVE555", "live555", "2016.11.28", "LGPL-3.0-or-later", ["COPYING", "COPYING.LESSER"], "RTSP", "http://www.live555.com/"),
    ("libarchive", "libarchive", "3.6.1", "BSD-2-Clause", ["COPYING"], "archive access", "https://www.libarchive.org/"),
    ("libdvdread", "dvdread", "6.1.3", "GPL-2.0-or-later", ["COPYING"], "DVD (unprotected)", "https://code.videolan.org/videolan/libdvdread"),
    ("libdvdnav", "dvdnav", "6.1.1", "GPL-2.0-or-later", ["COPYING"], "DVD menus", "https://code.videolan.org/videolan/libdvdnav"),
    ("libbluray", "bluray", "1.3.2", "LGPL-2.1-or-later", ["COPYING"], "Blu-ray (unprotected, no BD-J)", "https://code.videolan.org/videolan/libbluray"),
    ("libdvbpsi", "libdvbpsi", "1.3.3", "LGPL-2.1-or-later", ["COPYING"], "MPEG-TS", "https://www.videolan.org/developers/libdvbpsi.html"),
    ("GnuTLS", "gnutls", "3.6.16", "LGPL-2.1-or-later", ["LICENSE"], "TLS (https)", "https://www.gnutls.org/"),
    ("Nettle", "nettle", "3.7.3", "LGPL-3.0-or-later OR GPL-2.0-or-later", ["COPYING.LESSERv3", "COPYINGv2"], "crypto (GnuTLS)", "https://www.lysator.liu.se/~nisse/nettle/"),
    ("GMP", "gmp", "6.1.2", "LGPL-3.0-or-later OR GPL-2.0-or-later", ["COPYING.LESSERv3", "COPYINGv2"], "bignum (GnuTLS)", "https://gmplib.org/"),
    ("libtasn1", "libtasn1", "4.8", "LGPL-2.1-or-later", ["COPYING.LIB"], "ASN.1 (GnuTLS)", "https://www.gnu.org/software/libtasn1/"),
    ("libgcrypt", "gcrypt", "1.7.10", "LGPL-2.1-or-later", ["COPYING.LIB", "LICENSES"], "HLS AES-128, SFTP", "https://gnupg.org/software/libgcrypt/"),
    ("libgpg-error", "libgpg-error", "1.27", "LGPL-2.1-or-later", ["COPYING.LIB"], "libgcrypt dependency", "https://gnupg.org/software/libgpg-error/"),
    ("libssh2", "ssh2", "1.10.0", "BSD-3-Clause", ["COPYING"], "SFTP access", "https://www.libssh2.org/"),
    ("SRT", "srt", "1.4.4", "MPL-2.0", ["LICENSE"], "SRT streaming", "https://github.com/Haivision/srt"),
    ("libsmb2", "smb2", "4.0.0", "LGPL-2.1-or-later", ["COPYING", "LICENCE-LGPL-2.1.txt"], "SMB2/3 shares", "https://github.com/sahlberg/libsmb2"),
    ("libdsm", "libdsm", "0.4.3", "LGPL-2.1-or-later", ["COPYING"], "SMB1 shares", "https://github.com/videolabs/libdsm"),
    ("libnfs", "nfs", "5.0.1", "LGPL-2.1-or-later", ["COPYING", "LICENCE-LGPL-2.1.txt", "LICENCE-BSD.txt"], "NFS shares", "https://github.com/sahlberg/libnfs"),
    ("libupnp (pupnp)", "upnp", "1.14.13", "BSD-3-Clause", ["COPYING"], "UPnP discovery", "https://pupnp.github.io/pupnp/"),
    ("libsoxr", "soxr", "0.1.3", "LGPL-2.1-or-later", ["COPYING.LGPL", "LICENCE"], "resampler", "https://sourceforge.net/projects/soxr/"),
    ("libsamplerate", "samplerate", "0.1.9", "BSD-2-Clause", ["COPYING"], "resampler", "https://libsndfile.github.io/libsamplerate/"),
    ("libmysofa", "mysofa", "0.5", "BSD-3-Clause", ["LICENSE"], "HRTF (spatial audio)", "https://github.com/hoene/libmysofa"),
    ("libspatialaudio", "spatialaudio", "0.3.0", "LGPL-2.1-or-later", ["LICENSE"], "ambisonics", "https://github.com/videolabs/libspatialaudio"),
    ("libpng", "png", "1.6.37", "Libpng", ["LICENSE"], "PNG", "http://www.libpng.org/"),
    ("libjpeg (IJG)", "jpeg", "9b", "IJG", ["README"], "JPEG", "https://ijg.org/"),
    ("OpenJPEG", "openjpeg", "2.3.0", "BSD-2-Clause", ["LICENSE"], "JPEG 2000", "https://www.openjpeg.org/"),
    ("libgsm", "gsm", "1.0.13", "TU-Berlin-1.0", ["COPYRIGHT"], "GSM audio", "https://www.quut.com/gsm/"),
]


def main():
    if not os.path.isdir(SRC):
        sys.exit(f"sorgenti contrib non trovati: {SRC}")
    shutil.rmtree(DST, ignore_errors=True)
    missing = []
    for name, d, ver, spdx, files, role, url in LIBS:
        out = os.path.join(DST, d)
        os.makedirs(out, exist_ok=True)
        for f in files:
            p = os.path.join(SRC, d, f)
            if os.path.isfile(p):
                shutil.copy(p, os.path.join(out, f.replace("/", "_")))
            else:
                missing.append(f"{d}/{f}")
    rows = "\n".join(
        f"| {n} | {v} | `{s}` | {r} | `contrib/{d}/` | {u} |" for n, d, v, s, _, r, u in LIBS)
    md = f"""# libVLC contrib libraries — license mapping

Since RooTheater 1.9.0 the bundled libVLC 3.0.21 is a **full build**: the same
codecs, demuxers and access modules as desktop VLC. Its plugins are built by
VLC's contrib system (`scripts/build-libvlc.sh`) and **statically** link the
libraries below — no separate shared objects are shipped for them. Each library
is used under the terms of its license; its own license files are copied, as
found in its source tree, under `contrib/<library>/` in this directory.

**Combined license.** Several of these libraries (x264, x265, FAAD2, liba52,
libdca, libmpeg2, libdvdread, libdvdnav, libpostproc, libsidplay2) are
GPL-2.0-or-later, so the bundled libVLC as a whole is distributed under
GPL-2.0-or-later — compatible with RooTheater's GPL-3.0-or-later. Every
GPL-licensed library here carries the "or later" clause (checked file by file);
**libzvbi was left out** because two of its linked files are GPL-2.0-only
(VLC's own `telx` teletext decoder is used instead).

**Left out on purpose:** fdk-aac (licence incompatible with the GPL; AAC is
decoded by FFmpeg and FAAD2), and the libraries that circumvent disc copy
protection — libdvdcss, libaacs, libbdplus, aribb25 — which cannot be
distributed in the EU. libdvdread loads a user-installed libdvdcss at run time
if one is present; RooTheater does not ship one.

**System libraries** (not bundled, provided by Sailfish OS and linked at run
time): FreeType, Fontconfig, HarfBuzz, PulseAudio, OpenSSL, zlib, bzip2, expat.

| Library | Version | License (SPDX) | Used for | Texts | Upstream |
|---|---|---|---|---|---|
{rows}

Corresponding source: the upstream projects at the versions above, fetched and
built reproducibly by `scripts/build-libvlc.sh` (VLC contrib system); the exact
source tarballs are also published with the `rootheater-vendor-<version>`
release on GitHub.
"""
    with open(os.path.join(PROJ, "licenses", "vlc", "CONTRIB.md"), "w") as fh:
        fh.write(md)
    print(f"{len(LIBS)} librerie, testi in {DST}")
    if missing:
        print("MANCANTI:", " ".join(missing))
        sys.exit(1)


if __name__ == "__main__":
    main()
