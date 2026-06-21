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

#ifndef VIDEOSURFACE_H
#define VIDEOSURFACE_H

#include <QQuickPaintedItem>
#include <QImage>

// VideoSurface is the QML video sink shared by the CPU-buffer backends: libVLC
// (vmem) and the droidmedia first cut (lock_ycbcr → swscale) both hand it each
// finished frame as a QImage via a queued signal, so it always arrives on the
// GUI thread, and it paints it. A QQuickPaintedItem keeps this simple and
// correct; a zero-copy QSGTexture path can replace paint() later without
// touching the QML or the backends.
class VideoSurface : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
    explicit VideoSurface(QQuickItem *parent = nullptr);

    bool active() const { return !m_frame.isNull(); }

    void paint(QPainter *painter) override;

public slots:
    // Deliver a decoded frame. Called via a queued connection from a backend,
    // i.e. always on the GUI thread; the QImage is an already-detached copy.
    void presentFrame(const QImage &frame);

    // Drop the current frame (e.g. on stop) and repaint black.
    void clear();

signals:
    void activeChanged();

private:
    QImage m_frame;
};

#endif // VIDEOSURFACE_H
