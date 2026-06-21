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
  the binary RPATH and `VLC_PLUGIN_PATH`
- Source / corresponding source: https://www.videolan.org/vlc/ (3.0.21) + `scripts/build-libvlc.sh`
- License texts: `licenses/vlc/`

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
