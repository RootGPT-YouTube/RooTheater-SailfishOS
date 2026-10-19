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

#ifndef SUBTITLEVIEW_H
#define SUBTITLEVIEW_H

#include <QQuickPaintedItem>
#include <QString>
#include <QTimer>
#include <memory>

struct SubtitleJob;

// SubtitleView draws text subtitles over the video, the same way whichever
// backend is playing (droidmedia, libVLC, QtMultimedia). It reads them itself on
// a worker thread, from one of two places:
//  • `file` — an external subtitle file: SubRip (.srt), WebVTT (.vtt) or
//    SubStation Alpha (.ass/.ssa), in UTF-8/UTF-16 or, failing that, Windows-1252
//    (what most Italian .srt files out there are);
//  • `source` + `streamIndex` — a text subtitle track inside the media (Matroska
//    SRT/ASS/WebVTT, MP4 tx3g), demuxed with ffmpeg on its own connection. The
//    vendored ffmpeg has no subtitle decoders, so the packets are read as the
//    text they are; bitmap tracks (DVD/PGS/DVB) are left to libVLC.
// Cues arrive progressively (an embedded track is read through the whole file),
// so the start of the film has subtitles at once. `position` is the playhead in
// ms; the current cues are drawn white with a black outline, bottom-centred.
class SubtitleView : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(QString file READ file WRITE setFile NOTIFY sourceChanged)
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(int streamIndex READ streamIndex WRITE setStreamIndex NOTIFY sourceChanged)
    Q_PROPERTY(qlonglong position READ position WRITE setPosition NOTIFY positionChanged)
    Q_PROPERTY(qreal fontPixelSize READ fontPixelSize WRITE setFontPixelSize NOTIFY fontPixelSizeChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(int cueCount READ cueCount NOTIFY loadingChanged)
    Q_PROPERTY(bool failed READ failed NOTIFY loadingChanged)
    Q_PROPERTY(QString text READ text NOTIFY textChanged)

public:
    explicit SubtitleView(QQuickItem *parent = nullptr);
    ~SubtitleView() override;

    QString file() const { return m_file; }
    void setFile(const QString &file);
    QString source() const { return m_source; }
    void setSource(const QString &source);
    int streamIndex() const { return m_streamIndex; }
    void setStreamIndex(int index);
    qlonglong position() const { return m_position; }
    void setPosition(qlonglong ms);
    qreal fontPixelSize() const { return m_fontPixelSize; }
    void setFontPixelSize(qreal px);
    bool loading() const { return m_loading; }
    int cueCount() const;
    bool failed() const;
    QString text() const { return m_text; }

    void paint(QPainter *painter) override;

    // Subtitle file next to `mediaPath` with the same base name (film.mkv →
    // film.srt, film.it.srt, ...), "" if none — what VLC loads on its own.
    Q_INVOKABLE static QString findSidecar(const QString &mediaPath);

signals:
    void sourceChanged();
    void positionChanged();
    void fontPixelSizeChanged();
    void loadingChanged();
    void textChanged();

private:
    void restart();                  // drop the current cues, start reading anew
    void refreshText();
    void checkJob();

    QString m_file;
    QString m_source;
    int m_streamIndex = -1;
    qlonglong m_position = 0;
    qreal m_fontPixelSize = 32;
    bool m_loading = false;
    QString m_text;
    std::shared_ptr<SubtitleJob> m_job;
    QTimer m_jobTimer;               // watches the worker while it reads
    bool m_restartPending = false;
};

#endif // SUBTITLEVIEW_H
