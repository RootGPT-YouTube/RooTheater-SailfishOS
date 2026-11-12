# libVLC contrib libraries — license mapping

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
| FFmpeg (libavcodec/libavformat/libavutil/libswscale) | 4.4.4 | `LGPL-2.1-or-later` | avcodec/avformat/swscale plugins | `contrib/ffmpeg/` | https://ffmpeg.org/ |
| libpostproc | git 3b7053f | `GPL-2.0-or-later` | postproc filter | `contrib/postproc/` | https://git.videolan.org/?p=libpostproc.git |
| dav1d | 1.4.2 | `BSD-2-Clause` | AV1 decoder | `contrib/dav1d/` | https://code.videolan.org/videolan/dav1d |
| libvpx | 1.14.1 | `BSD-3-Clause` | VP8/VP9 | `contrib/libvpx/` | https://chromium.googlesource.com/webm/libvpx |
| x264 | snapshot 20180324 | `GPL-2.0-or-later` | H.264 encoder | `contrib/x264/` | https://www.videolan.org/developers/x264.html |
| x265 | 2.9 | `GPL-2.0-or-later` | HEVC encoder | `contrib/x265/` | https://www.videolan.org/developers/x265.html |
| libogg | 1.3.3 | `BSD-3-Clause` | Ogg demux | `contrib/libogg/` | https://xiph.org/ogg/ |
| libvorbis | 1.3.6 | `BSD-3-Clause` | Vorbis | `contrib/libvorbis/` | https://xiph.org/vorbis/ |
| Opus | 1.3 | `BSD-3-Clause` | Opus | `contrib/opus/` | https://opus-codec.org/ |
| FLAC (libFLAC) | 1.3.4 | `BSD-3-Clause` | FLAC | `contrib/flac/` | https://xiph.org/flac/ |
| libtheora | 1.1.1 | `BSD-3-Clause` | Theora | `contrib/libtheora/` | https://www.theora.org/ |
| Speex | 1.2.1 | `BSD-3-Clause` | Speex | `contrib/speex/` | https://speex.org/ |
| SpeexDSP | 1.2.1 | `BSD-3-Clause` | resampler | `contrib/speexdsp/` | https://speex.org/ |
| liba52 (a52dec) | 0.7.4 | `GPL-2.0-or-later` | AC-3 | `contrib/a52dec/` | https://liba52.sourceforge.io/ |
| libdca | 0.0.7 | `GPL-2.0-or-later` | DTS | `contrib/libdca/` | https://www.videolan.org/developers/libdca.html |
| FAAD2 | 2.10.0 | `GPL-2.0-or-later` | AAC | `contrib/faad2/` | https://github.com/knik0/faad2 |
| mpg123 | 1.30.1 | `LGPL-2.1-or-later` | MPEG audio | `contrib/mpg123/` | https://www.mpg123.de/ |
| libmpeg2 | 0.5.1 | `GPL-2.0-or-later` | MPEG-1/2 video | `contrib/libmpeg2/` | https://libmpeg2.sourceforge.io/ |
| TwoLAME | 0.4.0 | `LGPL-2.1-or-later` | MP2 encoder | `contrib/twolame/` | https://www.twolame.org/ |
| LAME | 3.100 | `LGPL-2.0-or-later` | MP3 encoder | `contrib/lame/` | https://lame.sourceforge.io/ |
| libmpcdec (Musepack) | r481 | `BSD-3-Clause` | Musepack | `contrib/musepack/` | https://www.musepack.net/ |
| libebml | 1.4.3 | `LGPL-2.1-or-later` | MKV demux | `contrib/ebml/` | https://github.com/Matroska-Org/libebml |
| libmatroska | 1.6.3 | `LGPL-2.1-or-later` | MKV demux | `contrib/matroska/` | https://github.com/Matroska-Org/libmatroska |
| libass | 0.17.1 | `ISC` | ASS/SSA subtitles | `contrib/libass/` | https://github.com/libass/libass |
| GNU FriBidi | 1.0.12 | `LGPL-2.1-or-later` | bidi text | `contrib/fribidi/` | https://github.com/fribidi/fribidi |
| libkate | 0.4.1 | `BSD-3-Clause` | Kate subtitles | `contrib/libkate/` | https://code.google.com/archive/p/libkate/ |
| aribb24 | 1.0.3 | `LGPL-2.1-or-later` | ARIB captions | `contrib/aribb24/` | https://github.com/nkoriyama/aribb24 |
| libmodplug | 0.8.9.0 | `LicenseRef-Public-Domain` | tracker music | `contrib/libmodplug/` | https://github.com/Konstanty/libmodplug |
| Game_Music_Emu | 0.6.3 | `LGPL-2.1-or-later` | chiptunes | `contrib/game-music-emu/` | https://github.com/libgme/game-music-emu |
| libsidplay2 / reSID | 2.1.1 | `GPL-2.0-or-later` | C64 SID music | `contrib/sidplay-libs/` | https://sidplay2.sourceforge.net/ |
| libxml2 | 2.9.14 | `MIT` | XML (DASH, playlists) | `contrib/libxml2/` | https://gitlab.gnome.org/GNOME/libxml2 |
| TagLib | 1.12 | `LGPL-2.1-only OR MPL-1.1` | metadata | `contrib/taglib/` | https://taglib.org/ |
| LIVE555 | 2016.11.28 | `LGPL-3.0-or-later` | RTSP | `contrib/live555/` | http://www.live555.com/ |
| libarchive | 3.6.1 | `BSD-2-Clause` | archive access | `contrib/libarchive/` | https://www.libarchive.org/ |
| libdvdread | 6.1.3 | `GPL-2.0-or-later` | DVD (unprotected) | `contrib/dvdread/` | https://code.videolan.org/videolan/libdvdread |
| libdvdnav | 6.1.1 | `GPL-2.0-or-later` | DVD menus | `contrib/dvdnav/` | https://code.videolan.org/videolan/libdvdnav |
| libbluray | 1.3.2 | `LGPL-2.1-or-later` | Blu-ray (unprotected, no BD-J) | `contrib/bluray/` | https://code.videolan.org/videolan/libbluray |
| libdvbpsi | 1.3.3 | `LGPL-2.1-or-later` | MPEG-TS | `contrib/libdvbpsi/` | https://www.videolan.org/developers/libdvbpsi.html |
| GnuTLS | 3.6.16 | `LGPL-2.1-or-later` | TLS (https) | `contrib/gnutls/` | https://www.gnutls.org/ |
| Nettle | 3.7.3 | `LGPL-3.0-or-later OR GPL-2.0-or-later` | crypto (GnuTLS) | `contrib/nettle/` | https://www.lysator.liu.se/~nisse/nettle/ |
| GMP | 6.1.2 | `LGPL-3.0-or-later OR GPL-2.0-or-later` | bignum (GnuTLS) | `contrib/gmp/` | https://gmplib.org/ |
| libtasn1 | 4.8 | `LGPL-2.1-or-later` | ASN.1 (GnuTLS) | `contrib/libtasn1/` | https://www.gnu.org/software/libtasn1/ |
| libgcrypt | 1.7.10 | `LGPL-2.1-or-later` | HLS AES-128, SFTP | `contrib/gcrypt/` | https://gnupg.org/software/libgcrypt/ |
| libgpg-error | 1.27 | `LGPL-2.1-or-later` | libgcrypt dependency | `contrib/libgpg-error/` | https://gnupg.org/software/libgpg-error/ |
| libssh2 | 1.10.0 | `BSD-3-Clause` | SFTP access | `contrib/ssh2/` | https://www.libssh2.org/ |
| SRT | 1.4.4 | `MPL-2.0` | SRT streaming | `contrib/srt/` | https://github.com/Haivision/srt |
| libsmb2 | 4.0.0 | `LGPL-2.1-or-later` | SMB2/3 shares | `contrib/smb2/` | https://github.com/sahlberg/libsmb2 |
| libdsm | 0.4.3 | `LGPL-2.1-or-later` | SMB1 shares | `contrib/libdsm/` | https://github.com/videolabs/libdsm |
| libnfs | 5.0.1 | `LGPL-2.1-or-later` | NFS shares | `contrib/nfs/` | https://github.com/sahlberg/libnfs |
| libupnp (pupnp) | 1.14.13 | `BSD-3-Clause` | UPnP discovery | `contrib/upnp/` | https://pupnp.github.io/pupnp/ |
| libsoxr | 0.1.3 | `LGPL-2.1-or-later` | resampler | `contrib/soxr/` | https://sourceforge.net/projects/soxr/ |
| libsamplerate | 0.1.9 | `BSD-2-Clause` | resampler | `contrib/samplerate/` | https://libsndfile.github.io/libsamplerate/ |
| libmysofa | 0.5 | `BSD-3-Clause` | HRTF (spatial audio) | `contrib/mysofa/` | https://github.com/hoene/libmysofa |
| libspatialaudio | 0.3.0 | `LGPL-2.1-or-later` | ambisonics | `contrib/spatialaudio/` | https://github.com/videolabs/libspatialaudio |
| libpng | 1.6.37 | `Libpng` | PNG | `contrib/png/` | http://www.libpng.org/ |
| libjpeg (IJG) | 9b | `IJG` | JPEG | `contrib/jpeg/` | https://ijg.org/ |
| OpenJPEG | 2.3.0 | `BSD-2-Clause` | JPEG 2000 | `contrib/openjpeg/` | https://www.openjpeg.org/ |
| libgsm | 1.0.13 | `TU-Berlin-1.0` | GSM audio | `contrib/gsm/` | https://www.quut.com/gsm/ |

Corresponding source: the upstream projects at the versions above, fetched and
built reproducibly by `scripts/build-libvlc.sh` (VLC contrib system); the exact
source tarballs are also published with the `rootheater-vendor-<version>`
release on GitHub.
