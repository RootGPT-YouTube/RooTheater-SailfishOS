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

#ifndef MEDIAENGINE_H
#define MEDIAENGINE_H

#include <QObject>
#include <QString>
#include <QFutureWatcher>

#include "MediaProbe.h"

// MediaEngine is the C++ media-engine facade exposed to QML. v0.2 lands its
// foundation: it probes a source with ffmpeg (off the GUI thread) and, from the
// probe, picks the backend that *should* play it — the capability-driven
// selection described in the architecture notes. Playback itself still flows
// through the QtMultimedia baseline (Layer 2); the libvlc backend (Layer 3) and
// the direct droidmedia HW path (Layer 1) plug in behind this same facade in
// later versions, so QML keeps talking to MediaEngine regardless of backend.
class MediaEngine : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool probing READ probing NOTIFY probingChanged)
    Q_PROPERTY(bool valid READ valid NOTIFY probed)
    Q_PROPERTY(QString errorString READ errorString NOTIFY probed)
    Q_PROPERTY(QString url READ url NOTIFY probed)
    Q_PROPERTY(bool network READ network NOTIFY probed)
    Q_PROPERTY(QString container READ container NOTIFY probed)
    Q_PROPERTY(qlonglong durationMs READ durationMs NOTIFY probed)
    Q_PROPERTY(bool hasVideo READ hasVideo NOTIFY probed)
    Q_PROPERTY(QString videoCodec READ videoCodec NOTIFY probed)
    Q_PROPERTY(int width READ width NOTIFY probed)
    Q_PROPERTY(int height READ height NOTIFY probed)
    Q_PROPERTY(int rotation READ rotation NOTIFY probed)
    Q_PROPERTY(bool hasAudio READ hasAudio NOTIFY probed)
    Q_PROPERTY(QString audioCodec READ audioCodec NOTIFY probed)
    Q_PROPERTY(bool hasCover READ hasCover NOTIFY probed)
    Q_PROPERTY(QString coverSource READ coverSource NOTIFY probed)
    Q_PROPERTY(Backend recommendedBackend READ recommendedBackend NOTIFY probed)
    Q_PROPERTY(QString recommendedBackendName READ recommendedBackendName NOTIFY probed)

public:
    // Which engine layer should handle a source. Mirrors the layered design:
    // Droidmedia = direct zero-copy HW path (v0.3); QtMultimedia = gst-droid
    // baseline (v0.1); Libvlc = exotic-coverage backend (v0.2 Phase B);
    // Software = ffmpeg SW decode fallback. Auto = not decided / unknown.
    enum Backend {
        Auto = 0,
        Droidmedia,
        QtMultimedia,
        Libvlc,
        Software
    };
    Q_ENUM(Backend)

    explicit MediaEngine(QObject *parent = nullptr);

    bool probing() const { return m_probing; }
    bool valid() const { return m_result.ok; }
    QString errorString() const { return m_result.error; }
    QString url() const { return m_result.url; }
    bool network() const { return m_result.isNetwork; }
    QString container() const { return m_result.container; }
    qlonglong durationMs() const { return m_result.durationMs; }
    bool hasVideo() const { return m_result.hasVideo; }
    QString videoCodec() const { return m_result.videoCodec; }
    int width() const { return m_result.width; }
    int height() const { return m_result.height; }
    int rotation() const { return m_result.rotation; }
    bool hasAudio() const { return m_result.hasAudio; }
    QString audioCodec() const { return m_result.audioCodec; }
    bool hasCover() const { return m_hasCover; }
    QString coverSource() const { return m_coverSource; }
    Backend recommendedBackend() const { return m_backend; }
    QString recommendedBackendName() const;

    // Probe `url` asynchronously (ffmpeg demux/probe runs on a worker thread).
    // Emits probed() when the result and recommendedBackend are ready.
    Q_INVOKABLE void probe(const QString &url);

signals:
    void probingChanged();
    void probed();

private slots:
    void onProbeFinished();

private:
    // Capability-driven backend choice from a probe result. v0.2 implements the
    // decision skeleton; the live droidmedia HW-decoder query lands with v0.3.
    static Backend chooseBackend(const MediaProbe::Result &r);

    bool m_probing = false;
    MediaProbe::Result m_result;
    Backend m_backend = Auto;
    QFutureWatcher<MediaProbe::Result> m_watcher;

    // Cover art: decoded into the shared CoverImageProvider; coverSource is the
    // "image://rtcover/<token>" URL (token only busts the QML pixmap cache).
    bool m_hasCover = false;
    QString m_coverSource;
    int m_coverToken = 0;
};

#endif // MEDIAENGINE_H
