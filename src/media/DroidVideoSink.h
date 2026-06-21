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

#ifndef DROIDVIDEOSINK_H
#define DROIDVIDEOSINK_H

#include <QQuickItem>
#include <QMutex>
#include <QVector>

struct _DroidMediaBuffer;

// DroidVideoSink is the zero-copy video surface for the droidmedia HW path
// (v0.3.3). The decoder hands it gralloc DroidMediaBuffers; the sink wraps each
// in an EGLImage and draws it as a GL_TEXTURE_EXTERNAL_OES scene-graph node — no
// CPU touch of the pixels. All EGL/GL work happens on the Qt render thread in
// updatePaintNode(); presentBuffer() is the cross-thread handoff from the
// droidmedia output thread. (The libVLC CPU path keeps using VideoSurface.)
class DroidVideoSink : public QQuickItem
{
    Q_OBJECT
public:
    explicit DroidVideoSink(QQuickItem *parent = nullptr);
    ~DroidVideoSink() override;

    // Called from the droidmedia output thread. Ownership of `buffer` transfers
    // to the sink, which releases it back to the pool once it has been replaced
    // by a newer frame (or on reset/teardown). Thread-safe.
    void presentBuffer(_DroidMediaBuffer *buffer);

    // Drop any held/pending buffers and clear the surface (e.g. on stop).
    Q_INVOKABLE void reset();

protected:
    QSGNode *updatePaintNode(QSGNode *old, UpdatePaintNodeData *) override;
    void releaseResources() override;

private slots:
    void requestUpdate() { update(); }

private:
    void releaseBuffer(_DroidMediaBuffer *buffer); // render-thread: release to pool

    QMutex m_mutex;
    _DroidMediaBuffer *m_pending = nullptr;   // newest, awaiting the render thread
    _DroidMediaBuffer *m_current = nullptr;   // bound in the live EGLImage
    void *m_currentImage = nullptr;           // EGLImageKHR of m_current
    QVector<void *> m_deadImages;             // EGLImageKHRs awaiting render-thread destroy
    unsigned int m_texture = 0;               // GLuint, GL_TEXTURE_EXTERNAL_OES
    int m_srcW = 0;                           // buffer (aligned) width
    int m_srcH = 0;                           // buffer (aligned) height
    float m_cropL = 0, m_cropT = 0, m_cropR = 1, m_cropB = 1; // normalized texcoords
};

#endif // DROIDVIDEOSINK_H
