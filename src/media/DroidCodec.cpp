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

#include "DroidCodec.h"

#include <QAtomicInt>

#include <cstring>

extern "C" {
#include <droidmedia.h>
#include <droidmediacodec.h>
}

namespace {

// ffmpeg codec short name → Android/OMX MIME type understood by droidmedia.
QByteArray mimeFor(const QString &codec)
{
    if (codec == QLatin1String("h264"))       return QByteArrayLiteral("video/avc");
    if (codec == QLatin1String("hevc"))       return QByteArrayLiteral("video/hevc");
    if (codec == QLatin1String("vp9"))        return QByteArrayLiteral("video/x-vnd.on2.vp9");
    if (codec == QLatin1String("vp8"))        return QByteArrayLiteral("video/x-vnd.on2.vp8");
    if (codec == QLatin1String("mpeg4"))      return QByteArrayLiteral("video/mp4v-es");
    if (codec == QLatin1String("mpeg2video")) return QByteArrayLiteral("video/mpeg2");
    if (codec == QLatin1String("h263"))       return QByteArrayLiteral("video/3gpp");
    return QByteArray();
}

} // namespace

bool DroidCodec::initialize()
{
    // 0 = not tried, 1 = initialised, 2 = failed. droid_media_init() brings up
    // the whole droidmedia/HAL stack and must run once per process; it only
    // succeeds inside the libhybris-enabled app sandbox.
    static QAtomicInt state(0);
    int s = state.loadAcquire();
    if (s == 0) {
        s = droid_media_init() ? 1 : 2;
        state.storeRelease(s);
    }
    return s == 1;
}

bool DroidCodec::decoderSupported(const QString &codec, int width, int height)
{
    const QByteArray mime = mimeFor(codec);
    if (mime.isEmpty())
        return false;
    if (!initialize())
        return false;

    DroidMediaCodecMetaData meta;
    std::memset(&meta, 0, sizeof(meta));
    meta.type = mime.constData();
    meta.width = width;
    meta.height = height;
    meta.fps = 30; // nominal; decoders are not gated on exact fps

    return droid_media_codec_is_supported(&meta, false /* decoder */);
}
