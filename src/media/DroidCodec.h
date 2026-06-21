/*
    RooTheater — a multimedia player for Sailfish OS.
    Copyright (C) 2026 RootGPT

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef DROIDCODEC_H
#define DROIDCODEC_H

#include <QString>

// DroidCodec is the thin entry point to the Layer 1 (direct HW) path: it talks
// to droidmedia, the same lib gst-droid wraps, to reach the device's OMX video
// decoders over the Android HAL (libhybris). v0.3.1 exposes only the capability
// query that makes the engine facade's "Droidmedia" choice real and
// capability-driven (architecture: ask the device which decoders it actually
// has, don't hardcode). The decode pipeline (DroidCodecBackend) builds on this.
class DroidCodec
{
public:
    // Whether the device's droidmedia exposes a hardware decoder for `codec`
    // (an ffmpeg short name: "h264", "hevc", "vp9", …) at the given size.
    // Returns false for codecs we don't map or when droidmedia can't init
    // (e.g. outside the libhybris-enabled app sandbox).
    static bool decoderSupported(const QString &codec, int width, int height);

    // droid_media_init() once per process (cached). Shared by the capability
    // query and the decode backend so the HAL is brought up exactly once.
    static bool initialize();

private:
    DroidCodec() = delete;
};

#endif // DROIDCODEC_H
