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

#ifndef TRACKCOVERPROVIDER_H
#define TRACKCOVERPROVIDER_H

#include <QQuickImageProvider>

// Path-keyed, lazy embedded-cover provider for the gallery grids. Unlike the
// single-slot CoverImageProvider (driven by MediaEngine for the now-playing
// track), this decodes the album art straight from whatever file the id names,
// so QML can show per-track / per-album covers on demand via
// "image://rttrackcover/<percent-encoded-file-path>". Returns a null image when
// the file has no embedded art, letting QML fall back to a placeholder.
//
// Requests are forced asynchronous: each one opens a container with ffmpeg
// (MediaProbe::coverArt), which must not block the GUI thread when a grid pulls
// many covers at once.
class TrackCoverProvider : public QQuickImageProvider
{
public:
    TrackCoverProvider()
        : QQuickImageProvider(QQuickImageProvider::Image,
                              QQuickImageProvider::ForceAsynchronousImageLoading) {}

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};

#endif // TRACKCOVERPROVIDER_H
