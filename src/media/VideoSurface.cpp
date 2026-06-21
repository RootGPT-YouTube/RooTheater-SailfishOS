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

#include "VideoSurface.h"

#include <QPainter>

VideoSurface::VideoSurface(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    // Black where no frame has arrived yet; opaque painting is a touch cheaper.
    setOpaquePainting(true);
    setFillColor(Qt::black);
}

void VideoSurface::paint(QPainter *painter)
{
    if (m_frame.isNull()) {
        painter->fillRect(boundingRect(), Qt::black);
        return;
    }

    // Letterbox: preserve aspect ratio, centre inside the item.
    const QSizeF target = QSizeF(m_frame.size()).scaled(boundingRect().size(), Qt::KeepAspectRatio);
    QRectF dst(QPointF(0, 0), target);
    dst.moveCenter(boundingRect().center());

    if (dst != boundingRect())
        painter->fillRect(boundingRect(), Qt::black);
    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter->drawImage(dst, m_frame);
}

void VideoSurface::presentFrame(const QImage &frame)
{
    const bool wasActive = active();
    m_frame = frame;
    if (wasActive != active())
        emit activeChanged();
    update();
}

void VideoSurface::clear()
{
    if (m_frame.isNull())
        return;
    m_frame = QImage();
    emit activeChanged();
    update();
}
