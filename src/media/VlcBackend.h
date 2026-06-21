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

#ifndef VLCBACKEND_H
#define VLCBACKEND_H

#include <QObject>
#include <QString>
#include <QImage>
#include <QTimer>
#include <vector>
#include <cstdint>

#include "VideoSurface.h"

struct libvlc_instance_t;
struct libvlc_media_player_t;

// VlcBackend is the Layer 3 player: it drives libvlc and renders video through
// the vmem (CPU buffer) callbacks into a VideoSurface. It is the QML-facing
// counterpart of the QtMultimedia MediaPlayer, used when the MediaEngine facade
// routes a source to the libvlc backend (exotic codecs/protocols/subtitles).
// Audio is handled by libvlc's own pulse output; only video crosses into Qt.
class VlcBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(VideoSurface *videoOutput READ videoOutput WRITE setVideoOutput NOTIFY videoOutputChanged)
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY stateChanged)
    Q_PROPERTY(qlonglong position READ position NOTIFY positionChanged)
    Q_PROPERTY(qlonglong duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(bool available READ available CONSTANT)

public:
    // Mirrors libvlc_state_t, narrowed to what the UI needs.
    enum State { Stopped, Opening, Buffering, Playing, Paused, Ended, Error };
    Q_ENUM(State)

    explicit VlcBackend(QObject *parent = nullptr);
    ~VlcBackend() override;

    VideoSurface *videoOutput() const { return m_output; }
    void setVideoOutput(VideoSurface *output);

    State state() const { return m_state; }
    bool playing() const { return m_state == Playing; }
    qlonglong position() const { return m_position; }
    qlonglong duration() const { return m_duration; }
    bool seekable() const { return m_seekable; }
    bool available() const { return m_vlc != nullptr; }

    Q_INVOKABLE void play(const QString &url);
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void togglePause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(qlonglong ms);

signals:
    void videoOutputChanged();
    void stateChanged();
    void positionChanged();
    void durationChanged();
    void seekableChanged();
    void frameReady(const QImage &frame);

private slots:
    void poll();

private:
    // vmem callbacks (run on libvlc's video thread; opaque == this).
    static unsigned setupCb(void **opaque, char *chroma, unsigned *width,
                            unsigned *height, unsigned *pitches, unsigned *lines);
    static void cleanupCb(void *opaque);
    static void *lockCb(void *opaque, void **planes);
    static void unlockCb(void *opaque, void *picture, void *const *planes);
    static void displayCb(void *opaque, void *picture);

    void setState(State s);

    libvlc_instance_t *m_vlc = nullptr;
    libvlc_media_player_t *m_player = nullptr;
    VideoSurface *m_output = nullptr;

    // vmem frame buffer (RV32 = 32-bit RGB), reallocated by setupCb.
    std::vector<uint8_t> m_buffer;
    unsigned m_width = 0;
    unsigned m_height = 0;
    unsigned m_pitch = 0;

    State m_state = Stopped;
    qlonglong m_position = 0;
    qlonglong m_duration = 0;
    bool m_seekable = false;
    QTimer m_pollTimer;
};

#endif // VLCBACKEND_H
