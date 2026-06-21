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

#include "TrackCoverProvider.h"
#include "MediaProbe.h"

#include <QImage>
#include <QUrl>

QImage TrackCoverProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    // QML hands us the part after "image://rttrackcover/". The caller percent-
    // encodes the file path (encodeURIComponent) so slashes don't split the id;
    // undo that to get the real path.
    const QString path = QUrl::fromPercentEncoding(id.toUtf8());

    const QByteArray art = MediaProbe::coverArt(path);
    QImage img;
    if (!art.isEmpty())
        img.loadFromData(art);
    if (img.isNull())
        return img; // null → QML Image status Error, page shows its placeholder

    if (requestedSize.isValid() && !requestedSize.isEmpty())
        img = img.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    if (size)
        *size = img.size();
    return img;
}
