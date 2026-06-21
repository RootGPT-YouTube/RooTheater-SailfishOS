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

#include "MediaEngine.h"
#include "CoverImageProvider.h"

#include <QtConcurrent/QtConcurrentRun>
#include <QImage>

#ifdef HAVE_DROIDMEDIA
#include "DroidCodec.h"
#endif

MediaEngine::MediaEngine(QObject *parent)
    : QObject(parent)
{
    connect(&m_watcher, &QFutureWatcher<MediaProbe::Result>::finished,
            this, &MediaEngine::onProbeFinished);
}

void MediaEngine::probe(const QString &url)
{
    if (m_probing)
        return; // one probe at a time; ignore re-entrant calls

    m_probing = true;
    emit probingChanged();

    // ffmpeg open/find_stream_info blocks (network sources especially), so run
    // it on the global thread pool and collect the result via the watcher.
    m_watcher.setFuture(QtConcurrent::run(&MediaProbe::probe, url));
}

void MediaEngine::onProbeFinished()
{
    m_result = m_watcher.result();
    m_backend = chooseBackend(m_result);

    // Decode the embedded cover art (if any) into the shared image provider and
    // expose a cache-busting URL for QML; empty when the file has no cover.
    m_hasCover = false;
    m_coverSource.clear();
    if (!m_result.coverArt.isEmpty() && g_coverProvider) {
        QImage cover;
        if (cover.loadFromData(m_result.coverArt) && !cover.isNull()) {
            g_coverProvider->setImage(cover);
            m_coverSource = QStringLiteral("image://rtcover/%1").arg(++m_coverToken);
            m_hasCover = true;
        }
    }

    m_probing = false;
    emit probingChanged();
    emit probed();
}

MediaEngine::Backend MediaEngine::chooseBackend(const MediaProbe::Result &r)
{
    // Probe failed (unreadable/exotic container or protocol ffmpeg couldn't
    // open): hand it to libvlc, our broad-coverage backend.
    if (!r.ok)
        return Libvlc;

    // Audio-only: the QtMultimedia/gst-droid baseline plays it fine.
    if (!r.hasVideo)
        return QtMultimedia;

    const QString c = r.videoCodec;

#ifdef HAVE_DROIDMEDIA
    // Capability-driven (v0.3): take the direct HW path only if the device's
    // droidmedia actually exposes a decoder for this codec/size.
    if (DroidCodec::decoderSupported(c, r.width, r.height))
        return Droidmedia;
#else
    // No droidmedia at build time: still label the guaranteed HW codecs as
    // Droidmedia (they play via the QtMultimedia/gst-droid baseline for now).
    if (c == QLatin1String("h264") || c == QLatin1String("hevc") || c == QLatin1String("vp9"))
        return Droidmedia;
#endif

    // Common codecs gst-droid usually handles (HW opportunistically, else SW):
    // keep them on the QtMultimedia baseline.
    if (c == QLatin1String("h264") || c == QLatin1String("hevc") || c == QLatin1String("vp9")
        || c == QLatin1String("mpeg2video") || c == QLatin1String("mpeg4")
        || c == QLatin1String("vp8"))
        return QtMultimedia;

    // Anything else with video is "exotic" → libvlc coverage.
    return Libvlc;
}

QString MediaEngine::recommendedBackendName() const
{
    switch (m_backend) {
    case Droidmedia:   return QStringLiteral("droidmedia (HW)");
    case QtMultimedia: return QStringLiteral("QtMultimedia");
    case Libvlc:       return QStringLiteral("libVLC");
    case Software:     return QStringLiteral("software");
    case Auto:
    default:           return QStringLiteral("auto");
    }
}
