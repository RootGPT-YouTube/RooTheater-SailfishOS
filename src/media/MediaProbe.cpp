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

#include "MediaProbe.h"

#include <QUrl>
#include <QAtomicInt>

extern "C" {
#include <libavformat/avformat.h>
#include <libavutil/dict.h>
#include <libavutil/error.h>
#include <libavutil/display.h>
}

#include <cmath>
#include <cstdint>

namespace {

// avformat_network_init() must run once before opening network URLs. Guarded so
// repeated probes don't re-init; ffmpeg ref-counts internally but we avoid the
// churn. (avformat_network_deinit is intentionally never called — the network
// stack lives for the whole process.)
void ensureNetworkInit()
{
    static QAtomicInt done(0);
    if (done.testAndSetAcquire(0, 1))
        avformat_network_init();
}

QString averr(int code)
{
    char buf[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(code, buf, sizeof(buf));
    return QString::fromUtf8(buf);
}

} // namespace

MediaProbe::Result MediaProbe::probe(const QString &url)
{
    Result r;
    r.url = url;

    // A non-empty, non-"file" scheme means a network source. A bare path or a
    // file:// URL is local. QUrl::scheme() is empty for plain filesystem paths.
    const QString scheme = QUrl(url).scheme();
    r.isNetwork = !scheme.isEmpty() && scheme != QLatin1String("file");
    if (r.isNetwork)
        ensureNetworkInit();

    // libavformat wants the bare path for local files (a "file://" prefix also
    // works via its file protocol, but a plain path is the common case here).
    const QByteArray src = url.toUtf8();

    AVFormatContext *fmt = nullptr;
    int rc = avformat_open_input(&fmt, src.constData(), nullptr, nullptr);
    if (rc < 0) {
        r.error = QStringLiteral("open failed: %1").arg(averr(rc));
        return r;
    }

    rc = avformat_find_stream_info(fmt, nullptr);
    if (rc < 0) {
        r.error = QStringLiteral("stream info failed: %1").arg(averr(rc));
        avformat_close_input(&fmt);
        return r;
    }

    if (fmt->iformat) {
        r.formatName = QString::fromUtf8(fmt->iformat->name ? fmt->iformat->name : "");
        r.container = QString::fromUtf8(fmt->iformat->long_name ? fmt->iformat->long_name : "");
    }
    if (fmt->duration != AV_NOPTS_VALUE && fmt->duration > 0)
        r.durationMs = static_cast<qint64>(fmt->duration) * 1000 / AV_TIME_BASE;

    // Pick the first video and first audio stream. av_find_best_stream would
    // also work, but a straight scan keeps the dependency surface minimal and
    // lets us report "has audio/video" plus the leading track of each.
    for (unsigned i = 0; i < fmt->nb_streams; ++i) {
        const AVStream *st = fmt->streams[i];
        const AVCodecParameters *par = st->codecpar;
        if (!par)
            continue;
        // An "attached picture" is cover art (e.g. an MP3's album thumbnail), NOT
        // a real video track — capture its bytes (for display during audio
        // playback) and skip it, so audio files with cover art are detected as
        // audio-only (→ QtMultimedia) instead of being mistaken for exotic video
        // and sent to the libVLC path.
        if (st->disposition & AV_DISPOSITION_ATTACHED_PIC) {
            if (r.coverArt.isEmpty() && st->attached_pic.data && st->attached_pic.size > 0)
                r.coverArt = QByteArray(reinterpret_cast<const char *>(st->attached_pic.data),
                                        st->attached_pic.size);
            continue;
        }
        const char *name = avcodec_get_name(par->codec_id);
        if (par->codec_type == AVMEDIA_TYPE_VIDEO && !r.hasVideo) {
            r.hasVideo = true;
            r.videoCodec = QString::fromUtf8(name ? name : "");
            r.width = par->width;
            r.height = par->height;
            // Container display rotation (e.g. phone-camera videos). The raw HW
            // decode path ignores it, so we surface it and apply it ourselves.
            const AVPacketSideData *sd = av_packet_side_data_get(
                par->coded_side_data, par->nb_coded_side_data, AV_PKT_DATA_DISPLAYMATRIX);
            if (sd && sd->data) {
                // av_display_rotation_get is counter-clockwise; clockwise = its negative.
                int cw = static_cast<int>(std::lround(-av_display_rotation_get(
                    reinterpret_cast<const int32_t *>(sd->data))));
                r.rotation = ((cw % 360) + 360) % 360;
            }
        } else if (par->codec_type == AVMEDIA_TYPE_AUDIO && !r.hasAudio) {
            r.hasAudio = true;
            r.audioCodec = QString::fromUtf8(name ? name : "");
        }
    }

    avformat_close_input(&fmt);
    r.ok = true;
    return r;
}

QByteArray MediaProbe::coverArt(const QString &url)
{
    QByteArray out;
    AVFormatContext *fmt = nullptr;
    if (avformat_open_input(&fmt, url.toUtf8().constData(), nullptr, nullptr) < 0)
        return out;
    if (avformat_find_stream_info(fmt, nullptr) >= 0) {
        for (unsigned i = 0; i < fmt->nb_streams; ++i) {
            const AVStream *st = fmt->streams[i];
            if ((st->disposition & AV_DISPOSITION_ATTACHED_PIC)
                && st->attached_pic.data && st->attached_pic.size > 0) {
                out = QByteArray(reinterpret_cast<const char *>(st->attached_pic.data),
                                 st->attached_pic.size);
                break;
            }
        }
    }
    avformat_close_input(&fmt);
    return out;
}

QVariantMap MediaProbe::metadata(const QString &url)
{
    QVariantMap out;
    AVFormatContext *fmt = nullptr;
    if (avformat_open_input(&fmt, url.toUtf8().constData(), nullptr, nullptr) < 0)
        return out;
    avformat_find_stream_info(fmt, nullptr);

    auto collect = [&out](AVDictionary *d) {
        AVDictionaryEntry *e = nullptr;
        while ((e = av_dict_get(d, "", e, AV_DICT_IGNORE_SUFFIX))) {
            const QString key = QString::fromUtf8(e->key).toLower();
            const QString val = QString::fromUtf8(e->value);
            if (!key.isEmpty() && !val.isEmpty() && !out.contains(key))
                out.insert(key, val); // first hit wins (format-level before streams)
        }
    };
    if (fmt->metadata)
        collect(fmt->metadata);
    for (unsigned i = 0; i < fmt->nb_streams; ++i)
        if (fmt->streams[i]->metadata)
            collect(fmt->streams[i]->metadata);

    avformat_close_input(&fmt);
    return out;
}
