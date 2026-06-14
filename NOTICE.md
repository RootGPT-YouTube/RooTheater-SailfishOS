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

RooTheater's media engine builds on the following open-source components.
Their full license texts are shipped with the RPM under
`/usr/share/harbour-rootheater/licenses/` once the corresponding backend is
bundled.

| Component | Role | License |
|-----------|------|---------|
| Qt 5 + Sailfish Silica | App framework / UI | LGPL v2.1+ / proprietary (Silica) |
| droidmedia / gst-droid | Hardware video decode via the Android HAL (libhybris) | LGPL v2.1+ |
| FFmpeg (libavformat / libavcodec / …) | Container demux, codec probe, software decode | LGPL v2.1+ / GPL v2+ |
| libVLC (VideoLAN) | Broad format / codec / streaming coverage | LGPL v2.1+ |

These components are owned by their respective authors and are used here under
the terms of their licenses.
