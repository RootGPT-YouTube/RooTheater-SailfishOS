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
- Role: broad coverage backend for exotic containers/codecs/streaming
- Version: 3.0.21
- License: LGPL-2.1-or-later for libvlc / libvlccore; some bundled plugins are
  GPL-2.0-or-later
- Distribution: `libvlc` / `libvlccore` shared objects and the VLC plugins are
  **bundled** in the RPM under `/usr/share/harbour-rootheater/lib/` and loaded via
  the binary RPATH and `VLC_PLUGIN_PATH`. The TLS access (`libgnutls_plugin`) and
  MPEG-TS demux (`libts_plugin`) plugins are built and bundled to support HTTPS
  network streaming; they statically include the contrib libraries listed next.
- Source / corresponding source: https://www.videolan.org/vlc/ (3.0.21) + `scripts/build-libvlc.sh`
- License texts: `licenses/vlc/`

**libVLC contrib libraries** (statically linked into the TLS / MPEG-TS plugins above)
- Role: TLS for `https://` streams (GnuTLS + its crypto deps) and MPEG-TS
  parsing (libdvbpsi); built from source by VLC's contrib system as part of
  `scripts/build-libvlc.sh` and statically linked into `libgnutls_plugin.so` /
  `libts_plugin.so` (no separate shared objects are shipped)
- Components, versions and licenses:
  - **GnuTLS** 3.6.16 — LGPL-2.1-or-later — https://www.gnutls.org/
  - **Nettle** 3.7.3 — LGPL-3.0-or-later OR GPL-2.0-or-later (dual) — https://www.lysator.liu.se/~nisse/nettle/
  - **GMP** 6.1.2 — LGPL-3.0-or-later OR GPL-2.0-or-later (dual) — https://gmplib.org/
  - **libtasn1** 4.8 — LGPL-2.1-or-later — https://www.gnu.org/software/libtasn1/
  - **libdvbpsi** 1.3.3 — LGPL-2.1-or-later — https://www.videolan.org/developers/libdvbpsi.html
- Distribution: statically embedded in the two VLC plugins bundled in the RPM
- Source / corresponding source: the upstream projects at the versions above,
  fetched and built by `scripts/build-libvlc.sh` (VLC contrib)
- License texts: `licenses/vlc/` (LGPL-2.1 / LGPL-3 / GPL-2 cover these too; see
  `licenses/vlc/CONTRIB.md` for the per-library mapping)

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
