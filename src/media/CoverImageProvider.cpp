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

#include "CoverImageProvider.h"

CoverImageProvider *g_coverProvider = nullptr;

QImage CoverImageProvider::requestImage(const QString &, QSize *size, const QSize &requestedSize)
{
    QMutexLocker lock(&m_mutex);
    QImage img = m_image;
    if (img.isNull())
        return img;
    if (requestedSize.isValid() && !requestedSize.isEmpty())
        img = img.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    if (size)
        *size = img.size();
    return img;
}

void CoverImageProvider::setImage(const QImage &image)
{
    QMutexLocker lock(&m_mutex);
    m_image = image;
}
