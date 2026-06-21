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

#ifndef COVERIMAGEPROVIDER_H
#define COVERIMAGEPROVIDER_H

#include <QQuickImageProvider>
#include <QImage>
#include <QMutex>

// In-memory image provider for the embedded cover art of audio files. MediaEngine
// pushes the decoded cover here on probe; QML shows it via "image://rtcover/<tok>"
// (the token only busts the QML pixmap cache). Registered once on the QML engine
// in main(); reached from MediaEngine through the global pointer below.
class CoverImageProvider : public QQuickImageProvider
{
public:
    CoverImageProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
    void setImage(const QImage &image);

private:
    QImage m_image;
    QMutex m_mutex;
};

extern CoverImageProvider *g_coverProvider; // owned by the QML engine, set in main()

#endif // COVERIMAGEPROVIDER_H
