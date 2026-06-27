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

#ifndef IMAGEEDITOR_H
#define IMAGEEDITOR_H

#include <QObject>
#include <QString>
#include <QRectF>
#include <QVariantList>

// QML-facing image editor. The QML editor page drives interactive crop + drawing
// over a fitted preview, then hands the result here as resolution-independent
// vectors so the original image is re-rendered (and cropped) at FULL resolution.
//
// The original is first rotated by `rotation` (a multiple of 90°, clockwise);
// the crop and annotations are then interpreted in that rotated frame, exactly
// as the QML editor previews them.
//
// Coordinate convention (everything normalised against the rotated,
// EXIF-corrected image, x/y in [0..1]):
//   crop          — QRectF(x, y, w, h)
//   annotations   — list of maps, drawn before the crop is applied:
//       { type: "free"|"circle"|"arrow",
//         color: "#rrggbb",
//         width: <stroke width as a fraction of image width>,
//         points: [ { x, y }, … ] }   // free: polyline; circle/arrow: 2 points
//
// On success a new file is written next to the source (basename + "_edit"),
// never overwriting the original, and its path is returned (also via saved()).
class ImageEditor : public QObject
{
    Q_OBJECT
public:
    explicit ImageEditor(QObject *parent = nullptr);

    Q_INVOKABLE QString save(const QString &srcPath,
                             const QRectF &crop,
                             const QVariantList &annotations,
                             int rotation = 0);

signals:
    void saved(const QString &path);
    void error(const QString &message);
};

#endif // IMAGEEDITOR_H
