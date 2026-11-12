# RooTheater — License Notice

RooTheater is distributed under the GNU General Public License v3.0 or later
(GPL-3.0-or-later). The complete license text is in [LICENSE](LICENSE) and at
https://www.gnu.org/licenses/gpl-3.0.html

## What this means in practice
- You are free to use, study, modify, and redistribute this software.
- If you distribute modified versions, you must keep them under the same
  GPL-compatible terms and provide the corresponding source code.
- The software is provided without warranty, as described by the GPL.

## Third-party components

RooTheater's media engine links and/or bundles the open-source components below.
Each component is owned by its respective authors and used under the terms of its
license. The full license texts ship inside the RPM under
`/usr/share/harbour-rootheater/licenses/<component>/` and are kept in this
repository under `licenses/<component>/`.

**Note on distribution and corresponding source:** the FFmpeg and libVLC builds
are *vendored* (prebuilt and committed under `ffmpeg/<arch>/` and `vlc/<arch>/` in
the development repository, and bundled/linked into the distributed RPM). Those
prebuilt binary trees are **not** republished in the public source mirror to keep
it lean; their corresponding source is the upstream project at the version listed
below, reproducible with the build recipe shipped in `scripts/build-ffmpeg.sh` and
`scripts/build-libvlc.sh`.

---

**RooTheater** (this application)
- License: GPL-3.0-or-later — see [LICENSE](LICENSE)
- Source: https://github.com/RootGPT-YouTube/RooTheater-SailfishOS

**FFmpeg** (libavformat / libavcodec / libavutil / libswscale / libswresample)
- Role: container demux, codec probe, audio decode, software scaling/resampling
- Version: 7.0.2
- License: LGPL-2.1-or-later (built with `--enable-version3`, **without**
  `--enable-gpl` and without GPL encoders such as libx264 → LGPL only)
- Distribution: static libraries linked into the `harbour-rootheater` binary;
  the `.a` are vendored under `ffmpeg/<arch>/`
- Source / corresponding source: https://ffmpeg.org/ (7.0.2) + `scripts/build-ffmpeg.sh`
- License texts: `licenses/ffmpeg/`

**libVLC** (VideoLAN) and its plugins
- Role: broad coverage backend — since 1.9.0 a **full build** with the same
  codecs, demuxers and access modules as desktop VLC (AV1 via dav1d, VP8/VP9,
  native MKV/Ogg, ASS subtitles, DVD/Blu-ray without copy protection, RTSP,
  SRT, SMB, NFS, SFTP, UPnP, x264/x265 encoders…)
- Version: 3.0.21
- License: libvlc / libvlccore are LGPL-2.1-or-later; many plugins and the
  contrib libraries they embed are GPL-2.0-or-later, so the bundled libVLC as a
  whole is distributed under **GPL-2.0-or-later** (compatible with
  RooTheater's GPL-3.0-or-later)
- Distribution: `libvlc` / `libvlccore` shared objects and the VLC plugins are
  **bundled** in the RPM under `/usr/share/harbour-rootheater/lib/` and loaded via
  the binary RPATH and `VLC_PLUGIN_PATH`
- Source / corresponding source: https://www.videolan.org/vlc/ (3.0.21) + `scripts/build-libvlc.sh`
- License texts: `licenses/vlc/`

**libVLC contrib libraries** (statically linked into the bundled VLC plugins)
- Role: the codec, container, subtitle, crypto and network libraries behind the
  plugins above, built from source by VLC's contrib system as part of
  `scripts/build-libvlc.sh` (no separate shared objects are shipped)
- Components: 58 libraries — the complete list with versions, SPDX licenses and
  upstream links is in [`licenses/vlc/CONTRIB.md`](licenses/vlc/CONTRIB.md).
  Licenses involved: GPL-2.0-or-later (x264, x265, FAAD2, liba52, libdca,
  libmpeg2, libdvdread, libdvdnav, libpostproc, libsidplay2), LGPL-2.1/3.0-or-later
  (FFmpeg, GnuTLS, libgcrypt, LIVE555, libebml/libmatroska, mpg123, libbluray…),
  MPL-2.0 (SRT) and permissive licenses (BSD, MIT, ISC, libpng, IJG: dav1d,
  libvpx, Xiph codecs, libass, libxml2…)
- Left out on purpose: fdk-aac (incompatible with the GPL), libzvbi (two
  GPL-2.0-only files), and libdvdcss / libaacs / libbdplus / aribb25 (copy
  protection circumvention, not distributable in the EU)
- Source / corresponding source: the upstream projects at the versions listed
  in `CONTRIB.md`, fetched and built by `scripts/build-libvlc.sh` (VLC contrib)
- License texts: `licenses/vlc/contrib/<library>/` (+ `licenses/vlc/COPYING.*`)

**droidmedia**
- Role: hardware video decode through the Android HAL via libhybris (the direct
  zero-copy HW path)
- License: Apache-2.0
- Distribution: **linked** against the on-device system library (libhybris
  namespace); not bundled in the RPM
- Source: https://github.com/sailfishos/droidmedia
- License text: `licenses/droidmedia/`

**Qt 5** and **Sailfish Silica**
- Role: application framework and UI toolkit
- License: LGPL-2.1-or-later (Qt 5) / proprietary (Sailfish Silica)
- Distribution: system libraries provided by the platform; not bundled

**Grilo** and **Tracker 3** (music library metadata)
- Role: the Audio library (All songs / Albums / Artists) reads track metadata
  from the system media index through the `grl-tracker3` Grilo source and
  SPARQL queries over the public Tracker 3 audio ontology — the same index the
  stock Media app uses
- License: LGPL-2.1-or-later (Grilo, grilo-plugins, libtracker-sparql) /
  GPL-2.0-or-later (the Tracker 3 indexer daemon)
- Distribution: system libraries and QML plugin provided by the platform
  (`grilo-qt5-qml-plugin`, `grilo-plugin-tracker`); linked/loaded at runtime,
  **not** bundled in the RPM
- Source: https://gitlab.gnome.org/GNOME/grilo and
  https://gitlab.gnome.org/GNOME/tracker
